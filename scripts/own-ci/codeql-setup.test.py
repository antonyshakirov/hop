import hashlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

SOURCE = Path(__file__).with_name('codeql-setup.py')
module = None
if SOURCE.exists():
    spec = importlib.util.spec_from_file_location('codeql_setup', SOURCE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(module, 'Authenticated SDK preparation is not implemented')
        self.temp = tempfile.TemporaryDirectory(prefix='codeql-setup-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()

    def archive(self, entries):
        path = self.base / 'fixture.tar'
        with tarfile.open(path, 'w') as archive:
            for name, kind, value in entries:
                item = tarfile.TarInfo(name)
                item.mode = 0o755 if name.endswith('tool') else 0o644
                if kind == 'symlink':
                    item.type = tarfile.SYMTYPE
                    item.linkname = value
                elif kind == 'hardlink':
                    item.type = tarfile.LNKTYPE
                    item.linkname = value
                elif kind == 'fifo':
                    item.type = tarfile.FIFOTYPE
                else:
                    item.size = len(value)
                archive.addfile(item, io.BytesIO(value) if kind == 'file' else None)
        return path, hashlib.sha256(path.read_bytes()).hexdigest()

    def test_roundtrip_and_pinned_tree(self):
        archive, digest = self.archive([('codeql/bin/tool', 'file', b'public'), ('codeql/link', 'symlink', 'bin/tool'), ('codeql/copy', 'hardlink', 'codeql/bin/tool')])
        first = module.prepare_sdk(archive, self.base / 'first', digest)
        self.assertEqual((Path(first['root']) / 'link').read_bytes(), b'public')
        second = module.prepare_sdk(archive, self.base / 'second', digest, first['sha256'])
        self.assertEqual(first['sha256'], second['sha256'])
        self.assertEqual(os.stat(Path(first['root']) / 'copy').st_ino, os.stat(Path(first['root']) / 'bin/tool').st_ino)

    def test_archive_hash_failure_precedes_destination_creation(self):
        archive, _ = self.archive([('codeql/tool', 'file', b'public')])
        destination = self.base / 'new'
        with self.assertRaises(Exception):
            module.prepare_sdk(archive, destination, '0' * 64)
        self.assertFalse(destination.exists())

    def test_fifo_archive_is_rejected_without_waiting_for_a_writer(self):
        fifo = self.base / 'not-an-archive'
        os.mkfifo(fifo)
        program = 'import importlib.util,sys; s=importlib.util.spec_from_file_location("setup",sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); m.prepare_sdk(sys.argv[2],sys.argv[3],"0"*64)'
        result = subprocess.run([sys.executable, '-c', program, str(SOURCE), str(fifo), str(self.base / 'new')], capture_output=True, text=True, timeout=2)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('SDK archive must be a regular file', result.stderr)
        self.assertFalse((self.base / 'new').exists())

    def test_existing_destination_is_untouched(self):
        archive, digest = self.archive([('codeql/tool', 'file', b'public')])
        destination = self.base / 'existing'
        destination.mkdir()
        (destination / 'canary').write_bytes(b'preserve')
        with self.assertRaises(Exception):
            module.prepare_sdk(archive, destination, digest)
        self.assertEqual((destination / 'canary').read_bytes(), b'preserve')

    def test_corrupt_expected_tree_never_publishes(self):
        archive, digest = self.archive([('codeql/tool', 'file', b'public')])
        with self.assertRaises(Exception):
            module.prepare_sdk(archive, self.base / 'new', digest, '0' * 64)
        self.assertFalse((self.base / 'new').exists())

    def test_unsafe_archive_members_are_rejected(self):
        cases = [
            [('codeql/../outside', 'file', b'forbidden')],
            [('/codeql/tool', 'file', b'forbidden')],
            [('outside/tool', 'file', b'forbidden')],
            [('codeql/link', 'symlink', '../../outside')],
            [('codeql/link', 'symlink', '/usr/bin/true')],
            [('codeql/link', 'symlink', '../codeql/tool')],
            [('codeql/link', 'symlink', 'link')],
            [('codeql/link', 'symlink', 'directory'), ('codeql/link/child', 'file', b'forbidden')],
            [('codeql/copy', 'hardlink', '../outside')],
            [('codeql/fifo', 'fifo', None)],
            [('codeql/tool', 'file', b'one'), ('codeql/tool', 'file', b'two')],
        ]
        for index, entries in enumerate(cases):
            with self.subTest(index=index):
                archive, digest = self.archive(entries)
                destination = self.base / ('bad-' + str(index))
                with self.assertRaises(Exception):
                    module.prepare_sdk(archive, destination, digest)
                self.assertFalse(destination.exists())
        self.assertFalse((self.base / 'outside').exists())


if __name__ == '__main__':
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__]))
    sys.exit(not result.wasSuccessful() or result.testsRun < 6 or bool(result.skipped))

import hashlib
import importlib.util
import io
import os
import selectors
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
        program = 'import importlib.util,sys; s=importlib.util.spec_from_file_location("setup",sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); print("ready",flush=True); m.prepare_sdk(sys.argv[2],sys.argv[3],"0"*64)'
        child = subprocess.Popen([sys.executable, '-B', '-I', '-c', program, str(SOURCE), str(fifo), str(self.base / 'new')], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            with selectors.DefaultSelector() as ready:
                ready.register(child.stdout, selectors.EVENT_READ)
                self.assertTrue(ready.select(timeout=10), 'Python helper did not finish startup')
                self.assertEqual(child.stdout.readline(), 'ready\n')
            # Startup cost is separate; the actual FIFO rejection still has two seconds.
            _, stderr = child.communicate(timeout=2)
            self.assertNotEqual(child.returncode, 0)
            self.assertIn('SDK archive must be a regular file', stderr)
        finally:
            if child.poll() is None:
                child.kill()
                child.communicate()
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


    def compatibility_fixture(self):
        archive, digest = self.archive([('codeql/swift/tools/osx64/extractor.real', 'file', b'original'), ('codeql/data', 'file', b'unchanged')])
        first = module.prepare_sdk(archive, self.base / 'reference', digest)
        target = Path(first['root']) / 'swift/tools/osx64/extractor.real'
        target.write_bytes(b'candidate')
        target.chmod(0o711)
        derived = module.hash_tree(Path(first['root']))
        candidate = self.base / 'extractor'
        candidate.write_bytes(b'candidate')
        manifest = dict(bundle=dict(sha256=digest), upstreamSdkTreeSha256=first['sha256'], sdkTreeSha256=derived['sha256'], compatibility=dict(extractorSha256=hashlib.sha256(b'candidate').hexdigest()))
        return archive, candidate, manifest

    def test_compatible_sdk_authenticates_both_trees_and_changes_only_extractor(self):
        archive, candidate, manifest = self.compatibility_fixture()
        result = module.prepare_compatible_sdk(archive, self.base / 'compatible', manifest, candidate)
        self.assertEqual(result['sha256'], manifest['sdkTreeSha256'])
        self.assertEqual((Path(result['root']) / 'data').read_bytes(), b'unchanged')
        self.assertEqual((Path(result['root']) / 'swift/tools/osx64/extractor.real').read_bytes(), b'candidate')

    def test_unreviewed_extractor_is_rejected_before_creating_destination(self):
        archive, candidate, manifest = self.compatibility_fixture()
        candidate.write_bytes(b'corrupt')
        with self.assertRaisesRegex(ValueError, 'extractor authentication failed'):
            module.prepare_compatible_sdk(archive, self.base / 'new', manifest, candidate)
        self.assertFalse((self.base / 'new').exists())

    def test_linked_or_special_extractor_is_rejected(self):
        archive, candidate, manifest = self.compatibility_fixture()
        link = self.base / 'link'
        link.symlink_to(candidate)
        fifo = self.base / 'fifo'
        os.mkfifo(fifo)
        for index, path in enumerate([link, fifo]):
            with self.subTest(path=path):
                with self.assertRaises((OSError, ValueError)):
                    module.prepare_compatible_sdk(archive, self.base / ('new-' + str(index)), manifest, path)
                self.assertFalse((self.base / ('new-' + str(index))).exists())

    def test_corrupt_upstream_or_derived_pin_cleans_only_owned_destination(self):
        archive, candidate, manifest = self.compatibility_fixture()
        for index, key in enumerate(['upstreamSdkTreeSha256', 'sdkTreeSha256']):
            with self.subTest(key=key):
                altered = dict(manifest, **{key: '0' * 64})
                with self.assertRaisesRegex(ValueError, 'tree authentication failed'):
                    module.prepare_compatible_sdk(archive, self.base / ('new-' + str(index)), altered, candidate)
                self.assertFalse((self.base / ('new-' + str(index))).exists())
        self.assertEqual(candidate.read_bytes(), b'candidate')


    def test_compatible_existing_destination_is_untouched(self):
        archive, candidate, manifest = self.compatibility_fixture()
        destination = self.base / 'existing'
        destination.mkdir()
        (destination / 'canary').write_bytes(b'preserve')
        with self.assertRaises(FileExistsError):
            module.prepare_compatible_sdk(archive, destination, manifest, candidate)
        self.assertEqual((destination / 'canary').read_bytes(), b'preserve')

    def test_compatibility_pins_are_required_before_destination_creation(self):
        archive, candidate, manifest = self.compatibility_fixture()
        for index, key in enumerate(['upstreamSdkTreeSha256', 'sdkTreeSha256', 'compatibility']):
            with self.subTest(key=key):
                altered = dict(manifest)
                altered.pop(key)
                with self.assertRaisesRegex(ValueError, 'Missing reviewed compatibility'):
                    module.prepare_compatible_sdk(archive, self.base / ('bad-' + str(index)), altered, candidate)
                self.assertFalse((self.base / ('bad-' + str(index))).exists())

    def test_cli_requires_reviewed_extractor_without_reading_archive(self):
        result = subprocess.run([sys.executable, '-B', '-I', str(SOURCE), '--archive', str(self.base / 'absent'), '--destination', str(self.base / 'new')], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 2)
        self.assertIn('--extractor is required', result.stderr)
        self.assertFalse((self.base / 'new').exists())


if __name__ == '__main__':
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__]))
    sys.exit(not result.wasSuccessful() or result.testsRun < 13 or bool(result.skipped))

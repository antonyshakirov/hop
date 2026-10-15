import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import tarfile
import tempfile
import unicodedata


def internal_link(root, link):
    cursor = root
    pending = list(link.relative_to(root).parts)
    count = 0
    while pending:
        part = pending.pop(0)
        if part in {'', '.'}:
            continue
        if part == '..':
            if cursor == root:
                raise ValueError('SDK link leaves the root')
            cursor = cursor.parent
            continue
        candidate = cursor / part
        try:
            metadata = candidate.lstat()
        except FileNotFoundError:
            metadata = None
        if metadata is not None and stat.S_ISLNK(metadata.st_mode):
            count += 1
            if count > 40:
                raise ValueError('SDK link is cyclic or too deep')
            target = os.readlink(candidate)
            target.encode('utf-8')
            if target.startswith('/'):
                raise ValueError('Absolute SDK links are not portable')
            pending = target.split('/') + pending
        else:
            cursor = candidate


def hash_tree(root):
    root = Path(root).absolute()
    if root.resolve(strict=True) != root or not stat.S_ISDIR(root.lstat().st_mode):
        raise ValueError('SDK root must be a canonical directory')
    records, links = [], []

    def visit(path):
        metadata = path.lstat()
        name = path.relative_to(root).as_posix() or '.'
        name.encode('utf-8')
        if stat.S_ISLNK(metadata.st_mode):
            target = os.readlink(path)
            target.encode('utf-8')
            records.append([name, 'l', 0, target])
            links.append(path)
        elif stat.S_ISDIR(metadata.st_mode):
            records.append([name, 'd', metadata.st_mode & 0o111, ''])
            for child in path.iterdir():
                visit(child)
        elif stat.S_ISREG(metadata.st_mode):
            digest = hashlib.sha256()
            descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
            with os.fdopen(descriptor, 'rb') as stream:
                before = os.fstat(stream.fileno())
                if not stat.S_ISREG(before.st_mode) or (before.st_dev, before.st_ino) != (metadata.st_dev, metadata.st_ino):
                    raise ValueError('SDK file changed before hashing')
                total = 0
                for block in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(block)
                    total += len(block)
                after, current = os.fstat(stream.fileno()), path.lstat()
                if total != before.st_size or after.st_size != before.st_size or after.st_mtime_ns != before.st_mtime_ns or (current.st_dev, current.st_ino, current.st_mode & 0o111) != (before.st_dev, before.st_ino, metadata.st_mode & 0o111):
                    raise ValueError('SDK file changed while hashing')
            records.append([name, 'f', metadata.st_mode & 0o111, digest.hexdigest()])
        else:
            raise ValueError('SDK contains a non-file entry')

    visit(root)
    for link in links:
        internal_link(root, link)
    digest = hashlib.sha256(b'codeql-sdk-tree-v1\n')
    for record in sorted(records, key=lambda item: item[0].encode('utf-8')):
        digest.update((json.dumps(record, ensure_ascii=False, separators=(',', ':')) + '\n').encode('utf-8'))
    return dict(sha256=digest.hexdigest(), entries=len(records))


@contextmanager
def read_tar(stream):
    stream.seek(0)
    magic = stream.read(4)
    stream.seek(0)
    if magic == b'\x28\xb5\x2f\xfd':
        try:
            import zstandard
        except ImportError as error:
            raise RuntimeError('Use an existing Python environment with zstandard; this setup never installs it') from error
        with zstandard.ZstdDecompressor().stream_reader(stream, closefd=False) as reader:
            with tarfile.open(fileobj=reader, mode='r|') as archive:
                yield archive
    else:
        with tarfile.open(fileobj=stream, mode='r|') as archive:
            yield archive


def member_name(value):
    while value.startswith('./'):
        value = value[2:]
    value = value.rstrip('/')
    parts = value.split('/')
    if not value or parts[0] != 'codeql' or any(part in {'', '.', '..'} for part in parts) or '\\' in value or '\x00' in value:
        raise ValueError('Archive member is outside the canonical codeql subtree')
    value.encode('utf-8')
    return value


def validate_members(members):
    entries, normalized = {}, set()
    total = 0
    for item in members:
        name = member_name(item.name)
        key = unicodedata.normalize('NFD', name).casefold()
        if name in entries or key in normalized or item.mode & 0o6000 or not (item.isfile() or item.isdir() or item.issym() or item.islnk()):
            raise ValueError('Unsafe or duplicate SDK archive member')
        if name == 'codeql' and not item.isdir():
            raise ValueError('SDK archive root must be a directory')
        entries[name] = item
        normalized.add(key)
        total += item.size
        if len(entries) > 50000 or total > 4 * 1024 ** 3 or item.size < 0 or item.size > 1024 ** 3:
            raise ValueError('SDK archive exceeds the preparation bounds')
    if not entries:
        raise ValueError('Empty SDK archive')
    for name, item in entries.items():
        for parent in Path(name).parents:
            if str(parent) in entries and not entries[str(parent)].isdir():
                raise ValueError('Archive member has a non-directory parent')
        if item.issym():
            if not item.linkname or item.linkname.startswith('/') or '\\' in item.linkname or '\x00' in item.linkname:
                raise ValueError('Unsafe SDK symlink')
            cursor, pending, count = [], name.split('/'), 0
            while pending:
                part = pending.pop(0)
                if part in {'', '.'}:
                    continue
                if part == '..':
                    if len(cursor) <= 1:
                        raise ValueError('SDK link leaves the root')
                    cursor.pop()
                    continue
                candidate = '/'.join(cursor + [part])
                entry = entries.get(candidate)
                if entry is not None and entry.issym():
                    count += 1
                    if count > 40:
                        raise ValueError('SDK link is cyclic or too deep')
                    pending = entry.linkname.split('/') + pending
                else:
                    cursor.append(part)
        elif item.islnk():
            hardlink_target(item, entries)
    return entries


def hardlink_target(item, entries):
    for _ in range(40):
        name = member_name(item.linkname)
        target = entries.get(name)
        if target is None:
            raise ValueError('SDK hardlink target is missing')
        if target.isfile():
            return name
        if not target.islnk():
            raise ValueError('SDK hardlinks must target a regular archived file')
        item = target
    raise ValueError('SDK hardlink cycle')


def remove_owned(destination, identity):
    current = destination.lstat()
    if (current.st_dev, current.st_ino) != identity or not stat.S_ISDIR(current.st_mode):
        raise RuntimeError('Refusing cleanup of a replaced SDK destination')
    os.chmod(destination, 0o700)
    for path, directories, _ in os.walk(destination, followlinks=False):
        for name in directories:
            child = Path(path) / name
            if not child.is_symlink():
                os.chmod(child, 0o700)
    shutil.rmtree(destination)


def prepare_sdk(archive_path, destination, archive_sha256, tree_sha256=None):
    if len(archive_sha256) != 64 or any(ch not in '0123456789abcdef' for ch in archive_sha256):
        raise ValueError('Missing reviewed archive SHA-256')
    destination = Path(destination)
    destination = destination.parent.resolve(strict=True) / destination.name
    if destination.exists() or destination.is_symlink():
        raise FileExistsError('SDK preparation requires a new destination')
    descriptor = os.open(archive_path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, 'rb') as source, tempfile.TemporaryFile(dir=destination.parent) as stable:
        if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
            raise ValueError('SDK archive must be a regular file')
        digest, size = hashlib.sha256(), 0
        for block in iter(lambda: source.read(1024 * 1024), b''):
            size += len(block)
            if size > 1024 ** 3:
                raise ValueError('SDK archive is too large')
            digest.update(block)
            stable.write(block)
        if digest.hexdigest() != archive_sha256:
            raise ValueError('CodeQL archive authentication failed')
        with read_tar(stable) as archive:
            entries = validate_members(archive)
        destination.mkdir(mode=0o700)
        metadata = destination.lstat()
        identity = metadata.st_dev, metadata.st_ino
        try:
            with read_tar(stable) as archive:
                for item in archive:
                    name = member_name(item.name)
                    target = destination / name
                    if item.isdir():
                        target.mkdir(parents=True, exist_ok=True, mode=0o755)
                    elif item.isfile():
                        target.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
                        with archive.extractfile(item) as stream, target.open('xb') as output:
                            shutil.copyfileobj(stream, output, length=1024 * 1024)
                        target.chmod(0o600 | item.mode & 0o111)
            for name, item in entries.items():
                target = destination / name
                if item.islnk():
                    target.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
                    os.link(destination / hardlink_target(item, entries), target, follow_symlinks=False)
            for name, item in entries.items():
                if item.issym():
                    target = destination / name
                    target.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
                    target.symlink_to(item.linkname)
            for name, item in sorted(entries.items(), key=lambda pair: pair[0].count('/'), reverse=True):
                if item.isdir():
                    (destination / name).chmod(0o600 | item.mode & 0o111)
            root = destination / 'codeql'
            result = hash_tree(root)
            if tree_sha256 is not None and result['sha256'] != tree_sha256:
                raise ValueError('Extracted CodeQL SDK tree authentication failed')
            return dict(root=str(root), archiveSha256=archive_sha256, **result)
        except BaseException:
            remove_owned(destination, identity)
            raise


def main():
    parser = argparse.ArgumentParser(description='Authenticate and extract an offline official CodeQL SDK')
    parser.add_argument('--archive', required=True)
    parser.add_argument('--destination', required=True)
    args = parser.parse_args()
    manifest = json.loads(Path(__file__).with_name('codeql-sdk.json').read_text())
    tree = manifest.get('sdkTreeSha256')
    if not isinstance(tree, str) or len(tree) != 64:
        raise ValueError('Missing reviewed CodeQL SDK tree pin')
    print(json.dumps(prepare_sdk(args.archive, args.destination, manifest['bundle']['sha256'], tree)))


if __name__ == '__main__':
    main()

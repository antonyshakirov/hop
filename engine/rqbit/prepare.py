import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description='Apply the pinned selective-storage engine patch.')
    parser.add_argument('source', type=Path)
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    package = Path(__file__).resolve().parent
    manifest = json.loads((package / 'source.json').read_text())
    patch = package / manifest['patch']
    if hashlib.sha256(patch.read_bytes()).hexdigest() != manifest['patch_sha256']:
        raise SystemExit('Patch checksum mismatch.')
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source, text=True).strip()
    if head != manifest['commit']:
        raise SystemExit('Source revision differs from source.json.')
    dirty = subprocess.check_output(['git', 'status', '--porcelain'], cwd=source)
    if dirty:
        raise SystemExit('Use a clean source checkout.')
    subprocess.run(['git', 'apply', '--check', str(patch)], cwd=source, check=True)
    subprocess.run(['git', 'apply', str(patch)], cwd=source, check=True)
    for name, expected in manifest['patched_files_sha256'].items():
        if hashlib.sha256((source / name).read_bytes()).hexdigest() != expected:
            raise SystemExit(f'Patched source checksum mismatch: {name}')
    print('Pinned source patch applied and verified.')


if __name__ == '__main__':
    main()

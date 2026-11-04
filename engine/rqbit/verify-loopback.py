import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request


def bencode(value):
    if isinstance(value, int):
        return b'i' + str(value).encode() + b'e'
    if isinstance(value, bytes):
        return str(len(value)).encode() + b':' + value
    if isinstance(value, list):
        return b'l' + b''.join(map(bencode, value)) + b'e'
    return b'd' + b''.join(bencode(key) + bencode(value[key]) for key in sorted(value)) + b'e'


def port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def wait_for(probe, description, timeout=30):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            value = probe()
            if value:
                return value
        except (OSError, urllib.error.URLError) as error:
            last = str(error)
        time.sleep(0.1)
    raise AssertionError(f'timeout: {description}; last={last}')


class Engine:
    def __init__(self, binary, root, logs, name, output, peer_port=None):
        self.root = root / name
        self.root.mkdir(exist_ok=True)
        self.api_port = port()
        self.peer_port = peer_port or port()
        self.output = output
        self.output.mkdir(parents=True, exist_ok=True)
        self.log = (logs / f'{name}.log').open('ab')
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(('RQBIT_', 'RUST_', 'XDG_'))}
        env.update(HOME=str(self.root), TMPDIR=str(root), RUST_LOG='info')
        command = [str(binary), '--disable-dht', '--disable-dht-persistence',
                   '--disable-trackers', '--disable-lsd', '--disable-upnp-port-forward',
                   '--listen-ip', '127.0.0.1', '--listen-port', str(self.peer_port),
                   '--http-api-listen-addr', f'127.0.0.1:{self.api_port}',
                   '--worker-threads', '2', 'server', 'start', str(output),
                   '--persistence-location', str(self.root / 'session'), '--fastresume']
        profile = '(version 1)(allow default)(deny network*)(allow network* (remote ip "localhost:*") (local ip "localhost:*"))'
        self.process = subprocess.Popen(['/usr/bin/sandbox-exec', '-p', profile, *command],
                                        env=env, stdout=self.log, stderr=subprocess.STDOUT)
        try:
            wait_for(lambda: self.process.poll() is None and self.request('/'), f'{name} HTTP ready', 10)
        except BaseException:
            self.close()
            raise

    def request(self, path, data=None, content_type='application/octet-stream'):
        request = urllib.request.Request(f'http://127.0.0.1:{self.api_port}' + path,
                                         data=data, headers={'Content-Type': content_type})
        with urllib.request.urlopen(request, timeout=2) as response:
            body = response.read()
        return json.loads(body) if body else {}

    def add(self, torrent, selection=None, peer=None):
        query = {'overwrite': 'true', 'output_folder': str(self.output), 'is_url': 'false'}
        if selection is not None:
            query['only_files'] = ','.join(map(str, selection))
        if peer:
            query['initial_peers'] = f'127.0.0.1:{peer}'
        result = self.request('/torrents?' + urllib.parse.urlencode(query), torrent)
        return result['id']

    def finished(self, torrent_id):
        def check():
            stats = self.request(f'/torrents/{torrent_id}/stats/v1')
            if stats['state'] == 'error':
                raise AssertionError(stats)
            return stats if stats['finished'] else None
        return wait_for(check, f'torrent {torrent_id} finished')

    def selection(self, torrent_id, ids):
        self.request(f'/torrents/{torrent_id}/update_only_files',
                     json.dumps({'only_files': ids}).encode(), 'application/json')

    def close(self):
        if self.process.poll() is None:
            self.process.send_signal(signal.SIGINT)
            try:
                self.process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        self.log.close()


def run_case(binary, root, logs, existing, aligned=False):
    lengths = [16384, 32768, 16384, 4096, 0] if aligned else [12000, 36000, 15000, 4096, 0]
    names = ['chosen/first.bin', 'skipped/middle.bin', 'chosen/last.bin', 'never/file.bin', 'empty/zero.bin']
    payloads = [bytes(((index * 29 + pos * 17) % 251 for pos in range(size)))
                for index, size in enumerate(lengths)]
    data = b''.join(payloads)
    info = {b'name': b'fixture', b'piece length': 16384,
            b'pieces': b''.join(hashlib.sha1(data[pos:pos + 16384]).digest()
                                for pos in range(0, len(data), 16384)),
            b'files': [{b'length': len(payload), b'path': [part.encode() for part in name.split('/')]}
                       for name, payload in zip(names, payloads)]}
    torrent = bencode({b'info': info})
    source = root / 'source'
    for name, payload in zip(names, payloads):
        path = source / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
    destination = root / 'download'
    sentinel = b'user-owned skipped file, keep these bytes'
    if existing:
        path = destination / names[1]
        path.parent.mkdir(parents=True)
        path.write_bytes(sentinel)
    engines = []
    def start(name, output, peer_port=None):
        engine = Engine(binary, root, logs, name, output, peer_port)
        engines.append(engine)
        return engine
    def verify(output, keep_sentinel=False):
        for index in [0, 2]:
            assert (output / names[index]).read_bytes() == payloads[index], names[index]
        assert not (output / 'never').exists()
        assert not (output / 'empty').exists()
        if keep_sentinel:
            assert (output / names[1]).read_bytes() == sentinel
        else:
            assert not (output / 'skipped').exists()
    try:
        seed = start('seed', source)
        seed.finished(seed.add(torrent))
        leecher = start('leecher', destination)
        tid = leecher.add(torrent, [0, 2], seed.peer_port)
        stats = leecher.finished(tid)
        verify(destination, existing)
        leecher.request(f'/torrents/{tid}/pause', b'')
        leecher.request(f'/torrents/{tid}/start', b'')
        leecher.finished(tid)
        seed.close()
        prior_port = leecher.peer_port
        leecher.close()
        leecher = start('leecher', destination, prior_port)
        restarted = leecher.finished(tid)
        verify(destination, existing)
        clone = start('clone', root / 'clone-download')
        clone_id = clone.add(torrent, [0, 2], leecher.peer_port)
        clone.finished(clone_id)
        verify(clone.output)
        clone.selection(clone_id, [])
        clone.selection(clone_id, [0, 2])
        clone.finished(clone_id)
        verify(clone.output)
        clone.selection(clone_id, [0, 1, 2])
        seed = start('seed-again', source)
        seed.finished(seed.add(torrent, peer=clone.peer_port))
        clone.finished(clone_id)
        for index in [0, 1, 2]:
            assert (clone.output / names[index]).read_bytes() == payloads[index]
        assert not (clone.output / 'never').exists()
        assert not (clone.output / 'empty').exists()
        return {'existing_skipped_sentinel': existing, 'aligned': aligned,
                'selected_sha256': [hashlib.sha256(payloads[index]).hexdigest() for index in [0, 2]],
                'initial_progress_bytes': stats['progress_bytes'],
                'restart_progress_bytes': restarted['progress_bytes'],
                'restart_without_seed': True, 'seed_from_fragment_cache': True,
                'pause_resume': True, 'deselect_reselect': True,
                'dynamic_selection_hashes_match': True, 'unselected_paths_absent': True,
                'skipped_sentinel_preserved': existing,
                'fragment_files': len(list((root / 'leecher/session/parts-v1').glob('*.parts')))}
    finally:
        for engine in reversed(engines):
            engine.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('binary', type=Path)
    parser.add_argument('evidence', type=Path)
    args = parser.parse_args()
    binary = args.binary.resolve(strict=True)
    args.evidence.mkdir(parents=True, exist_ok=True)
    proof = {'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
             'network': 'sandbox-exec: loopback only', 'cases': [], 'passed': False}
    try:
        with tempfile.TemporaryDirectory(prefix='hop-engine-e2e-', dir='/private/tmp') as temporary:
            for label, existing, aligned in [('shared-absent', False, False),
                                             ('shared-existing', True, False),
                                             ('aligned-absent', False, True)]:
                root = Path(temporary) / label
                logs = args.evidence / label
                root.mkdir()
                logs.mkdir(exist_ok=True)
                proof['cases'].append(run_case(binary, root, logs, existing, aligned))
                print(label + ': PASS', flush=True)
        proof['passed'] = True
        proof['temporary_data_removed'] = True
    finally:
        (args.evidence / 'proof.json').write_text(json.dumps(proof, indent=2) + '\n')


if __name__ == '__main__':
    main()

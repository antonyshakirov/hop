#!/usr/bin/env python3
"""Run one Hop build at a time across checkouts and isolated HOME directories."""
import fcntl
import os
import signal
import stat
import subprocess
import sys
import time


LOCK_PATH = '/private/tmp/hop-build-budget-{}.lock'.format(os.getuid())


def limited_arguments(argv):
    if os.path.basename(argv[0]) != 'swift' or len(argv) < 2 or argv[1] not in ('build', 'test'):
        return argv
    result = argv[:2]
    index = 2
    while index < len(argv):
        arg = argv[index]
        if arg in ('--jobs', '-j'):
            if index + 1 == len(argv) or not argv[index + 1].isdigit():
                raise ValueError('Expected a job count')
            index += 2
        elif arg.startswith('--jobs=') or (arg.startswith('-j') and arg[2:].isdigit()):
            index += 1
        else:
            result.append(arg)
            index += 1
    return result + ['--jobs', '2']


def stop_group(pid, sig):
    try:
        os.killpg(pid, sig)
    except ProcessLookupError:
        pass


def main(argv):
    if not argv:
        raise SystemExit('Usage: build-budget.py command [arguments ...]')
    child = None
    cancelled = 0
    deadline = None

    def cancel(sig, _frame):
        nonlocal cancelled, deadline
        cancelled = sig
        if child is None:
            raise SystemExit(128 + sig)
        stop_group(child.pid, sig)
        deadline = time.monotonic() + 1

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, cancel)
    fd = os.open(LOCK_PATH, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        metadata = os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid() or metadata.st_mode & 0o077 or metadata.st_nlink != 1:
            raise RuntimeError('Unsafe Hop build lock')
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print('Another Hop build is running; waiting for the shared build budget.', file=sys.stderr, flush=True)
            fcntl.flock(fd, fcntl.LOCK_EX)
        # Leave interactive applications ahead of background verification work.
        os.nice(5)
        signals = {signal.SIGTERM, signal.SIGINT, signal.SIGHUP}
        previous = signal.pthread_sigmask(signal.SIG_BLOCK, signals)
        try:
            child = subprocess.Popen(limited_arguments(argv), start_new_session=True,
                                     env={**os.environ, 'HOP_BUILD_BUDGET_OWNER': str(os.getpid())},
                                     preexec_fn=lambda: signal.pthread_sigmask(signal.SIG_SETMASK, previous))
        finally:
            signal.pthread_sigmask(signal.SIG_SETMASK, previous)
        while True:
            try:
                code = child.wait(timeout=0.1)
                break
            except subprocess.TimeoutExpired:
                if deadline is not None and time.monotonic() >= deadline:
                    stop_group(child.pid, signal.SIGKILL)
        return 128 + cancelled if cancelled else (128 - code if code < 0 else code)
    finally:
        if child is not None:
            # Failed compilers can leave extractor workers behind. They must not
            # continue consuming CPU after the next build acquires the lock.
            stop_group(child.pid, signal.SIGKILL)
            child.wait()
        os.close(fd)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

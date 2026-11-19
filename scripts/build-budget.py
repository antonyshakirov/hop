#!/usr/bin/env python3
"""Run one Hop build at a time across checkouts and isolated HOME directories."""
from contextlib import nullcontext
import ctypes
import errno
import fcntl
import os
import signal
import stat
import subprocess
import sys
import tempfile
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
    except PermissionError:
        # XNU returns EPERM for zombie-only groups as well as real denials.
        # Keep the leader unreaped while checking its kernel-backed membership.
        if not exited_without_reaping(pid):
            raise
        members = subprocess.run(['/bin/ps', '-A', '-o', 'pgid=,stat='],
                                 capture_output=True, text=True, timeout=2)
        rows = [line.split() for line in members.stdout.splitlines()]
        if members.returncode != 0 or members.stderr.strip() or any(len(row) != 2 or not row[0].isdigit() for row in rows):
            raise
        states = [row[1] for row in rows if row[0] == str(pid)]
        if not states or any(not state.startswith('Z') for state in states):
            raise



def exited_without_reaping(pid):
    # Keep the group leader waitable until cleanup: its PID must not be reused.
    options = os.WEXITED | os.WNOWAIT | os.WNOHANG
    if hasattr(os, 'waitid'):
        return os.waitid(os.P_PID, pid, options) is not None
    # Darwin exposes waitid in libc but Apple's Python 3.9 omits os.waitid.
    # siginfo_t starts with si_signo; this aligned buffer exceeds its SDK size.
    info = (ctypes.c_longlong * 32)()
    waitid = ctypes.CDLL(None, use_errno=True).waitid
    waitid.argtypes = [ctypes.c_int, ctypes.c_uint, ctypes.c_void_p, ctypes.c_int]
    waitid.restype = ctypes.c_int
    if waitid(os.P_PID, pid, ctypes.byref(info), options) != 0:
        error = ctypes.get_errno()
        if error == errno.EINTR:
            return False
        raise OSError(error, os.strerror(error))
    return ctypes.cast(info, ctypes.POINTER(ctypes.c_int))[0] != 0


def main(argv):
    if not argv:
        raise SystemExit('Usage: build-budget.py command [arguments ...]')
    signal.signal(signal.SIGCHLD, signal.SIG_DFL)
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
            groups = os.environ.get('HOP_BUILD_GROUP_DIRECTORY')
            # An empty receipt means launch was interrupted before the group was known.
            receipt = tempfile.NamedTemporaryFile(mode='w', dir=groups, prefix='group-', delete=False) if groups else nullcontext()
            with receipt as record:
                child = subprocess.Popen(limited_arguments(argv), start_new_session=True, pass_fds=(fd,),
                                         env={**os.environ, 'HOP_BUILD_BUDGET_OWNER': str(os.getpid())},
                                         preexec_fn=lambda: signal.pthread_sigmask(signal.SIG_SETMASK, previous))
                if record:
                    print(child.pid, file=record, flush=True)
        finally:
            signal.pthread_sigmask(signal.SIG_SETMASK, previous)
        while not exited_without_reaping(child.pid):
            if deadline is not None and time.monotonic() >= deadline:
                stop_group(child.pid, signal.SIGKILL)
            time.sleep(0.1)
    except OSError as error:
        if error.errno == errno.ECHILD:
            child = None  # Ownership was lost; never signal a potentially reused group.
        raise
    finally:
        # Failed compilers can leave extractor workers behind. They must not
        # continue consuming CPU after the next build acquires the lock.
        # Signal before reaping; block cancellation across that identity change.
        previous = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM, signal.SIGINT, signal.SIGHUP})
        try:
            if child is not None:
                try:
                    stop_group(child.pid, signal.SIGKILL)
                except BaseException:
                    if exited_without_reaping(child.pid):
                        child.wait()
                        child = None
                    raise
                code = child.wait()
                child = None
        finally:
            os.close(fd)
            signal.pthread_sigmask(signal.SIG_SETMASK, previous)
    return 128 + cancelled if cancelled else (128 - code if code < 0 else code)



if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

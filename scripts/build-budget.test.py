"""Exercise the build queue with real processes, without compiling Hop."""
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest


SCRIPT = Path(__file__).with_name('build-budget.py')


class BuildBudgetTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='hop-budget-test-', dir='/private/tmp')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.lock = self.root / 'build.lock'
        self.children = []
        self.addCleanup(self.stop_children)

    def stop_children(self):
        for child in self.children:
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()

    def launch(self, code, script=SCRIPT, default_lock=False, command=None):
        # Only tests substitute the lock path; the shipped CLI has one per-user lock.
        bootstrap = ('import importlib.util,sys;'
                     's=importlib.util.spec_from_file_location("budget",sys.argv[1]);'
                     'm=importlib.util.module_from_spec(s);s.loader.exec_module(m);'
                     'm.LOCK_PATH=sys.argv[2];sys.exit(m.main(sys.argv[3:]))')
        home = self.root / ('home-' + str(len(self.children)))
        home.mkdir()
        actual = command or [sys.executable, '-c', code]
        argv = ([sys.executable, '-B', str(script), *actual] if default_lock else
                [sys.executable, '-B', '-c', bootstrap, str(script), str(self.lock), *actual])
        child = subprocess.Popen(argv,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                 env={**os.environ, 'HOME': str(home), 'TMPDIR': str(home)})
        self.children.append(child)
        self.addCleanup(child.stdout.close)
        self.addCleanup(child.stderr.close)
        return child

    def wait_file(self, path, timeout=5):
        deadline = None if timeout is None else time.monotonic() + timeout
        while not path.exists() and (deadline is None or time.monotonic() < deadline):
            for child in self.children:
                self.assertIsNone(child.poll(), 'build launcher exited before becoming ready')
            time.sleep(0.02)
        self.assertTrue(path.exists(), str(path))

    def test_copies_with_different_homes_serialize(self):
        first = self.root / 'first'
        release = self.root / 'release'
        second = self.root / 'second'
        copy = self.root / 'copy.py'
        copy.write_bytes(SCRIPT.read_bytes())
        a = self.launch(f'from pathlib import Path;import time;Path({str(first)!r}).touch();'
                        f'\nwhile not Path({str(release)!r}).exists():time.sleep(.02)', default_lock=True)
        # The check runner owns the queue timeout. An existing real build may
        # legitimately hold the default lock much longer than a fixture takes.
        self.wait_file(first, timeout=None)
        b = self.launch(f'from pathlib import Path;Path({str(second)!r}).touch()', copy, default_lock=True)
        time.sleep(0.2)
        self.assertFalse(second.exists(), 'a second checkout started before the first finished')
        release.touch()
        self.assertEqual(a.wait(timeout=5), 0)
        self.assertEqual(b.wait(), 0)
        self.assertTrue(second.exists())

    def test_failure_releases_queue_and_preserves_exit_code(self):
        self.assertEqual(self.launch('raise SystemExit(7)').wait(timeout=5), 7)
        self.assertEqual(self.launch('pass').wait(timeout=5), 0)

    def test_cancel_stops_descendants_and_releases_queue(self):
        pidfile = self.root / 'pid'
        code = ('import subprocess,sys,time;from pathlib import Path;'
                'p=subprocess.Popen([sys.executable,"-c","import time;time.sleep(60)"]);'
                f'Path({str(pidfile)!r}).write_text(str(p.pid));time.sleep(60)')
        a = self.launch(code)
        self.wait_file(pidfile)
        descendant = int(pidfile.read_text())
        a.terminate()
        self.assertEqual(a.wait(timeout=5), 128 + signal.SIGTERM)
        for _ in range(100):
            result = subprocess.run(['ps', '-p', str(descendant), '-o', 'stat='],
                                    capture_output=True, text=True)
            if not result.stdout.strip() or result.stdout.strip().startswith('Z'):
                break
            time.sleep(0.02)
        else:
            self.fail('compiler descendant survived cancellation')
        self.assertEqual(self.launch('pass').wait(timeout=5), 0)

    def test_successful_parent_cannot_leave_an_extractor_running(self):
        pidfile = self.root / 'orphan'
        code = ('import subprocess,sys;from pathlib import Path;'
                'p=subprocess.Popen([sys.executable,"-c","import time;time.sleep(60)"]);'
                f'Path({str(pidfile)!r}).write_text(str(p.pid))')
        a = self.launch(code)
        self.assertEqual(a.wait(timeout=5), 0)
        descendant = int(pidfile.read_text())
        for _ in range(100):
            state = subprocess.run(['ps', '-p', str(descendant), '-o', 'stat='], capture_output=True, text=True).stdout.strip()
            if not state or state.startswith('Z'):
                break
            time.sleep(0.02)
        else:
            self.fail('extractor survived successful parent exit')

    def test_group_signals_precede_reaping_the_leader(self):
        script = self.root / 'instrumented.py'
        original = SCRIPT.read_text()
        injected = ("\n_real_wait = subprocess.Popen.wait\n_reaped = False\n"
                    "def checked_wait(self, *args, **kwargs):\n"
                    "    global _reaped\n    result = _real_wait(self, *args, **kwargs)\n    _reaped = True\n    return result\n"
                    "_real_stop = stop_group\n"
                    "def checked_stop(pid, sig):\n    assert not _reaped, 'signal after reap'\n    _real_stop(pid, sig)\n"
                    "subprocess.Popen.wait = checked_wait\nstop_group = checked_stop\n")
        script.write_text(original.replace("if __name__ == '__main__':", injected + "\nif __name__ == '__main__':"))
        self.assertEqual(self.launch('pass', script=script).wait(timeout=5), 0)

    def test_killed_wrapper_keeps_queue_locked_until_child_finishes(self):
        ready, release, second = [self.root / name for name in ['ready', 'release', 'second']]
        self.addCleanup(release.touch)
        a = self.launch(f'from pathlib import Path;import time;Path({str(ready)!r}).touch();'
                        f'\nwhile not Path({str(release)!r}).exists():time.sleep(.02)')
        self.wait_file(ready)
        a.kill(); a.wait(timeout=5)
        b = self.launch(f'from pathlib import Path;Path({str(second)!r}).touch()')
        time.sleep(0.2)
        self.assertFalse(second.exists(), 'child lost its inherited build lock')
        release.touch()
        self.assertEqual(b.wait(timeout=5), 0)

    def test_node_command_inherits_lock_after_wrapper_kill(self):
        import json
        ready, release, second = [self.root / name for name in ['node-ready', 'node-release', 'second']]
        self.addCleanup(release.touch)
        code = ("const fs=require('fs');fs.writeFileSync(" + json.dumps(str(ready)) + ", 'ready');"
                "const t=setInterval(()=>{if(fs.existsSync(" + json.dumps(str(release)) + "))clearInterval(t)},20)")
        a = self.launch('', command=['node', '-e', code])
        self.wait_file(ready); a.kill(); a.wait(timeout=5)
        b = self.launch(f'from pathlib import Path;Path({str(second)!r}).touch()')
        time.sleep(0.2); self.assertFalse(second.exists())
        release.touch(); self.assertEqual(b.wait(timeout=5), 0)

    def test_ignored_term_is_escalated_before_outer_gate_kill(self):
        ready = self.root / 'ignoring-term'
        a = self.launch('import signal,time;from pathlib import Path;'
                        'signal.signal(signal.SIGTERM,signal.SIG_IGN);'
                        f'Path({str(ready)!r}).touch();time.sleep(60)')
        self.wait_file(ready)
        started = time.monotonic(); a.terminate()
        self.assertEqual(a.wait(timeout=3), 128 + signal.SIGTERM)
        self.assertLess(time.monotonic() - started, 3)

    def test_permission_denial_with_live_members_is_not_hidden(self):
        import importlib.util
        from unittest.mock import patch
        from types import SimpleNamespace
        spec = importlib.util.spec_from_file_location('budget', SCRIPT)
        budget = importlib.util.module_from_spec(spec); spec.loader.exec_module(budget)
        with patch.object(budget.os, 'killpg', side_effect=PermissionError()), \
             patch.object(budget, 'exited_without_reaping', return_value=True), \
             patch.object(budget.subprocess, 'run', return_value=SimpleNamespace(returncode=0, stdout='123 S\n', stderr='')):
            with self.assertRaises(PermissionError):
                budget.stop_group(123, signal.SIGKILL)

    def test_linked_lock_is_rejected(self):
        target = self.root / 'unrelated'
        target.write_text('keep')
        self.lock.symlink_to(target)
        self.assertNotEqual(self.launch('pass').wait(timeout=5), 0)
        self.assertEqual(target.read_text(), 'keep')

    def test_swift_jobs_are_capped_even_when_caller_requests_more(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('budget', SCRIPT)
        budget = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(budget)
        for options in ([], ['-j10'], ['-j', '10'], ['--jobs=10'], ['--jobs', '10']):
            command = budget.limited_arguments(['/toolchain/swift', 'test', *options, '--filter', 'HopCoreTests'])
            self.assertEqual(command, ['/toolchain/swift', 'test', '--filter', 'HopCoreTests', '--jobs', '2'])

    def test_cancel_waiting_build_does_not_start_it_or_interrupt_owner(self):
        ready = self.root / 'ready'
        forbidden = self.root / 'forbidden'
        a = self.launch(f'from pathlib import Path;import time;Path({str(ready)!r}).touch();time.sleep(60)')
        self.wait_file(ready)
        b = self.launch(f'from pathlib import Path;Path({str(forbidden)!r}).touch()')
        time.sleep(0.2)
        b.terminate()
        self.assertEqual(b.wait(timeout=5), 128 + signal.SIGTERM)
        self.assertIsNone(a.poll())
        self.assertFalse(forbidden.exists())


if __name__ == '__main__':
    unittest.main()

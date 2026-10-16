import { createHash, randomBytes } from 'node:crypto';
import { createConnection, createServer } from 'node:net';
import { execFileSync, spawn } from 'node:child_process';
import { createWriteStream } from 'node:fs';
import { access, lstat, mkdir, mkdtemp, open, readFile, readlink, realpath, rename, rm, writeFile } from 'node:fs/promises';
import { dirname, isAbsolute, join, relative, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { finished } from 'node:stream/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';

const hash = value => createHash('sha256').update(value).digest('hex');
const json = value => JSON.stringify(value);
const age = 6 * 60 * 60 * 1000;
const gitEnv = { PATH: process.env.PATH, LANG: 'C', TZ: 'UTC', GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_COUNT: '0', GIT_TERMINAL_PROMPT: '0' };
const git = (root, args) => execFileSync('git', ['-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false', ...args], { cwd: root, env: gitEnv, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }).trim();
const safeRelative = value => typeof value === 'string' && !isAbsolute(value) && !value.split(/[\\/]/).includes('..') && !value.includes('\0');
const same = (a, b) => json(a) === json(b);
const readJson = async file => JSON.parse(await readFile(file, 'utf8'));
async function atomic(file, value) { const tmp = file + '.' + randomBytes(8).toString('hex'); await writeFile(tmp, json(value) + '\n', { mode: 0o600, flag: 'wx' }); await rename(tmp, file); }
async function secureDirectory(directory) {
  await mkdir(directory, { recursive: true, mode: 0o700 });
  const stat = await lstat(directory);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || (stat.mode & 0o077) || await realpath(directory) !== resolve(directory)) throw new Error('Unsafe proof directory');
}
async function regular(file) { const s = await lstat(file); if (!s.isFile() || s.isSymbolicLink() || await realpath(file) !== resolve(file)) throw new Error('Unsafe proof file'); return readFile(file); }

export function validatePlan(plan) {
  if (plan.schema !== 1 || !/^[a-z0-9][a-z0-9-]*$/.test(plan.project) || !Array.isArray(plan.steps) || !plan.steps.length) throw new Error('Invalid or empty check plan');
  const ids = new Set();
  for (const step of [...plan.steps, ...(plan.cleanup ?? [])]) {
    if (!/^[a-z0-9-]+$/.test(step.id) || ids.has(step.id) || !safeRelative(step.cwd) || !step.command || !Array.isArray(step.args) || step.args.some(a => typeof a !== 'string') || step.network !== undefined && typeof step.network !== 'boolean' || !Number.isInteger(step.timeoutMs) || step.timeoutMs < 1 || step.timeoutMs > 3600000) throw new Error('Invalid check step');
    if (step.tapMinimum !== undefined && (!Number.isInteger(step.tapMinimum) || step.tapMinimum < 1)) throw new Error('Invalid TAP minimum');
    ids.add(step.id);
  }
  for (const item of plan.artifacts ?? []) {
    if (!safeRelative(item.path) || !item.path || !['vitest', 'playwright', 'playwright-discovery', 'json', 'file'].includes(item.type)) throw new Error('Invalid artifact path or type');
    if (item.minimumPassed !== undefined && (!Number.isInteger(item.minimumPassed) || item.minimumPassed < 1)) throw new Error('Invalid artifact case minimum');
    if (item.allowedSkipped !== undefined && (!Number.isInteger(item.allowedSkipped) || item.allowedSkipped < 0)) throw new Error('Invalid allowed skip count');
  }
  for (const file of plan.generatedPaths ?? []) if (!safeRelative(file) || !file || file === '.') throw new Error('Invalid generated file contract');
  for (const port of plan.ports ?? []) if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid fixture port');
  for (const value of Object.values(plan.env ?? {})) if (typeof value !== 'string') throw new Error('Environment values must be literal strings');
  return plan;
}

export async function captureSource(root, generatedPaths = [], allowedUntracked = []) {
  const changes = git(root, ['status', '--porcelain', '-z', '--untracked-files=all']).split('\0').filter(Boolean);
  if (changes.some(row => !generatedPaths.includes(row.slice(3)) && !(row.startsWith('?? ') && allowedUntracked.includes(row.slice(3))))) throw new Error('Refusing dirty tracked or untracked source');
  const paths = execFileSync('git', ['-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false', 'ls-files', '-z'], { cwd: root, env: gitEnv, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }).split('\0').filter(Boolean).sort();
  const digest = createHash('sha256');
  for (const file of paths) {
    if (generatedPaths.includes(file)) continue;
    const absolute = join(root, file), s = await lstat(absolute);
    if (s.isSymbolicLink()) {
      const target = resolve(dirname(absolute), await readlink(absolute));
      if (!target.startsWith(resolve(root) + '/') || !(await realpath(absolute)).startsWith(resolve(root) + '/')) throw new Error('Tracked symlink escapes source workspace');
    }
    const value = s.isSymbolicLink() ? 'link:' + await readlink(absolute) : s.isFile() ? hash(await readFile(absolute)) : 'gitlink:' + git(root, ['ls-files', '-s', '--', file]);
    digest.update(file + '\0' + (s.mode & 0o777) + '\0' + value + '\0');
  }
  return { head: git(root, ['rev-parse', 'HEAD']), tree: git(root, ['rev-parse', 'HEAD^{tree}']), sourceHash: digest.digest('hex') };
}

export async function assertPortFree(port) {
  for (const host of ['127.0.0.1', '::1']) {
    await new Promise((done, reject) => {
      const socket = createConnection({ host, port });
      let completed = false;
      const stop = error => { if (completed) return; completed = true; socket.destroy(); error ? reject(error) : done(); };
      socket.setTimeout(1000, () => stop(new Error('Fixture port connection timed out: ' + port)));
      socket.once('connect', () => stop(new Error('Fixture port is occupied: ' + port)));
      socket.once('error', e => stop(e.code === 'ECONNREFUSED' ? undefined : e));
    });
    await new Promise((done, reject) => { const server = createServer(); server.once('error', reject); server.listen({ host, port, exclusive: true }, () => server.close(e => e ? reject(e) : done())); });
  }
}

export function processGroupHasNoLiveMembers(output, pgid) {
  if (!Number.isSafeInteger(pgid) || pgid < 1) throw new Error('Invalid owned process group');
  let live = false;
  for (const line of output.split('\n').filter(line => line.trim())) {
    const row = /^\s*\d+\s+(\d+)\s+\d+\s+(\S+)\s*$/.exec(line);
    if (!row) throw new Error('Cannot verify process group state');
    if (Number(row[1]) === pgid && !row[2].startsWith('Z')) live = true;
  }
  return !live;
}
export function confirmGroupExit(pgid, {
  snapshot = () => execFileSync('/bin/ps', ['-axo', 'pid=,pgid=,uid=,stat='], { encoding: 'utf8', env: gitEnv }),
  pause = () => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 50),
} = {}) {
  for (let attempt = 0; attempt < 20; attempt++) {
    if (processGroupHasNoLiveMembers(snapshot(), pgid)) return true;
    pause();
  }
  return false;
}
function stopGroup(pid, signal) {
  try { process.kill(-pid, signal); }
  catch (error) {
    if (error.code === 'ESRCH') return;
    if (error.code === 'EPERM') {
      if (confirmGroupExit(pid)) return;
    }
    throw error;
  }
}
export async function execute(step, { cwd, env, logFile, signal }) {
  const output = createWriteStream(logFile, { flags: 'wx', mode: 0o600 });
  let timedOut = false, error, child;
  const result = await new Promise(done => {
    child = spawn(step.command, step.args, { cwd, env, detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
    child.stdout.pipe(output, { end: false }); child.stderr.pipe(output, { end: false });
    let killer;
    const terminate = () => { if (child.pid) { stopGroup(child.pid, 'SIGTERM'); killer ??= setTimeout(() => stopGroup(child.pid, 'SIGKILL'), 3000); } };
    const timer = setTimeout(() => { timedOut = true; terminate(); }, step.timeoutMs);
    output.on('error', e => { error = e.message; terminate(); });
    child.on('error', e => { error = e.message; });
    signal?.addEventListener('abort', terminate, { once: true });
    if (signal?.aborted) terminate();
    child.once('close', (exitCode, exitSignal) => { clearTimeout(timer); clearTimeout(killer); signal?.removeEventListener('abort', terminate); done({ exitCode, signal: exitSignal, timedOut, aborted: Boolean(signal?.aborted), ...(error ? { error } : {}) }); });
  });
  if (child.pid) stopGroup(child.pid, 'SIGTERM');
  output.end(); await finished(output);
  return { ...result, logHash: hash(await readFile(logFile)) };
}

function validateOutput(step, bytes) {
  if (step.tapMinimum !== undefined) {
    const text = bytes.toString();
    const count = [...text.matchAll(/^# tests (\d+)$/gm)].at(-1);
    const failures = [...text.matchAll(/^# fail (\d+)$/gm)].at(-1);
    const skips = [...text.matchAll(/^# skipped (\d+)$/gm)].at(-1);
    if (!count || !failures || Number(count[1]) < step.tapMinimum || Number(failures[1]) !== 0 || !skips || Number(skips[1]) !== 0) throw new Error('TAP coverage is incomplete or skipped');
  }
}
function expand(value, variables) {
  return value.replace(/\{\{([a-z]+)\}\}/g, (_, key) => { if (!(key in variables)) throw new Error('Unknown plan variable: ' + key); return variables[key]; });
}
function commands(plan, variables) {
  const expandStep = step => ({ ...step, command: expand(step.command, variables), args: step.args.map(x => expand(x, variables)), cwd: step.cwd });
  return { steps: plan.steps.map(expandStep), cleanup: (plan.cleanup ?? []).map(expandStep) };
}
function environment(plan, variables, state) {
  const env = { PATH: process.env.PATH, HOME: join(variables.run, 'home'), TMPDIR: join(variables.run, 'tmp'), LANG: 'en_US.UTF-8', TZ: 'UTC', CI: '1', NEXT_TELEMETRY_DISABLED: '1', DO_NOT_TRACK: '1', GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1', npm_config_userconfig: join(variables.run, 'npmrc'), npm_config_globalconfig: '/dev/null', npm_config_cache: join(state, 'npm-cache'), npm_config_registry: 'https://registry.npmjs.org/', XDG_CACHE_HOME: join(state, 'cache'), XDG_CONFIG_HOME: join(variables.run, 'config') };
  for (const [key, value] of Object.entries(plan.env ?? {})) {
    if (['PATH', 'HOME', 'TMPDIR', 'NODE_OPTIONS', 'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM', 'npm_config_userconfig', 'npm_config_registry'].includes(key)) throw new Error('Protected environment override: ' + key);
    env[key] = expand(value, variables);
  }
  return env;
}
function browserCases(report) { const results = []; const walk = suites => { for (const suite of suites ?? []) { for (const spec of suite.specs ?? []) for (const t of spec.tests ?? []) results.push({ id: t.projectName + ':' + spec.id, file: spec.file, title: spec.title, ...t }); walk(suite.suites); } }; walk(report.suites); return results; }
function assertKnownSkips(spec, actual) {
  const expected = spec.allowedSkips ?? [];
  if (actual.length !== expected.length || actual.some(item => !expected.some(e => (item.file === e.file || item.file.endsWith('/' + e.file)) && item.title === e.title && item.project === e.project))) throw new Error('Unexpected skip identity');
}
function validateArtifact(spec, bytes) {
  if (spec.type === 'file') { if (!bytes.length) throw new Error('Empty artifact'); return { bytes: bytes.length }; }
  const result = JSON.parse(bytes);
  if (spec.type === 'vitest') {
    if (result.success !== true || !Number.isInteger(result.numPassedTests) || result.numFailedTests !== 0 || result.numPassedTests < (spec.minimumPassed ?? 1) || result.numPendingTests !== (spec.allowedSkipped ?? 0)) throw new Error('Unit coverage is incomplete or has unexpected skips');
    const assertions = (result.testResults ?? []).flatMap(file => file.assertionResults ?? []);
    if (assertions.filter(t => t.status === 'passed').length !== result.numPassedTests || assertions.filter(t => t.status === 'failed').length !== result.numFailedTests || assertions.some(t => !['passed', 'failed', 'pending', 'skipped'].includes(t.status))) throw new Error('Unit assertion metadata inconsistent');
    const skipped = (result.testResults ?? []).flatMap(file => (file.assertionResults ?? []).filter(t => ['pending', 'skipped'].includes(t.status)).map(t => ({ file: file.name, title: t.fullName })));
    if (skipped.length !== result.numPendingTests) throw new Error('Unit skip metadata incomplete');
    assertKnownSkips(spec, skipped);
    return { passed: result.numPassedTests, skipped: result.numPendingTests, skippedCases: skipped };
  }
  if (spec.type === 'playwright' || spec.type === 'playwright-discovery') {
    const cases = browserCases(result);
    if (!cases.length || new Set(cases.map(t => t.id)).size !== cases.length || !same(result.config.projects.map(p => p.name), spec.projects)) throw new Error('Browser projects are incomplete');
    if (spec.type === 'playwright-discovery') return { cases: cases.length, caseIds: cases.map(t => t.id).sort() };
    const failed = cases.filter(t => t.status !== 'expected' && t.status !== 'skipped');
    const skipped = cases.filter(t => t.status === 'skipped');
    if (failed.length || skipped.length !== (spec.allowedSkipped ?? 0) || result.errors?.length || cases.some(t => !Array.isArray(t.results) || t.results.length !== 1 || t.results.some(r => r.retry !== 0 || r.status !== (t.status === 'expected' ? 'passed' : 'skipped')))) throw new Error('Browser failures, retries or unexpected skips');
    assertKnownSkips(spec, skipped.map(t => ({ file: t.file, title: t.title, project: t.projectName })));
    const passed = cases.length - skipped.length;
    if (passed < (spec.minimumPassed ?? 1)) throw new Error('Browser coverage is incomplete');
    return { passed, skipped: skipped.length, caseIds: cases.map(t => t.id).sort() };
  }
  return { parsed: true };
}
async function artifactResults(plan, workspace, directory) {
  const result = [];
  await mkdir(join(directory, 'artifacts'), { mode: 0o700 });
  for (const [i, item] of (plan.artifacts ?? []).entries()) {
    const file = join(workspace, item.path);
    if (!resolve(await realpath(file)).startsWith(resolve(workspace) + '/')) throw new Error('Artifact escaped workspace');
    const bytes = await regular(file), coverage = validateArtifact(item, bytes), stored = 'artifacts/' + i + '.dat';
    await writeFile(join(directory, stored), bytes, { mode: 0o600, flag: 'wx' });
    result.push({ path: item.path, stored, hash: hash(bytes), coverage });
  }
  const discovery = result.find((_, i) => plan.artifacts[i].type === 'playwright-discovery');
  const browser = result.find((_, i) => plan.artifacts[i].type === 'playwright');
  if (discovery && browser && !same(discovery.coverage.caseIds, browser.coverage.caseIds)) throw new Error('Browser execution differs from discovered cases');
  return result;
}

export async function runGate({ root, state, plan }) {
  validatePlan(plan); root = await realpath(root); await secureDirectory(state);
  const lockPath = join(state, 'running.json');
  try { const lock = JSON.parse(await regular(lockPath)); if (!Number.isInteger(lock.pid) || lock.pid < 1) throw new Error('Invalid check lock'); try { process.kill(lock.pid, 0); throw new Error('Another check is running'); } catch (e) { if (e.code !== 'ESRCH') throw e; throw new Error('Stale interrupted-run lock; inspect ownership before clearing'); } } catch (e) { if (e.code !== 'ENOENT') throw e; }
  const lock = await open(lockPath, 'wx', 0o600); await lock.writeFile(json({ pid: process.pid })); await lock.close();
  const directory = await mkdtemp(join(state, 'run-'));
  await atomic(join(state, 'latest.json'), { run: directory.split('/').at(-1) });
  const proof = { schema: 1, project: plan.project, repository: root, status: 'running', planHash: hash(json(plan)), startedAt: new Date().toISOString(), steps: [], cleanupSteps: [], errors: [] };
  const workspace = join(directory, 'workspace');
  const variables = { run: directory, workspace, node: process.execPath, npm: await realpath(join(dirname(process.execPath), 'npm')) };
  const configured = commands(plan, variables), env = environment(plan, variables, state);
  const controller = new AbortController(), interrupt = () => controller.abort();
  process.once('SIGINT', interrupt); process.once('SIGTERM', interrupt);
  async function perform(step, index, cleanup = false) {
    const cwd = await realpath(join(workspace, step.cwd));
    if (cwd !== workspace && !cwd.startsWith(workspace + '/')) throw new Error('Command escaped isolated workspace');
    const log = `logs/${cleanup ? 'cleanup-' : ''}${index}-${step.id}.log`;
    const childEnv = { ...env };
    const networkFile = join(workspace, 'scripts/own-ci/network.mjs');
    if (!step.network) { await access(networkFile); childEnv.NODE_OPTIONS = '--import ' + pathToFileURL(networkFile).href; }
    const startedAt = new Date().toISOString();
    const result = await execute(step, { cwd, env: childEnv, logFile: join(directory, log), signal: cleanup ? undefined : controller.signal });
    const item = { id: step.id, command: step.command, args: step.args, cwd: step.cwd, log, startedAt, finishedAt: new Date().toISOString(), ...result };
    (cleanup ? proof.cleanupSteps : proof.steps).push(item); await atomic(join(directory, 'proof.json'), proof);
    if (item.exitCode !== 0 || item.signal || item.timedOut || item.aborted || item.error) throw new Error('Required step failed: ' + step.id);
    validateOutput(step, await readFile(join(directory, log)));
  }
  try {
    proof.source = await captureSource(root);
    for (const port of plan.ports ?? []) await assertPortFree(port);
    await mkdir(join(directory, 'logs'), { mode: 0o700 });
    await mkdir(env.HOME, { mode: 0o700 }); await mkdir(env.TMPDIR, { mode: 0o700 }); await writeFile(env.npm_config_userconfig, '', { mode: 0o600 });
    execFileSync('git', ['-c', 'core.hooksPath=/dev/null', 'clone', '--template=', '--quiet', '--shared', '--no-checkout', root, workspace], { env: gitEnv, stdio: 'pipe' });
    git(workspace, ['config', 'core.hooksPath', '/dev/null']); git(workspace, ['remote', 'remove', 'origin']); git(workspace, ['checkout', '--quiet', '--detach', proof.source.head]);
    const generated = plan.generatedPaths ?? [];
    const untracked = (plan.artifacts ?? []).map(item => item.path);
    for (const item of plan.artifacts ?? []) {
      if (['vitest', 'playwright', 'playwright-discovery'].includes(item.type)) {
        try { await lstat(join(workspace, item.path)); throw new Error('Preexisting test report cannot prove fresh execution'); } catch (e) { if (e.code !== 'ENOENT') throw e; }
      }
    }
    const baseline = await captureSource(workspace, generated, untracked);
    const originalBaseline = await captureSource(root, generated);
    if (!same(baseline, originalBaseline)) throw new Error('Cloned workspace differs from original source');
    for (const file of git(workspace, ['ls-files']).split('\n')) if (/(^|\/)\.env($|\.)/.test(file) && !/(\.example|\.sample|\.template)$/.test(file) && !(plan.safeEnvFiles ?? []).includes(file)) throw new Error('Unapproved tracked environment file: ' + file);
    for (const [i, step] of configured.steps.entries()) {
      if (!same(proof.source, await captureSource(root))) throw new Error('Source changed during checks');
      if (controller.signal.aborted) throw new Error('Checks interrupted');
      if (!same(baseline, await captureSource(workspace, generated, untracked))) throw new Error('Workspace source changed during checks');
      console.log('[own-checks] ' + step.id); await perform(step, i);
      if (!same(baseline, await captureSource(workspace, generated, untracked))) throw new Error('Workspace source changed during checks');
    }
    proof.artifacts = await artifactResults(plan, workspace, directory);
  } catch (e) { proof.errors.push(e.message); }
  finally {
    for (const [i, step] of configured.cleanup.entries()) try { await perform(step, i, true); } catch (e) { proof.errors.push('Cleanup: ' + e.message); }
    try { for (const port of plan.ports ?? []) await assertPortFree(port); proof.cleanup = { passed: true, portsFree: plan.ports ?? [] }; } catch (e) { proof.cleanup = { passed: false }; proof.errors.push(e.message); }
    try { proof.sourceAfter = await captureSource(root); if (!same(proof.source, proof.sourceAfter)) proof.errors.push('Source changed during checks'); } catch (e) { proof.errors.push(e.message); }
    proof.status = proof.errors.length || proof.steps.length !== plan.steps.length ? 'failed' : 'passed'; proof.finishedAt = new Date().toISOString();
    await atomic(join(directory, 'proof.json'), proof); await rm(lockPath); process.removeListener('SIGINT', interrupt); process.removeListener('SIGTERM', interrupt);
  }
  return proof;
}

export async function verifyGate({ root, state, plan, now = Date.now() }) {
  validatePlan(plan); root = await realpath(root); await secureDirectory(state);
  try { await lstat(join(state, 'running.json')); throw new Error('Checks running or interrupted'); } catch (e) { if (e.code !== 'ENOENT') throw e; }
  const pointer = JSON.parse(await regular(join(state, 'latest.json')));
  if (!/^run-[a-zA-Z0-9]+$/.test(pointer.run)) throw new Error('Invalid latest pointer');
  const directory = join(state, pointer.run); await secureDirectory(directory);
  const proof = JSON.parse(await regular(join(directory, 'proof.json'))), current = await captureSource(root);
  if (proof.schema !== 1 || proof.project !== plan.project || proof.repository !== root || proof.status !== 'passed' || !Array.isArray(proof.errors) || proof.errors.length || !proof.cleanup?.passed || !same(proof.source, current) || !same(proof.sourceAfter, current) || proof.planHash !== hash(json(plan))) throw new Error('Proof failed or source/plan changed');
  const start = Date.parse(proof.startedAt), end = Date.parse(proof.finishedAt);
  if (!Number.isFinite(start) || !Number.isFinite(end) || start > end || now - end > age) throw new Error('Proof expired or invalid timestamps');
  if (end > now + 30000 || start > now + 30000) throw new Error('Proof is from the future');
  const variables = { run: directory, workspace: join(directory, 'workspace'), node: process.execPath, npm: await realpath(join(dirname(process.execPath), 'npm')) };
  const configured = commands(plan, variables);
  for (const [list, actual] of [[configured.steps, proof.steps], [configured.cleanup, proof.cleanupSteps]]) {
    if (!Array.isArray(actual) || actual.length !== list.length) throw new Error('Incomplete steps');
    for (const [i, expected] of list.entries()) {
      const step = actual[i];
      if (step.id !== expected.id || step.command !== expected.command || !same(step.args, expected.args) || step.cwd !== expected.cwd || step.exitCode !== 0 || step.signal || step.timedOut || step.aborted || step.error || !/^logs\/(cleanup-)?\d+-[a-z0-9-]+\.log$/.test(step.log)) throw new Error('Required steps differ or failed');
      const bytes = await regular(join(directory, step.log));
      if (hash(bytes) !== step.logHash) throw new Error('Log hash mismatch');
      validateOutput(expected, bytes);
    }
  }
  if (proof.artifacts?.length !== (plan.artifacts ?? []).length) throw new Error('Missing artifacts');
  for (const [i, expected] of (plan.artifacts ?? []).entries()) {
    const actual = proof.artifacts[i]; if (actual.path !== expected.path || actual.stored !== 'artifacts/' + i + '.dat') throw new Error('Artifact differs');
    const bytes = await regular(join(directory, actual.stored));
    if (hash(bytes) !== actual.hash || !same(validateArtifact(expected, bytes), actual.coverage)) throw new Error('Artifact hash or coverage mismatch');
  }
  return proof;
}

async function cli() {
  if (Number(process.versions.node.split('.')[0]) !== 22 || !process.getuid) throw new Error('Own checks require Node22 on POSIX');
  const root = await realpath(join(dirname(fileURLToPath(import.meta.url)), '../..'));
  const state = join(await realpath(tmpdir()), 'own-checks-' + process.getuid() + '-' + hash(root).slice(0, 20));
  const plan = await readJson(join(root, 'scripts/own-ci/plan.json'));
  if (process.argv.length > 3 || process.argv[2] && process.argv[2] !== '--verify') throw new Error('Usage: scripts/check-release [--verify]');
  const proof = process.argv[2] ? await verifyGate({ root, state, plan }) : await runGate({ root, state, plan });
  console.log(json({ status: proof.status, source: proof.source, state, finishedAt: proof.finishedAt, errors: proof.errors }));
  if (proof.status !== 'passed') process.exitCode = 1;
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) cli().catch(e => { console.error('[own-checks] ' + e.message); process.exitCode = 1; });

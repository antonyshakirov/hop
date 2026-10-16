import { constants } from 'node:fs';
import { spawn, execFileSync } from 'node:child_process';
import { mkdir, readFile, realpath, writeFile, cp, chmod, lstat } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { isolatedRun, nativeEnvironment, sandboxProfile, prepareNativeTemporary, readPrivateNativeFile } from './native.mjs';
import { verifyCodeqlTree } from './codeql-sdk-tree.mjs';
import { prepareCodeqlBuild } from './codeql-build.mjs';
import { runCodeql } from './codeql.mjs';
import { summarizeTests, validateMessages, parsePreparingVersion } from './hop-report.mjs';

const mode = process.argv[2];
if (process.platform !== 'darwin' || process.argv.length !== 3 || !['toolchain', 'messages', 'build', 'tests', 'canvas', 'export', 'live', 'translations', 'version', 'codeql'].includes(mode)) throw new Error('Usage on macOS: hop-step.mjs toolchain|messages|build|tests|canvas|export|live|translations|version|codeql');
const run = await isolatedRun({ home: process.env.HOME, temporary: process.env.TMPDIR, workspace: process.cwd() });
const bin = join(run, 'bin');
await mkdir(bin, { recursive: true });
const xcrun = '#!/bin/sh\nexec /usr/bin/xcrun --no-cache "$@"\n';
try { await writeFile(join(bin, 'xcrun'), xcrun, { mode: 0o700, flag: 'wx' }); }
catch (error) { if (error.code !== 'EEXIST' || (await readPrivateNativeFile(join(bin, 'xcrun'))).toString('utf8') !== xcrun) throw error; }
const env = nativeEnvironment(run, { ...process.env, PATH: bin + ':' + process.env.PATH });
const profile = join(run, 'hop-' + mode + '.sb');
const tools = [];
if (mode === 'codeql') {
  for (const directory of process.env.PATH.split(':')) {
    try { const candidate = await realpath(join(directory, 'codeql')); tools.push(dirname(candidate)); break; }
    catch (error) { if (!['ENOENT', 'ENOTDIR'].includes(error.code)) throw error; }
  }
  if (!tools.length) throw new Error('Pinned CodeQL 2.27.2 must be available on PATH');
  const sdkReceipt = await verifyCodeqlTree(tools[0]);
  console.log('Authenticated pinned CodeQL SDK: ' + JSON.stringify(sdkReceipt));
  const privateSdk = join(run, 'codeql-sdk');
  await cp(tools[0], privateSdk, { recursive: true, force: false, errorOnExist: true, verbatimSymlinks: true, mode: constants.COPYFILE_FICLONE });
  await chmod(join(privateSdk, 'codeql'), (await lstat(join(privateSdk, 'codeql'))).mode & 0o555);
  await verifyCodeqlTree(privateSdk);
  tools[0] = privateSdk;
}
await writeFile(profile, sandboxProfile({ run, node: dirname(process.execPath), tools, namedPasteboard: mode === 'export' }), { mode: 0o600, flag: 'wx' });
let temporaryLibrary;
async function command(executable, args, overrides = {}) {
  const childEnv = { ...env, ...overrides };
  let stdout = '', stderr = '';
  const launch = temporaryLibrary ? ['/usr/bin/env', 'DYLD_INSERT_LIBRARIES=' + temporaryLibrary + (childEnv.DYLD_INSERT_LIBRARIES ? ':' + childEnv.DYLD_INSERT_LIBRARIES : ''), executable, ...args] : [executable, ...args];
  const child = spawn('/usr/bin/sandbox-exec', ['-f', profile, ...launch], { env: childEnv, stdio: ['ignore', 'pipe', 'pipe'] });
  child.stdout.on('data', chunk => { stdout += chunk; process.stdout.write(chunk); });
  child.stderr.on('data', chunk => { stderr += chunk; process.stderr.write(chunk); });
  const result = await new Promise((done, reject) => { child.once('error', reject); child.once('close', (code, signal) => done({ code, signal })); });
  if (result.code !== 0 || result.signal) throw new Error('Hop command failed: ' + JSON.stringify({ executable, args, ...result }));
  return { stdout, stderr };
}
temporaryLibrary = await prepareNativeTemporary(run, command);
if (mode === 'messages') {
  const base = '5b5b006c08c4d996cf26e898d46d1eb3afe63c69';
  const gitEnv = { PATH: process.env.PATH, GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_COUNT: '0', LANG: 'C' };
  const git = args => execFileSync('git', ['-c', 'core.hooksPath=/dev/null', ...args], { env: gitEnv, encoding: 'utf8' }).trim();
  git(['merge-base', '--is-ancestor', base, 'HEAD']);
  const commits = git(['rev-list', base + '..HEAD']).split('\n').filter(Boolean);
  if (!commits.length) commits.push(git(['rev-parse', 'HEAD']));
  validateMessages(commits.map(sha => git(['log', '-1', '--format=%B', sha])));
  console.log('Incoming commit messages checked: ' + commits.length);
} else if (mode === 'toolchain') {
  const result = await command('swift', ['--version']);
  await writeFile('hop-toolchain.json', JSON.stringify({ swift: result.stdout.trim(), platform: process.platform, arch: process.arch }) + '\n', { flag: 'wx', mode: 0o600 });
} else if (mode === 'build') {
  const result = await command('swift', ['build', '--disable-sandbox', '--build-system', 'native']);
  if (/^.*: (error|warning):/m.test(result.stdout + result.stderr)) throw new Error('Swift build produced warnings or errors');
} else if (mode === 'tests') {
  const list = await command('swift', ['test', '--disable-sandbox', '--build-system', 'native', 'list']);
  await writeFile('hop-test-discovery.txt', list.stdout, { flag: 'wx', mode: 0o600 });
  const result = await command('swift', ['test', '--disable-sandbox', '--build-system', 'native']);
  await writeFile('hop-test-output.txt', result.stdout + result.stderr, { flag: 'wx', mode: 0o600 });
  const summary = summarizeTests(list.stdout, result.stdout + result.stderr);
  await writeFile('hop-test-summary.json', JSON.stringify(summary) + '\n', { flag: 'wx', mode: 0o600 });
  console.log(`1..${summary.passed}\n# tests ${summary.passed}\n# fail 0\n# skipped 0`);
} else if (mode === 'codeql') {
  const launcherSource = join(run, 'swift-launcher.c');
  await writeFile(launcherSource, await readFile(new URL('./swift-launcher.c', import.meta.url)), { mode: 0o600, flag: 'wx' });
  await command('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang', ['-isysroot', '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk', '-Wall', '-Wextra', '-Werror', launcherSource, '-o', join(bin, 'swift')]);
  env.HOP_PRIVATE_SWIFT_BUILD = await prepareCodeqlBuild(run, command);
  env.SWIFT_EXEC = join(bin, 'swiftc');
  env.SWIFT_DRIVER_SWIFT_FRONTEND_EXEC = join(bin, 'swift-frontend');
  env.HOP_PRIVATE_ATOMIC_LIBRARY = temporaryLibrary;
  const mktemp = '#!/bin/sh\nif [ "$#" = 2 ] && [ "$1" = -t ] && [ "$2" = codeql.XXXXXXXX ]; then exec /usr/bin/mktemp "$TMPDIR/codeql.XXXXXXXX"; fi\nexit 64\n';
  await writeFile(join(bin, 'mktemp'), mktemp, { mode: 0o700, flag: 'wx' });
  await runCodeql({ run, workspace: process.cwd(), codeql: join(tools[0], 'codeql'), command });
} else {
  const binary = join(process.cwd(), '.build/debug/Hop');
  const args = { canvas: ['--canvas-selftest', join(run, 'canvas-selftest.png')], export: ['--markup-selftest', join(run, 'markup-selftest.png')], live: ['--live-selftest', join(run, 'live')], translations: ['--l10n-check'], version: ['--preparing-version'] }[mode];
  if (mode === 'live') await mkdir(join(run, 'live'));
  const result = await command(binary, args);
  if (mode === 'version') await writeFile('hop-preparing-version.json', JSON.stringify({ version: parsePreparingVersion(result.stdout) }) + '\n', { flag: 'wx', mode: 0o600 });
}

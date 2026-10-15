import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, readFile, realpath, rm, writeFile, symlink } from 'node:fs/promises';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { isolatedRun, sandboxProfile, prepareNativeTemporary } from './native.mjs';

const swift = '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc';
const fixture = `import Foundation
import Darwin
let args = CommandLine.arguments
let home = args[1], outside = args[2], mode = args[3]
func need(_ condition: Bool, _ code: Int32) { if !condition { exit(code) } }
if mode == "files" {
    var denied = 0
    do { _ = try String(contentsOfFile: outside + "/canary.txt", encoding: .utf8) } catch { denied += 1 }
    do { try "changed".write(toFile: outside + "/forbidden.txt", atomically: false, encoding: .utf8) } catch { denied += 1 }
    try "owned".write(toFile: home + "/allowed.txt", atomically: false, encoding: .utf8)
    need(denied == 2, 7)
    print("outside read/write denied; owned write allowed")
} else if mode == "atomic" {
    do {
        let expectedTemporary = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"]!).resolvingSymlinksInPath().path
        need(FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path == expectedTemporary, 18)
        need(URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().path == expectedTemporary, 19)
        let file = URL(fileURLWithPath: home + "/atomic.json")
        try Data("first".utf8).write(to: file, options: .atomic)
        try Data("second".utf8).write(to: file, options: .atomic)
        need(try String(contentsOf: file, encoding: .utf8) == "second", 14)
        let temporary = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: file, create: true)
        need(temporary.resolvingSymlinksInPath().path.hasPrefix(URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"]!).resolvingSymlinksInPath().path + "/"), 15)
        var denied = false
        do { try Data("forbidden".utf8).write(to: URL(fileURLWithPath: outside + "/canary.txt"), options: .atomic) } catch { denied = true }
        need(denied, 16)
        print("atomic writes and replacement directories stay private; sibling denied")
    } catch { print("atomic replacement failed:", String(describing: error)); exit(17) }
} else if mode == "preferences" {
    need(URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path).resolvingSymlinksInPath().path == URL(fileURLWithPath: home).resolvingSymlinksInPath().path && URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path == URL(fileURLWithPath: home).resolvingSymlinksInPath().path, 8)
    let defaults = UserDefaults(suiteName: args[4])!
    need(defaults.string(forKey: "outside-canary") == nil, 9)
    defaults.set("owned", forKey: "probe")
    need(defaults.string(forKey: "probe") == "owned", 10)
    defaults.removePersistentDomain(forName: args[4])
    print("synthetic home and in-process preferences isolated")
} else if mode == "preferences-canary" {
    let data = try Data(contentsOf: URL(fileURLWithPath: home + "/Library/Preferences/" + args[4] + ".plist"))
    let value = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: String]
    need(value["outside-canary"] == "synthetic only", 13)
    print("synthetic preference canary bytes visible from its own home")
} else if mode == "network" {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    var address = sockaddr_in(); address.sin_family = sa_family_t(AF_INET)
    address.sin_port = UInt16(args[4])!.bigEndian
    inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)
    let connected = withUnsafePointer(to: &address) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    close(fd); need(connected == 0, 11)
    let external = socket(AF_INET, SOCK_STREAM, 0)
    address.sin_port = UInt16(443).bigEndian
    inet_pton(AF_INET, "192.0.2.1", &address.sin_addr)
    let rejected = withUnsafePointer(to: &address) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(external, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    let error = errno; close(external)
    need(rejected == -1 && [EPERM, EACCES].contains(error), 12)
    print("loopback permitted; external TCP denied by OS")
}
`;

async function command(executable, args, options) {
  let stdout = '', stderr = '';
  const child = spawn(executable, args, { ...options, stdio: ['ignore', 'pipe', 'pipe'] });
  const timer = setTimeout(() => child.kill('SIGKILL'), 60000);
  child.stdout.on('data', chunk => stdout += chunk); child.stderr.on('data', chunk => stderr += chunk);
  try { return await new Promise((done, reject) => { child.once('error', reject); child.once('close', (status, signal) => done({ status, signal, stdout, stderr })); }); }
  finally { clearTimeout(timer); }
}

async function setup(t) {
  const base = await realpath(await mkdtemp(join(tmpdir(), 'hop-isolation-')));
  t.after(() => rm(base, { recursive: true, force: true }));
  const run = join(base, 'run'), outside = join(base, 'outside'), home = join(run, 'home'), temporary = join(run, 'tmp');
  await mkdir(home, { recursive: true, mode: 0o700 }); await mkdir(temporary, { mode: 0o700 }); await mkdir(outside);
  await writeFile(join(outside, 'canary.txt'), 'synthetic only');
  const source = join(run, 'probe.swift'), binary = join(run, 'probe');
  await writeFile(source, fixture);
  const env = { PATH: process.env.PATH, HOME: home, CFFIXED_USER_HOME: home, TMPDIR: temporary };
  const profile = join(run, 'native.sb');
  await writeFile(profile, sandboxProfile({ run, node: dirname(process.execPath) }));
  const library = await prepareNativeTemporary(run, async (executable, args) => {
    const result = await command('/usr/bin/sandbox-exec', ['-f', profile, executable, ...args], { env, cwd: run });
    assert.equal(result.status, 0, JSON.stringify(result));
  });
  const compiled = await command('/usr/bin/sandbox-exec', ['-f', profile, '/usr/bin/env', 'DYLD_INSERT_LIBRARIES=' + library, swift, ['-sdk', '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk', '-module-cache-path', join(run, 'module-cache'), source, '-o', binary]].flat(), { env, cwd: run });
  assert.equal(compiled.status, 0, JSON.stringify(compiled));
  return { run, outside, home, env, binary, profile, library };
}

async function probe(context, mode, extra = []) {
  const result = await command('/usr/bin/sandbox-exec', ['-f', context.profile, '/usr/bin/env', 'DYLD_INSERT_LIBRARIES=' + context.library, context.binary, context.home, context.outside, mode, ...extra], { env: context.env, cwd: context.run });
  assert.equal(result.status, 0, JSON.stringify(result));
  return result;
}

test('native Swift cannot read or change a synthetic sibling', async t => {
  const context = await setup(t);
  await probe(context, 'files');
  assert.equal(await readFile(join(context.home, 'allowed.txt'), 'utf8'), 'owned');
  assert.equal(await readFile(join(context.outside, 'canary.txt'), 'utf8'), 'synthetic only');
  await assert.rejects(readFile(join(context.outside, 'forbidden.txt')), { code: 'ENOENT' });
});

test('Foundation preferences use the synthetic home and deny preferences services', async t => {
  const context = await setup(t);
  const suite = 'own-ci-' + process.pid + '-' + Date.now();
  const directory = join(context.outside, 'Library', 'Preferences');
  await mkdir(directory, { recursive: true });
  const bytes = '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>outside-canary</key><string>synthetic only</string></dict></plist>';
  const file = join(directory, suite + '.plist');
  await writeFile(file, bytes);
  const outsideProfile = join(context.run, 'outside.sb');
  await writeFile(outsideProfile, sandboxProfile({ run: context.outside, node: dirname(process.execPath), tools: [context.run] }));
  const canary = await command('/usr/bin/sandbox-exec', ['-f', outsideProfile, context.binary, context.outside, context.outside, 'preferences-canary', suite], { env: { ...context.env, HOME: context.outside, CFFIXED_USER_HOME: context.outside }, cwd: context.outside });
  assert.equal(canary.status, 0, JSON.stringify(canary));
  await probe(context, 'preferences', [suite]);
  assert.equal(await readFile(file, 'utf8'), bytes);
  assert.match(sandboxProfile({ run: context.run, node: dirname(process.execPath) }), /deny mach-lookup[\s\S]*com\.apple\.cfprefsd/);
});

test('native Swift permits loopback and denies external TCP', async t => {
  const context = await setup(t), server = createServer(socket => socket.end());
  await new Promise((done, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', done); });
  try { await probe(context, 'network', [String(server.address().port)]); }
  finally { await new Promise(done => server.close(done)); }
});

test('internal steps reject normal HOME and workspaces outside the private run', async t => {
  const run = await realpath(await mkdtemp(join(tmpdir(), 'run-')));
  t.after(() => rm(run, { recursive: true, force: true }));
  for (const directory of ['home', 'tmp', 'workspace', 'person']) await mkdir(join(run, directory));
  const paths = { home: join(run, 'home'), temporary: join(run, 'tmp'), workspace: join(run, 'workspace') };
  assert.equal(await isolatedRun(paths), run);
  await assert.rejects(isolatedRun({ ...paths, home: join(run, 'person') }));
  await assert.rejects(isolatedRun({ ...paths, workspace: run }));
  await assert.rejects(isolatedRun({ ...paths, temporary: run }));
});

test('atomic replacements stay inside the private temporary directory', async t => {
  const context = await setup(t);
  await probe(context, 'atomic');
  assert.equal(await readFile(join(context.outside, 'canary.txt'), 'utf8'), 'synthetic only');
});


test('native temporary cache refuses sibling symlinks before reading', async t => {
  const context = await setup(t);
  const library = join(context.run, 'private-atomic-temp.dylib');
  const receipt = library + '.json';
  const forbidden = async () => { throw new Error('Unexpected compiler invocation'); };
  for (const file of [receipt, library]) {
    const original = await readFile(file);
    await rm(file);
    await symlink(join(context.outside, 'canary.txt'), file);
    await assert.rejects(prepareNativeTemporary(context.run, forbidden), /not canonical/);
    await rm(file);
    await writeFile(file, original, { mode: 0o600, flag: 'wx' });
  }
  assert.equal(await readFile(join(context.outside, 'canary.txt'), 'utf8'), 'synthetic only');
});

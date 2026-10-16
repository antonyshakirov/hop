import { createHash } from 'node:crypto';
import { constants } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { lstat, realpath, readFile, writeFile, open } from 'node:fs/promises';
import { basename, dirname, join } from 'node:path';

export function sandboxProfile({ run, node, tools = [], namedPasteboard = false }) {
  const path = value => JSON.stringify(value);
  const reads = ['/System', '/usr/bin', '/usr/sbin', '/usr/lib', '/usr/libexec', '/usr/share', '/usr/standalone', '/bin', '/sbin', '/Library/Apple', '/Library/Developer', '/Applications/Xcode.app', '/private/etc', '/etc', '/private/var/db/dyld', '/private/var/db/timezone', '/var/db/dyld', '/var/db/timezone', '/dev', run, node, ...tools];
  const literals = ['/', '/private', '/private/tmp', dirname(run), '/Library', '/Library/Preferences', '/Library/Preferences/com.apple.dt.Xcode.plist', '/Library/Preferences/com.apple.dt.CommandLineTools.plist', '/var', '/var/db', '/var/db/xcode_select_link', '/private/var/db/xcode_select_link'];
  return `(version 1)
(allow default)
(deny file-read-data file-map-executable (require-not (require-any ${literals.map(value => `(literal ${path(value)})`).join(' ')} ${reads.map(value => `(subpath ${path(value)})`).join(' ')})))
(deny file-read-data (subpath "/Library/Keychains"))
(deny file-write* (require-not (require-any (subpath ${path(run)}) (literal "/dev/null"))))
${tools.map(directory => `(deny file-write* (subpath ${path(directory)}))`).join('\n')}
(deny network*)
(deny mach-lookup (global-name "com.apple.securityd") (global-name "com.apple.securityd.xpc") (global-name "com.apple.security.agent") (global-name "com.apple.secd") (global-name "com.apple.cfprefsd.daemon") (global-name "com.apple.cfprefsd.agent") ${namedPasteboard ? '' : '(global-name "com.apple.pasteboard.1")'})
(allow network-bind (local ip "localhost:*"))
(allow network-inbound (local ip "localhost:*"))
(allow network-outbound (remote ip "localhost:*"))
`;
}

export function nativeEnvironment(run, env) {
  const home = join(run, 'home');
  return { ...env, xcrun_nocache: '1', DEVELOPER_DIR: '/Applications/Xcode.app/Contents/Developer', HOME: home, CFFIXED_USER_HOME: home, TMPDIR: join(run, 'tmp'), CLANG_MODULE_CACHE_PATH: join(run, 'clang-module-cache'), SWIFTPM_MODULECACHE_OVERRIDE: join(run, 'swift-module-cache') };
}

export async function isolatedRun({ home, temporary, workspace }) {
  const actualHome = await realpath(home), actualTemporary = await realpath(temporary), actualWorkspace = await realpath(workspace);
  const run = dirname(actualHome), metadata = await lstat(run);
  if (!/^(run|hop-preflight)-[a-zA-Z0-9]+$/.test(basename(run)) || actualHome !== join(run, 'home') || actualTemporary !== join(run, 'tmp') || actualWorkspace !== join(run, 'workspace') || !metadata.isDirectory() || metadata.isSymbolicLink() || metadata.uid !== process.getuid() || metadata.mode & 0o077) throw new Error('Hop checks require a private isolated run/home/tmp/workspace');
  return run;
}

export async function readPrivateNativeFile(path) {
  if (await realpath(path) !== path) throw new Error('Native adapter file is not canonical');
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const metadata = await file.stat();
    if (!metadata.isFile() || metadata.uid !== process.getuid() || metadata.size > 16 * 1024 * 1024) throw new Error('Unsafe native adapter file');
    return await file.readFile();
  } finally { await file.close(); }
}

export async function prepareNativeTemporary(run, compile) {
  const source = fileURLToPath(new URL('./atomic-temp.m', import.meta.url));
  const library = join(run, 'private-atomic-temp.dylib'), receipt = library + '.json';
  const hash = bytes => createHash('sha256').update(bytes).digest('hex');
  const sourceBytes = await readFile(source), sourceHash = hash(sourceBytes);
  try {
    const previous = JSON.parse((await readPrivateNativeFile(receipt)).toString('utf8'));
    if (previous.sourceHash !== sourceHash || previous.libraryHash !== hash(await readPrivateNativeFile(library))) throw new Error('Native temporary adapter changed');
    return library;
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
  const privateSource = join(run, 'private-atomic-temp.m');
  await writeFile(privateSource, sourceBytes, { mode: 0o600, flag: 'wx' });
  const clang = '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang';
  await compile(clang, ['-arch', 'arm64', '-arch', 'x86_64', '-isysroot', '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk', '-Wall', '-Wextra', '-Werror', '-dynamiclib', '-framework', 'Foundation', privateSource, '-o', library]);
  await writeFile(receipt, JSON.stringify({ sourceHash, libraryHash: hash(await readPrivateNativeFile(library)) }) + '\n', { mode: 0o600, flag: 'wx' });
  return library;
}

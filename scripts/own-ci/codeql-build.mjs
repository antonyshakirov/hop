import { chmod, readFile, symlink, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';

// Relocate only the disposable SwiftPM copy. Short absolute rpaths keep the
// official CodeQL relocator within Mach-O header space; Xcode stays untouched.
export async function prepareCodeqlBuild(run, command) {
  const toolchain = '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr';
  for (const name of ['swift-build', 'swift-driver', 'swift-frontend']) {
    const original = join(toolchain, 'bin', name);
    const copy = join(run, 'bin', name);
    await writeFile(copy, await readFile(original), { mode: 0o700, flag: 'wx' });
    await chmod(copy, 0o700);
    const result = await command(join(toolchain, 'bin/otool'), ['-l', original]);
    const paths = [...result.stdout.matchAll(/cmd LC_RPATH\n\s+cmdsize \d+\n\s+path (.+) \(offset \d+\)/g)].map(match => match[1]);
    if (!paths.length) throw new Error('Missing SwiftPM runtime paths');
    const args = [];
    for (const [index, path] of paths.entries()) {
      if (!path.startsWith('@executable_path/')) continue;
      const target = resolve(toolchain, 'bin', path.slice('@executable_path/'.length));
      if (!target.startsWith('/Applications/Xcode.app/')) throw new Error('Unexpected SwiftPM runtime path');
      const alias = join(run, name + '-l' + index);
      await symlink(target, alias);
      args.push('-rpath', path, alias);
    }
    if (!args.length) throw new Error('No SwiftPM relative paths were reviewed');
    await command(join(toolchain, 'bin/install_name_tool'), [...args, copy]);
    await command('/usr/bin/codesign', ['--force', '--sign', '-', copy]);
  }
  await symlink('swift-frontend', join(run, 'bin/swiftc'));
  await symlink(join(toolchain, 'lib'), join(run, 'lib'));
  return join(run, 'bin/swift-build');
}

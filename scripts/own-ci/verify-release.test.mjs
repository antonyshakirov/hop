import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import { execFile } from 'node:child_process';
import { copyFile, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import test from 'node:test';

const execute = promisify(execFile);
const repository = fileURLToPath(new URL('../../', import.meta.url));
const version = '2.4.0';
const bundleID = 'com.antonshakirov.minimo';
const mirror = 'mirror.fixture.invalid';
const products = [
  { arch: 'arm64', zip: `Hop-${version}.zip`, sig: `Hop-${version}.zip.sig`, dmg: 'Hop.dmg' },
  { arch: 'x86_64', zip: `Hop-${version}-intel.zip`, sig: `Hop-${version}-intel.zip.sig`, dmg: 'Hop-intel.dmg' },
];

function plist(values) {
  const escape = text => String(text).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  return '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict>'
    + Object.entries(values).map(([key, value]) => '<key>' + escape(key) + '</key>'
      + (typeof value === 'boolean' ? `<${value}/>` : '<string>' + escape(value) + '</string>')).join('')
    + '</dict></plist>\n';
}

const command = `#!${process.execPath}
const fs = require('node:fs');
const path = require('node:path');
const root = process.env.HOP_VERIFY_FIXTURE_ROOT;
const tool = path.basename(process.argv[1]);
const args = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(path.join(root, 'config.json'), 'utf8'));
const record = {tool, args};
if (tool === 'ditto') record.archiveTag = fs.readFileSync(args.at(-2)).subarray(0, 64).toString().split('\\n')[0];
fs.appendFileSync(path.join(root, 'commands.jsonl'), JSON.stringify(record) + '\\n');
const fail = () => process.exit(1);
if (tool === 'curl') {
  const url = args.find(arg => arg.startsWith('https://'));
  const output = args[args.indexOf('-o') + 1];
  if (!url || !output) fail();
  const parsed = new URL(url);
  if (!['hop.tools', '${mirror}'].includes(parsed.hostname) || !parsed.pathname.startsWith('/downloads/hop/')) fail();
  const resource = parsed.pathname.slice('/downloads/hop/'.length) + parsed.search;
  const source = path.join(root, parsed.hostname === 'hop.tools' ? 'primary' : 'mirror', resource);
  if (!fs.existsSync(source)) fail();
  if (output !== '/dev/null') fs.copyFileSync(source, output);
} else if (tool === 'ditto') {
  const archive = args.at(-2), destination = args.at(-1);
  const tag = fs.readFileSync(archive).subarray(0, 64).toString().split('\\n')[0];
  if (!tag.startsWith('HOP-FIXTURE:')) fail();
  const arch = tag.slice('HOP-FIXTURE:'.length);
  if (!['arm64', 'x86_64'].includes(arch)) fail();
  fs.mkdirSync(destination, {recursive: true});
  fs.cpSync(path.join(root, 'bundles', arch, 'Hop.app'), path.join(destination, 'Hop.app'), {recursive: true});
} else if (tool === 'lipo') {
  const file = args.find(arg => fs.existsSync(arg) && fs.statSync(arg).isFile());
  if (!file || !fs.existsSync(file + '.archs')) fail();
  const arches = fs.readFileSync(file + '.archs', 'utf8').trim().split(/\\s+/);
  if (args.includes('-verify_arch')) {
    const requested = args.slice(args.indexOf('-verify_arch') + 1).filter(arg => arg !== file && !arg.startsWith('-'));
    if (!requested.length || requested.some(arch => !arches.includes(arch))) fail();
  } else if (args.includes('-archs')) process.stdout.write(arches.join(' ') + '\\n');
  else fail();
} else if (tool === 'spctl') {
  if (config.gatekeeperFailure) fail();
  process.stderr.write('source=Notarized Developer ID\\n');
} else if (tool === 'xcrun') {
  if (args[0] !== 'stapler' || args[1] !== 'validate') fail();
  if (config.staplerFailure && args.at(-1).endsWith(config.staplerFailure)) fail();
} else if (tool === 'codesign') {
  const target = args.at(-1);
  if (config.signatureFailure && target.includes(config.signatureFailure)) fail();
  if (args.includes('--entitlements')) process.stdout.write('<?xml version="1.0"?><plist version="1.0"><dict><key>com.apple.developer.system-extension.install</key><true/></dict></plist>\\n');
  else if (args.some(arg => /^-d/.test(arg) || arg === '--display')) {
    const team = config.workerTeamMismatch && target.includes('HopAudioWorker.app') ? 'OTHERTEAM' : 'FIXTURETEAM';
    process.stderr.write('TeamIdentifier=' + team + '\\nAuthority=Developer ID Application: Fixture\\n');
  } else if (!args.includes('--verify')) fail();
} else fail();
`;

async function fixture(t) {
  const root = await mkdtemp('/private/tmp/hop-release-fixture-');
  t.after(() => rm(root, { recursive: true, force: true }));
  for (const name of ['scripts', 'Sources/Hop', 'bin', 'primary', 'mirror', 'home', 'tmp'])
    await mkdir(join(root, name), { recursive: true });
  await copyFile(join(repository, 'scripts/verify-release.sh'), join(root, 'scripts/verify-release.sh'));
  for (const name of ['Info.plist', 'HopAudioWorker-Info.plist'])
    await copyFile(join(repository, 'scripts', name), join(root, 'scripts', name));
  try { await copyFile(join(repository, 'scripts/verify-release-signature.mjs'), join(root, 'scripts/verify-release-signature.mjs')); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  const key = generateKeyPairSync('ed25519');
  const rawPublic = key.publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64');
  const originalSource = await readFile(join(repository, 'Sources/Hop/UpdateChecker.swift'), 'utf8');
  const source = originalSource.replace(/(static let updatePublicKeyBase64 = ")[^"]+(";?)/,
    (_, prefix, suffix) => prefix + rawPublic + suffix);
  assert.notEqual(source, originalSource);
  await writeFile(join(root, 'Sources/Hop/UpdateChecker.swift'), source);
  for (const tool of ['curl', 'ditto', 'lipo', 'spctl', 'xcrun', 'codesign'])
    await writeFile(join(root, 'bin', tool), command, { mode: 0o700 });
  const manifest = {
    version, zip: `https://hop.tools/downloads/hop/${products[0].zip}`,
    sig: `https://hop.tools/downloads/hop/${products[0].sig}`,
    zipIntel: `https://hop.tools/downloads/hop/${products[1].zip}`,
    sigIntel: `https://hop.tools/downloads/hop/${products[1].sig}`,
  };
  await writeFile(join(root, 'config.json'), '{}');
  await writeFile(join(root, 'commands.jsonl'), '');
  for (const product of products) {
    const app = join(root, 'bundles', product.arch, 'Hop.app');
    const filter = join(app, 'Contents/Library/SystemExtensions', bundleID + '.netfilter.systemextension');
    const worker = join(app, 'Contents/Helpers/HopAudioWorker.app');
    await executable(join(app, 'Contents/MacOS/Hop'), product.arch);
    await executable(join(filter, 'Contents/MacOS', bundleID + '.netfilter'), product.arch);
    await executable(join(worker, 'Contents/MacOS/HopAudioWorker'), 'arm64 x86_64');
    await writeFile(join(app, 'Contents/Info.plist'), plist({ CFBundleIdentifier: bundleID,
      CFBundleShortVersionString: version, CFBundleExecutable: 'Hop', CFBundleName: 'Hop' }));
    await writeFile(join(filter, 'Contents/Info.plist'), plist({ CFBundleIdentifier: bundleID + '.netfilter',
      CFBundleShortVersionString: version, CFBundleExecutable: bundleID + '.netfilter' }));
    await writeFile(join(worker, 'Contents/Info.plist'), plist({ CFBundleIdentifier: bundleID + '.audio-worker',
      CFBundleExecutable: 'HopAudioWorker' }));
    const archive = Buffer.concat([Buffer.from('HOP-FIXTURE:' + product.arch + '\n'), Buffer.alloc(1_000_001, 0x5a)]);
    const signature = sign(null, archive, key.privateKey);
    for (const host of ['primary', 'mirror']) {
      await writeFile(join(root, host, product.zip), archive);
      await writeFile(join(root, host, product.sig), signature);
      await writeFile(join(root, host, product.dmg), 'DMG-FIXTURE:' + product.arch);
    }
  }
  for (const host of ['primary', 'mirror'])
    await writeFile(join(root, host, 'latest.json'), JSON.stringify(manifest));
  return {
    root, manifest,
    app: arch => join(root, 'bundles', arch, 'Hop.app'),
    file: (host, name) => join(root, host, name),
    async config(value) { await writeFile(join(root, 'config.json'), JSON.stringify(value)); },
    async run() {
      const env = { PATH: join(root, 'bin') + ':' + dirname(process.execPath) + ':/usr/bin:/bin:/usr/sbin:/sbin',
        HOME: join(root, 'home'), TMPDIR: join(root, 'tmp') + '/', LANG: 'C', TZ: 'UTC',
        HOP_VERIFY_FIXTURE_ROOT: root, HOP_MIRROR_HOSTS: mirror };
      try {
        const result = await execute('/bin/zsh', [join(root, 'scripts/verify-release.sh'), version],
          { cwd: root, env, timeout: 20_000, maxBuffer: 2 * 1024 * 1024 });
        return { code: 0, output: result.stdout + result.stderr };
      } catch (error) {
        if (typeof error.code !== 'number') throw error;
        return { code: error.code, output: (error.stdout ?? '') + (error.stderr ?? '') };
      }
    },
    async commands() {
      return (await readFile(join(root, 'commands.jsonl'), 'utf8')).split('\n').filter(Boolean).map(line => JSON.parse(line));
    },
  };
}

async function executable(file, arches) {
  await mkdir(dirname(file), { recursive: true });
  await writeFile(file, 'synthetic executable metadata\n', { mode: 0o700 });
  await writeFile(file + '.archs', arches + '\n');
}

async function rejected(fixture) {
  const result = await fixture.run();
  assert.notEqual(result.code, 0, 'unsafe release was accepted:\n' + result.output);
  return result;
}

test('valid ARM and Intel fixtures allow a universal audio worker', async t => {
  const f = await fixture(t); const result = await f.run();
  assert.equal(result.code, 0, result.output);
});

test('both architecture archives, signatures and DMGs are fetched from each host', async t => {
  const f = await fixture(t); const result = await f.run(); assert.equal(result.code, 0, result.output);
  const fetched = (await f.commands()).filter(row => row.tool === 'curl').flatMap(row => row.args.filter(arg => arg.startsWith('https://')));
  for (const host of ['hop.tools', mirror]) for (const product of products)
    for (const name of [product.zip, product.sig, product.dmg])
      assert.ok(fetched.includes(`https://${host}/downloads/hop/${name}`), `missing ${host}/${name}`);
});

for (const product of products) test(`invalid ${product.arch} signature fails before archive extraction`, async t => {
  const f = await fixture(t); const bytes = await readFile(f.file('primary', product.sig)); bytes[0] ^= 0xff;
  await writeFile(f.file('primary', product.sig), bytes);
  await rejected(f);
  const extractions = (await f.commands()).filter(row => row.tool === 'ditto');
  assert.ok(extractions.every(row => row.archiveTag !== 'HOP-FIXTURE:' + product.arch), 'invalid archive was extracted');
});

test('a modified archive with an unchanged valid-length signature is rejected', async t => {
  const f = await fixture(t); const bytes = await readFile(f.file('primary', products[0].zip)); bytes[bytes.length - 1] ^= 1;
  await writeFile(f.file('primary', products[0].zip), bytes); await rejected(f);
});

test('signatures from another disposable key are rejected', async t => {
  const f = await fixture(t); const other = generateKeyPairSync('ed25519');
  for (const product of products) await writeFile(f.file('primary', product.sig),
    sign(null, await readFile(f.file('primary', product.zip)), other.privateKey));
  await rejected(f);
});

test('swapped ARM and Intel signatures are rejected', async t => {
  const f = await fixture(t); const arm = await readFile(f.file('primary', products[0].sig));
  const intel = await readFile(f.file('primary', products[1].sig));
  await writeFile(f.file('primary', products[0].sig), intel);
  await writeFile(f.file('primary', products[1].sig), arm); await rejected(f);
});

test('missing Intel manifest fields cannot pass an ARM-only verification', async t => {
  const f = await fixture(t); delete f.manifest.zipIntel; delete f.manifest.sigIntel;
  await writeFile(f.file('primary', 'latest.json'), JSON.stringify(f.manifest)); await rejected(f);
});

test('nested archive paths cannot be replaced by a mirror basename', async t => {
  const f = await fixture(t); const product = products[0];
  await mkdir(join(f.root, 'primary/nested'));
  await copyFile(f.file('primary', product.zip), f.file('primary', 'nested/' + product.zip));
  f.manifest.zip = `https://hop.tools/downloads/hop/nested/${product.zip}`;
  for (const host of ['primary', 'mirror'])
    await writeFile(f.file(host, 'latest.json'), JSON.stringify(f.manifest));
  await rejected(f);
});

test('archive query strings are rejected even when both hosts serve matching bytes', async t => {
  const f = await fixture(t); const product = products[1];
  for (const host of ['primary', 'mirror'])
    await copyFile(f.file(host, product.zip), f.file(host, product.zip + '?download=1'));
  f.manifest.zipIntel += '?download=1';
  for (const host of ['primary', 'mirror'])
    await writeFile(f.file(host, 'latest.json'), JSON.stringify(f.manifest));
  await rejected(f);
});

for (const arch of ['arm64', 'x86_64']) {
  test(`${arch} archive rejects a main executable with the other architecture`, async t => {
    const f = await fixture(t); await writeFile(join(f.app(arch), 'Contents/MacOS/Hop.archs'), arch === 'arm64' ? 'x86_64' : 'arm64');
    await rejected(f);
  });
  test(`${arch} archive rejects a development bundle identifier`, async t => {
    const f = await fixture(t); await writeFile(join(f.app(arch), 'Contents/Info.plist'), plist({
      CFBundleIdentifier: bundleID + '.dev', CFBundleShortVersionString: version, CFBundleExecutable: 'Hop' }));
    await rejected(f);
  });
  test(`${arch} archive rejects the open-Sound diagnostic flag`, async t => {
    const f = await fixture(t); await writeFile(join(f.app(arch), 'Contents/Info.plist'), plist({
      CFBundleIdentifier: bundleID, CFBundleShortVersionString: version, CFBundleExecutable: 'Hop', HopOpenSoundAtLaunch: true }));
    await rejected(f);
  });
}

test('Intel bundle version must match the release', async t => {
  const f = await fixture(t); await writeFile(join(f.app('x86_64'), 'Contents/Info.plist'), plist({
    CFBundleIdentifier: bundleID, CFBundleShortVersionString: '2.3.2', CFBundleExecutable: 'Hop' }));
  await rejected(f);
});

test('missing audio worker is rejected', async t => {
  const f = await fixture(t); await rm(join(f.app('x86_64'), 'Contents/Helpers/HopAudioWorker.app'), { recursive: true });
  await rejected(f);
});

test('audio worker without the archive architecture is rejected', async t => {
  const f = await fixture(t); await writeFile(join(f.app('x86_64'), 'Contents/Helpers/HopAudioWorker.app/Contents/MacOS/HopAudioWorker.archs'), 'arm64');
  await rejected(f);
});

test('audio worker bundle identity is checked', async t => {
  const f = await fixture(t); await writeFile(join(f.app('x86_64'), 'Contents/Helpers/HopAudioWorker.app/Contents/Info.plist'), plist({
    CFBundleIdentifier: bundleID + '.dev.audio-worker', CFBundleExecutable: 'HopAudioWorker' }));
  await rejected(f);
});

test('network filter must have the archive architecture', async t => {
  const f = await fixture(t); await writeFile(join(f.app('x86_64'), 'Contents/Library/SystemExtensions',
    bundleID + '.netfilter.systemextension/Contents/MacOS/' + bundleID + '.netfilter.archs'), 'arm64');
  await rejected(f);
});

test('network filter bundle identity must match the production app', async t => {
  const f = await fixture(t); await writeFile(join(f.app('x86_64'), 'Contents/Library/SystemExtensions',
    bundleID + '.netfilter.systemextension/Contents/Info.plist'), plist({
      CFBundleIdentifier: bundleID + '.dev.netfilter', CFBundleShortVersionString: version,
      CFBundleExecutable: bundleID + '.netfilter' }));
  await rejected(f);
});

test('network filter version must match the release', async t => {
  const f = await fixture(t); await writeFile(join(f.app('x86_64'), 'Contents/Library/SystemExtensions',
    bundleID + '.netfilter.systemextension/Contents/Info.plist'), plist({
      CFBundleIdentifier: bundleID + '.netfilter', CFBundleShortVersionString: '2.3.2',
      CFBundleExecutable: bundleID + '.netfilter' }));
  await rejected(f);
});

test('nested audio worker signature failure is rejected', async t => {
  const f = await fixture(t); await f.config({ signatureFailure: 'HopAudioWorker.app' }); await rejected(f);
});

test('nested audio worker signing team must match the app', async t => {
  const f = await fixture(t); await f.config({ workerTeamMismatch: true }); await rejected(f);
});

test('Gatekeeper refusal remains a failure', async t => {
  const f = await fixture(t); await f.config({ gatekeeperFailure: true }); await rejected(f);
});

test('Intel DMG must carry a valid stapled ticket', async t => {
  const f = await fixture(t); await f.config({ staplerFailure: 'Hop-intel.dmg' }); await rejected(f);
});

for (const product of products) for (const name of [product.zip, product.sig, product.dmg])
  test(`mirror byte mismatch is rejected for ${name}`, async t => {
    const f = await fixture(t); await writeFile(f.file('mirror', name), 'different bytes'); await rejected(f);
  });

test('malformed canonical public key fails closed', async t => {
  const f = await fixture(t); const file = join(f.root, 'Sources/Hop/UpdateChecker.swift');
  const source = await readFile(file, 'utf8');
  await writeFile(file, source.replace(/(static let updatePublicKeyBase64 = ")[^"]+(";?)/, '$1invalid$2'));
  await rejected(f);
});

test('missing canonical public key fails closed', async t => {
  const f = await fixture(t); const file = join(f.root, 'Sources/Hop/UpdateChecker.swift');
  const source = await readFile(file, 'utf8');
  await writeFile(file, source.replace(/^.*static let updatePublicKeyBase64 = .*\n/m, ''));
  await rejected(f);
});

test('ambiguous canonical public key definitions fail closed', async t => {
  const f = await fixture(t); const file = join(f.root, 'Sources/Hop/UpdateChecker.swift');
  const source = await readFile(file, 'utf8');
  const definition = source.match(/^.*static let updatePublicKeyBase64 = .*$/m)[0];
  await writeFile(file, source + '\n' + definition + '\n');
  await rejected(f);
});

import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { chmod, mkdir, mkdtemp, readdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import test from 'node:test';

const execute = promisify(execFile);
const repository = fileURLToPath(new URL('../../', import.meta.url));
const script = join(repository, 'scripts/upload-release.sh');
const builds = ['Hop-2.6.0.zip', 'Hop-2.6.0.zip.sig', 'Hop.dmg'];

// Fake network tools: `host:/dir` means the local /dir, ssh runs the remote
// script locally, curl serves hop.tools from the primary's folder.
const tool = `#!${process.execPath}
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {spawnSync} = require('node:child_process');
const root = process.env.HOP_UPLOAD_FIXTURE_ROOT;
const name = path.basename(process.argv[1]);
const args = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(path.join(root, 'config.json'), 'utf8'));
const log = record => fs.appendFileSync(path.join(root, 'commands.jsonl'), JSON.stringify({tool: name, ...record}) + '\\n');
const count = key => {
  const file = path.join(root, 'count-' + key);
  const value = (fs.existsSync(file) ? Number(fs.readFileSync(file, 'utf8')) : 0) + 1;
  fs.writeFileSync(file, String(value));
  return value;
};
if (name === 'rsync') {
  const plain = args.filter(arg => !arg.startsWith('-'));
  const target = plain.at(-1);
  const host = target.slice(0, target.indexOf(':'));
  const dir = target.slice(target.indexOf(':') + 1);
  const files = plain.slice(0, -1).map(file => path.basename(file));
  log({host, files});
  const rule = (config.rsync || {})[host] || {};
  const attempt = count('rsync-' + host + '-' + files.join(','));
  if (rule.fail) process.exit(23);
  if (attempt <= (rule.hangs || 0)) setInterval(() => {}, 1000);
  else {
    for (const file of plain.slice(0, -1)) {
      fs.copyFileSync(file, path.join(dir, path.basename(file)));
      fs.chmodSync(path.join(dir, path.basename(file)), 0o644);
    }
  }
} else if (name === 'ssh') {
  const host = args.at(-2);
  log({host});
  if ((config.ssh || {}).fail) process.exit(255);
  const result = spawnSync('sh', ['-s'], {stdio: 'inherit'});
  process.exit(result.status ?? 1);
} else if (name === 'curl') {
  const url = new URL(args.find(arg => arg.startsWith('https://')));
  const output = args[args.indexOf('-o') + 1];
  const file = path.basename(url.pathname);
  log({url: url.href, output});
  const source = path.join(config.primary, file);
  if (!fs.existsSync(source)) process.exit(22);
  if ((config.curl || {}).corrupt === file) fs.writeFileSync(output, 'truncated');
  else fs.copyFileSync(source, output);
} else if (name === 'sha256sum') {
  const file = args[0];
  process.stdout.write(crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex') + '  ' + file + '\\n');
}
`;

async function fixture(config = {}) {
  const root = await mkdtemp(join(tmpdir(), 'hop-upload-test-'));
  const local = join(root, 'local');
  const primary = join(root, 'primary');
  const mirror = join(root, 'mirror');
  const bin = join(root, 'bin');
  for (const dir of [local, primary, mirror, bin]) await mkdir(dir);
  for (const file of builds) await writeFile(join(local, file), `new ${file}\n`);
  await writeFile(join(local, 'latest.json'), '{"version":"2.6.0"}\n');
  for (const dir of [primary, mirror]) {
    await writeFile(join(dir, 'Hop.dmg'), 'old Hop.dmg\n');
    await writeFile(join(dir, 'latest.json'), '{"version":"2.5.9"}\n');
  }
  await writeFile(join(root, 'config.json'), JSON.stringify({primary, ...config}));
  for (const name of ['rsync', 'ssh', 'curl', 'sha256sum']) {
    await writeFile(join(bin, name), tool);
    await chmod(join(bin, name), 0o755);
  }
  return { root, local, primary, mirror, bin };
}

async function upload(f, env = {}) {
  try {
    const result = await execute('/bin/zsh', [script, join(f.local, 'latest.json'), ...builds.map(file => join(f.local, file))], {
      env: {
        PATH: `${f.bin}:/usr/bin:/bin`,
        HOME: f.root,
        TMPDIR: f.root,
        HOP_UPLOAD_FIXTURE_ROOT: f.root,
        HOP_UPLOAD_PRIMARY: `primary:${f.primary}`,
        HOP_UPLOAD_PRIMARY_URL: 'https://hop.tools/downloads/hop',
        HOP_UPLOAD_MIRRORS: `mirror:${f.mirror}`,
        HOP_UPLOAD_ATTEMPT_SECONDS: '3',
        ...env,
      },
      timeout: 60000,
    });
    return { code: 0, output: result.stdout + result.stderr };
  } catch (error) {
    if (error.code === undefined || typeof error.code !== 'number') throw error;
    return { code: error.code, output: error.stdout + error.stderr };
  }
}

async function commands(f) {
  return (await readFile(join(f.root, 'commands.jsonl'), 'utf8')).trim().split('\n').map(line => JSON.parse(line));
}

async function assertReleased(dir) {
  for (const file of builds) {
    assert.equal(await readFile(join(dir, file), 'utf8'), `new ${file}\n`, file);
    assert.equal((await stat(join(dir, file))).mode & 0o777, 0o644, file);
  }
  assert.equal(await readFile(join(dir, 'latest.json'), 'utf8'), '{"version":"2.6.0"}\n');
  assert.deepEqual((await readdir(dir)).filter(file => file.startsWith('.')), []);
}

test('the mirror fetches the builds from the primary, then every host gets the manifest', async () => {
  const f = await fixture();
  try {
    const result = await upload(f);
    assert.equal(result.code, 0, result.output);
    await assertReleased(f.primary);
    await assertReleased(f.mirror);
    const log = await commands(f);
    const pushes = log.filter(entry => entry.tool === 'rsync');
    assert.deepEqual(pushes.map(entry => [entry.host, entry.files]), [
      ['primary', builds],
      ['primary', ['latest.json']],
      ['mirror', ['latest.json']],
    ]);
    const fetches = log.filter(entry => entry.tool === 'curl');
    assert.equal(fetches.length, builds.length);
    for (const entry of fetches) assert.match(entry.url, /^https:\/\/hop\.tools\/downloads\/hop\/[^?]+\?sha256=[0-9a-f]{64}$/);
    assert.ok(log.findIndex(entry => entry.tool === 'ssh') < log.findIndex(entry => entry.files?.[0] === 'latest.json'));
  } finally {
    await rm(f.root, { recursive: true, force: true });
  }
});

test('a build that fails its hash on the mirror is never renamed into place, and the Mac pushes instead', async () => {
  const f = await fixture({ curl: { corrupt: 'Hop.dmg' } });
  try {
    const result = await upload(f);
    assert.equal(result.code, 0, result.output);
    assert.match(result.output, /hash mismatch: Hop\.dmg/);
    assert.match(result.output, /could not fetch the builds, pushing them from this Mac/);
    await assertReleased(f.mirror);
    const mirrorPushes = (await commands(f)).filter(entry => entry.tool === 'rsync' && entry.host === 'mirror');
    assert.deepEqual(mirrorPushes.map(entry => entry.files), [builds, ['latest.json']]);
  } finally {
    await rm(f.root, { recursive: true, force: true });
  }
});

test('a stalled push is killed at its deadline and a fresh attempt finishes the upload', async () => {
  const f = await fixture({ ssh: { fail: true }, rsync: { mirror: { hangs: 1 } } });
  try {
    const started = Date.now();
    const result = await upload(f);
    assert.equal(result.code, 0, result.output);
    assert.match(result.output, /attempt 1 of 3 did not finish/);
    assert.ok(Date.now() - started < 30000);
    await assertReleased(f.mirror);
  } finally {
    await rm(f.root, { recursive: true, force: true });
  }
});

test('when no route reaches the mirror the release stops before any manifest changes', async () => {
  const f = await fixture({ curl: { corrupt: 'Hop.dmg' }, rsync: { mirror: { fail: true } } });
  try {
    const result = await upload(f, { HOP_UPLOAD_ATTEMPTS: '2' });
    assert.notEqual(result.code, 0);
    assert.match(result.output, /upload of the builds to mirror:.* failed/);
    for (const dir of [f.primary, f.mirror]) {
      assert.equal(await readFile(join(dir, 'latest.json'), 'utf8'), '{"version":"2.5.9"}\n');
    }
    assert.equal(await readFile(join(f.mirror, 'Hop.dmg'), 'utf8'), 'old Hop.dmg\n');
    assert.deepEqual((await readdir(f.mirror)).sort(), ['Hop.dmg', 'latest.json']);
  } finally {
    await rm(f.root, { recursive: true, force: true });
  }
});

test('a failed push to the primary stops the release before the mirror is touched', async () => {
  const f = await fixture({ rsync: { primary: { fail: true } } });
  try {
    const result = await upload(f, { HOP_UPLOAD_ATTEMPTS: '1' });
    assert.notEqual(result.code, 0);
    assert.match(result.output, /upload of the builds to primary:.* failed/);
    assert.equal((await commands(f)).some(entry => entry.host === 'mirror'), false);
    assert.equal(await readFile(join(f.mirror, 'latest.json'), 'utf8'), '{"version":"2.5.9"}\n');
  } finally {
    await rm(f.root, { recursive: true, force: true });
  }
});

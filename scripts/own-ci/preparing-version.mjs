import { createHash } from 'node:crypto';
import { constants } from 'node:fs';
import { open, readFile, realpath } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { captureSource, verifyGate } from './engine.mjs';
import { parsePreparingVersion } from './hop-report.mjs';

// Release packaging consumes the version checked inside the isolated build.
// It must not execute a stale debug binary from the real checkout.
if (process.argv.length !== 2 || Number(process.versions.node.split('.')[0]) !== 22) throw new Error('Usage: node scripts/own-ci/preparing-version.mjs (Node22)');
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const root = await realpath(join(dirname(fileURLToPath(import.meta.url)), '../..'));
const state = join(await realpath(tmpdir()), 'own-checks-' + process.getuid() + '-' + digest(root).slice(0, 20));
const plan = JSON.parse(await readFile(join(root, 'scripts/own-ci/plan.json'), 'utf8'));
const proof = await verifyGate({ root, state, plan });
const pointer = JSON.parse(await boundedOwnedFile(join(state, 'latest.json')));
if (!/^run-[a-zA-Z0-9]+$/.test(pointer.run)) throw new Error('Invalid proof pointer');
const artifact = proof.artifacts.find(item => item.path === 'hop-preparing-version.json');
if (!artifact || !/^artifacts\/\d+\.dat$/.test(artifact.stored)) throw new Error('Missing verified preparing version');
const file = join(state, pointer.run, artifact.stored);
if (await realpath(file) !== file) throw new Error('Linked preparing-version artifact');
const bytes = await boundedOwnedFile(file);
if (digest(bytes) !== artifact.hash) throw new Error('Preparing-version artifact changed');
if (JSON.stringify(await captureSource(root)) !== JSON.stringify(proof.source)) throw new Error('Source changed after version verification');
console.log(parsePreparingVersion(JSON.parse(bytes).version));


async function boundedOwnedFile(path) {
  if (await realpath(path) !== path) throw new Error('Linked proof file');
  const handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const before = await handle.stat();
    if (!before.isFile() || before.uid !== process.getuid() || before.size < 1 || before.size > 512) throw new Error('Invalid proof file');
    const buffer = Buffer.alloc(513);
    const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0);
    const after = await handle.stat();
    if (bytesRead !== before.size || after.size !== before.size || after.mtimeMs !== before.mtimeMs || after.ctimeMs !== before.ctimeMs || await realpath(path) !== path) throw new Error('Proof file changed');
    return buffer.subarray(0, bytesRead);
  } finally {
    await handle.close();
  }
}

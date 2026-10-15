import { constants } from 'node:fs';
import { createHash } from 'node:crypto';
import { lstat, open, readFile, readdir, readlink, realpath } from 'node:fs/promises';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';

const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const inside = (root, path) => path === root || path.startsWith(root + sep);
const text = bytes => {
  const value = bytes.toString('utf8');
  if (!Buffer.from(value).equals(bytes)) throw new Error('SDK paths must be valid UTF-8');
  return value;
};

async function internalLink(root, link) {
  let cursor = root, count = 0;
  const pending = relative(root, link).split(sep);
  while (pending.length) {
    const part = pending.shift();
    if (!part || part === '.') continue;
    if (part === '..') {
      if (cursor === root) throw new Error('SDK link leaves the root');
      cursor = dirname(cursor);
      continue;
    }
    const candidate = join(cursor, part);
    let entry;
    try { entry = await lstat(candidate); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    if (entry?.isSymbolicLink()) {
      if (++count > 40) throw new Error('SDK link is cyclic or too deep');
      const target = text(await readlink(candidate, { encoding: 'buffer' }));
      if (isAbsolute(target)) throw new Error('Absolute SDK links are not portable');
      pending.unshift(...target.split(sep));
    } else cursor = candidate;
    if (!inside(root, cursor)) throw new Error('SDK link leaves the root');
  }
}

async function fileHash(path, expected) {
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const before = await file.stat();
    if (!before.isFile() || before.ino !== expected.ino || before.dev !== expected.dev) throw new Error('SDK file changed before hashing');
    const digest = createHash('sha256'), buffer = Buffer.alloc(1024 * 1024);
    let total = 0;
    while (true) {
      const { bytesRead } = await file.read(buffer, 0, buffer.length, null);
      if (!bytesRead) break;
      digest.update(buffer.subarray(0, bytesRead)); total += bytesRead;
    }
    const after = await file.stat(), current = await lstat(path);
    if (total !== before.size || after.size !== before.size || after.mtimeMs !== before.mtimeMs || current.ino !== before.ino || current.dev !== before.dev || (current.mode & 0o111) !== (expected.mode & 0o111)) throw new Error('SDK file changed while hashing');
    return digest.digest('hex');
  } finally { await file.close(); }
}

export async function hashCodeqlTree(root) {
  if (typeof root !== 'string' || !isAbsolute(root) || resolve(root) !== root || await realpath(root) !== root || !(await lstat(root)).isDirectory()) throw new Error('SDK root must be a canonical directory');
  const records = [], links = [];
  async function visit(path) {
    const metadata = await lstat(path), name = relative(root, path).split(sep).join('/') || '.';
    if (metadata.isSymbolicLink()) {
      records.push([name, 'l', 0, text(await readlink(path, { encoding: 'buffer' }))]); links.push(path);
    } else if (metadata.isDirectory()) {
      records.push([name, 'd', metadata.mode & 0o111, '']);
      for (const child of await readdir(path, { encoding: 'buffer' })) await visit(join(path, text(child)));
    } else if (metadata.isFile()) records.push([name, 'f', metadata.mode & 0o111, await fileHash(path, metadata)]);
    else throw new Error('SDK contains a non-file entry');
  }
  await visit(root);
  for (const link of links) await internalLink(root, link);
  records.sort((a, b) => Buffer.compare(Buffer.from(a[0]), Buffer.from(b[0])));
  return { sha256: sha('codeql-sdk-tree-v1\n' + records.map(record => JSON.stringify(record) + '\n').join('')), entries: records.length };
}

export async function verifyCodeqlTree(root) {
  const manifest = JSON.parse(await readFile(new URL('./codeql-sdk.json', import.meta.url), 'utf8'));
  if (!/^[a-f0-9]{64}$/.test(manifest.sdkTreeSha256)) throw new Error('Missing reviewed CodeQL SDK tree pin');
  const actual = await hashCodeqlTree(root);
  if (actual.sha256 !== manifest.sdkTreeSha256) throw new Error('CodeQL SDK tree authentication failed');
  return actual;
}

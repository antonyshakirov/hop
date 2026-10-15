import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmod, copyFile, mkdir, mkdtemp, readFile, realpath, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import test from 'node:test';
const api = await import('./codeql-sdk-tree.mjs').catch(error => { if (error.code === 'ERR_MODULE_NOT_FOUND') return {}; throw error; });
const ready = () => assert.equal(typeof api.hashCodeqlTree, 'function', 'SDK tree hashing is not implemented');
async function fixture(t) {
 const base = await realpath(await mkdtemp(join(tmpdir(), 'codeql-tree-'))); t.after(() => rm(base, { recursive: true, force: true }));
 const root = join(base, 'sdk'); await mkdir(root, { mode: 0o755 }); await mkdir(join(root, 'bin'), { mode: 0o755 });
 await writeFile(join(root, 'bin', 'tool'), 'verified public bytes\n', { mode: 0o755 }); await writeFile(join(root, 'data'), 'data\n', { mode: 0o644 }); await symlink('bin/tool', join(root, 'alias'));
 return { base, root };
}
test('hash is deterministic and ignores launcher write-bit changes only', async t => {
 ready(); const { root } = await fixture(t); const before = await api.hashCodeqlTree(root); await chmod(join(root, 'bin', 'tool'), 0o555); await chmod(join(root, 'data'), 0o444); assert.deepEqual(await api.hashCodeqlTree(root), before); assert.equal(before.entries, 5);
});
for (const [name, mutate] of [
 ['content', root => writeFile(join(root, 'data'), 'corrupted')],
 ['missing file', root => rm(join(root, 'data'))],
 ['extra file', root => writeFile(join(root, 'extra'), 'new')],
 ['executable bits', root => chmod(join(root, 'data'), 0o755)],
 ['internal link target', async root => { await rm(join(root, 'alias')); await symlink('data', join(root, 'alias')); }],
]) test('hash detects ' + name, async t => { ready(); const { root } = await fixture(t); const before = await api.hashCodeqlTree(root); await mutate(root); assert.notEqual((await api.hashCodeqlTree(root)).sha256, before.sha256); });
for (const [name, target] of [['external relative link','../outside'],['absolute link','/usr/bin/true'],['leave-and-reenter link','../sdk/data'],['cyclic link','alias']]) test('rejects ' + name, async t => { ready();const { root } = await fixture(t);await rm(join(root,'alias'));await symlink(target,join(root,'alias'));await assert.rejects(api.hashCodeqlTree(root)); });
test('allows dangling links only when their complete traversal stays inside', async t => { ready();const { root }=await fixture(t);await symlink('missing/../data',join(root,'dangling'));assert.equal((await api.hashCodeqlTree(root)).entries,6); });
test('Python and Node encode identical tree records including non-ASCII paths', async t => {
 ready(); const { root } = await fixture(t);await writeFile(join(root,'😀'), 'astral');await writeFile(join(root,'\ue000'), 'private-use');
 const script = new URL('./codeql-setup.py',import.meta.url).pathname; const program = 'import importlib.util,json,sys; s=importlib.util.spec_from_file_location("setup",sys.argv[1]); m=importlib.util.module_from_spec(s);s.loader.exec_module(m);print(json.dumps(m.hash_tree(sys.argv[2])))';
 const result=spawnSync('python3',['-c',program,script,root],{encoding:'utf8'});assert.equal(result.status,0,result.stderr);assert.deepEqual(JSON.parse(result.stdout),await api.hashCodeqlTree(root));
});
test('fixed-source verifier rejects a well-formed synthetic substitute SDK', async t => { ready();assert.equal(typeof api.verifyCodeqlTree,'function');const {root}=await fixture(t);await assert.rejects(api.verifyCodeqlTree(root)); });
test('verifier accepts its exact colocated pin and rejects every changed tree', async t => {
 ready();
 for (const mutate of [null, root => writeFile(join(root, 'data'), 'changed'), root => rm(join(root, 'data')), root => writeFile(join(root, 'extra'), 'extra'), root => chmod(join(root, 'data'), 0o755), async root => { await rm(join(root, 'alias')); await symlink('../outside', join(root, 'alias')); }]) {
  const { base, root } = await fixture(t), expected = await api.hashCodeqlTree(root);
  const source = join(base, 'codeql-sdk-tree.mjs');
  await copyFile(new URL('./codeql-sdk-tree.mjs', import.meta.url), source);
  await writeFile(join(base, 'codeql-sdk.json'), JSON.stringify({ sdkTreeSha256: expected.sha256 }));
  const verifier = await import(pathToFileURL(source));
  assert.deepEqual(await verifier.verifyCodeqlTree(root), expected);
  if (mutate) { await mutate(root); await assert.rejects(verifier.verifyCodeqlTree(root)); }
 }
});

import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { checkScripts, shellsFor } from './script-syntax.mjs';

const fixture = async files => {
  const root = await mkdtemp(join(tmpdir(), 'script-syntax-'));
  await mkdir(join(root, 'scripts'));
  for (const [name, text] of Object.entries(files)) await writeFile(join(root, 'scripts', name), text);
  return root;
};
const plist = '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict/></plist>\n';

test('the checked-in packaging scripts and plists parse', () => {
  assert.ok(checkScripts() > 10);
});
test('valid scripts and plists pass', async t => {
  const root = await fixture({ 'a.sh': '#!/bin/zsh\necho ok\n', 'b.sh': '#!/usr/bin/env bash\n[[ -n x ]] && echo ok\n', 'c.plist': plist, 'd.entitlements': plist, 'f.py': 'print(1)\n' });
  t.after(() => rm(root, { recursive: true, force: true }));
  assert.equal(checkScripts(root), 5);
});
test('a shell syntax error, a broken plist, a Python syntax error and an unknown shell fail', async t => {
  for (const files of [{ 'a.sh': '#!/bin/zsh\nif true; then\n' }, { 'c.plist': '<plist><dict>' }, { 'g.py': 'def broken(:\n' }, { 'e.sh': '#!/usr/bin/fish\necho\n' }]) {
    const root = await fixture(files);
    t.after(() => rm(root, { recursive: true, force: true }));
    assert.throws(() => checkScripts(root), JSON.stringify(files));
  }
});
test('the sourced build scratch helper parses in zsh and bash', () => {
  assert.deepEqual(shellsFor('build-scratch.sh', '# no shebang'), ['/bin/zsh', '/bin/bash']);
});

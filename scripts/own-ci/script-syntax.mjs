// Parses every shell and Python script in scripts/ with the interpreter that runs
// it and lints every plist and entitlements file, so a typo fails here, not in release.sh.
import { execFileSync } from 'node:child_process';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const directory = 'scripts';
const shells = { '#!/bin/zsh': ['/bin/zsh'], '#!/bin/bash': ['/bin/bash'], '#!/usr/bin/env bash': ['/bin/bash'], '#!/bin/sh': ['/bin/sh'] };
// Sourced by both a zsh and a bash entry point, so it must parse in both.
const sourced = { 'build-scratch.sh': ['/bin/zsh', '/bin/bash'] };

export function shellsFor(name, text) {
  if (sourced[name]) return sourced[name];
  const first = text.split('\n', 1)[0].trim();
  if (!shells[first]) throw new Error('Unknown shell for ' + name + ': ' + first);
  return shells[first];
}

export function checkScripts(root = process.cwd()) {
  const names = readdirSync(join(root, directory)).sort();
  let checked = 0;
  for (const name of names) {
    const path = join(root, directory, name);
    if (name.endsWith('.sh')) {
      for (const shell of shellsFor(name, readFileSync(path, 'utf8'))) execFileSync(shell, ['-n', path], { stdio: 'inherit' });
      checked++;
    } else if (name.endsWith('.py')) {
      execFileSync('/usr/bin/python3', ['-B', '-I', '-c', 'import ast, sys; ast.parse(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1])', path], { stdio: 'inherit' });
      checked++;
    } else if (name.endsWith('.plist') || name.endsWith('.entitlements')) {
      execFileSync('/usr/bin/plutil', ['-lint', '-s', path], { stdio: 'inherit' });
      checked++;
    }
  }
  if (!checked) throw new Error('No packaging scripts found');
  return checked;
}

if (process.argv[1]?.endsWith('script-syntax.mjs')) console.log('Packaging files parsed: ' + checkScripts());

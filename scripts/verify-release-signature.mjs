import { createPublicKey, verify } from 'node:crypto';
import { readFile } from 'node:fs/promises';

try {
  if (process.argv.length !== 4) throw new Error('Usage: node verify-release-signature.mjs <archive> <signature>');
  const source = await readFile(new URL('../Sources/Hop/UpdateChecker.swift', import.meta.url), 'utf8');
  const definitions = source.match(/^.*\b(?:let|var)\s+updatePublicKeyBase64\b.*$/gm) ?? [];
  const definition = definitions.length === 1
    ? definitions[0].match(/^\s*static let updatePublicKeyBase64 = "([^"]+)"\s*;?\s*$/) : null;
  if (!definition) throw new Error('Expected one canonical update public key in UpdateChecker.swift');
  const raw = Buffer.from(definition[1], 'base64');
  if (raw.length !== 32 || raw.toString('base64') !== definition[1]) throw new Error('Invalid canonical update public key');
  const key = createPublicKey({ format: 'der', type: 'spki',
    key: Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), raw]) });
  const [archive, signature] = await Promise.all(process.argv.slice(2).map(path => readFile(path)));
  if (signature.length !== 64 || !verify(null, archive, key, signature)) throw new Error('Invalid Ed25519 archive signature');
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}

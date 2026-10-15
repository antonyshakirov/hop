import { readdir } from 'node:fs/promises';
import { join, relative, sep } from 'node:path';

export async function expectedSwiftSources(workspace) {
  const files = [];
  async function visit(directory) {
    for (const item of await readdir(directory, { withFileTypes: true })) {
      const path = join(directory, item.name);
      if (item.isSymbolicLink()) throw new Error('Swift sources must not be symlinks');
      if (item.isDirectory()) await visit(path);
      else if (item.isFile() && item.name.endsWith('.swift')) files.push(relative(workspace, path).split(sep).join('/'));
    }
  }
  await visit(join(workspace, 'Sources'));
  if (!files.length) throw new Error('No application Swift sources discovered');
  return files.sort();
}

export function validateExtractionCoverage(report, expected, workspace) {
  if (!Array.isArray(expected) || !expected.length || new Set(expected).size !== expected.length) throw new Error('Invalid expected Swift source inventory');
  const extracted = new Set();
  for (const run of report.runs ?? []) {
    for (const invocation of run.invocations ?? []) {
      for (const item of invocation.toolExecutionNotifications ?? []) {
        const id = item.descriptor?.id ?? run.tool?.driver?.notifications?.[item.descriptor?.index]?.id;
        if (id !== 'swift/diagnostics/successfully-extracted-files') continue;
        for (const location of item.locations ?? []) {
          let uri = location.physicalLocation?.artifactLocation?.uri;
          if (typeof uri !== 'string') continue;
          uri = decodeURIComponent(uri);
          if (uri.startsWith('file://')) uri = new URL(uri).pathname;
          if (uri.startsWith(workspace + '/')) uri = uri.slice(workspace.length + 1);
          extracted.add(uri);
        }
      }
    }
  }
  const missing = expected.filter(path => !extracted.has(path));
  if (missing.length) throw new Error('CodeQL did not extract application sources: ' + missing.join(', '));
  return { expected: expected.length, extracted: expected.length, files: expected };
}

export function validateExtractorExecution(tracer, logs) {
  const exits = [...tracer.matchAll(/Extractor [^\r\n]+ terminated with exit code (\d+)\./g)];
  if (!exits.length || exits.some(match => match[1] !== '0') || /Extractor [^\r\n]+ (?:terminated|killed) (?:by|with) signal/.test(tracer)) throw new Error('CodeQL extractor invocations did not all succeed');
  if (!Array.isArray(logs) || !logs.length || logs.some(log => /\b(?:ERRO|FATAL)\s+\[/.test(log))) throw new Error('CodeQL extractor reported a compiler or translation error');
  return { invocations: exits.length, logs: logs.length };
}

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtemp, mkdir, readFile, realpath, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
const sdk = JSON.parse(await readFile(new URL('./codeql-sdk.json', import.meta.url)));
const required = sdk.queries.filter(q => ['problem', 'path-problem'].includes(q.kind)).map(q => q.id);
import { runCodeql, validateCodeqlSarif as validate } from './codeql.mjs';
const clean = () => ({ version: '2.1.0', runs: [{ tool: { driver: { name: 'CodeQL', semanticVersion: sdk.version, rules: required.map(id => ({ id, defaultConfiguration: { level: 'warning' } })) } }, invocations: [{ executionSuccessful: true }], results: [] }] });
const mutate = action => { const report = clean(); action(report.runs[0], report); return report; };

test('accepts the complete default Swift rule inventory with successful invocation', () => {
 const summary = validate(clean()); assert.equal(summary.rules, required.length); assert.equal(summary.results, 0);
});
for (const [name, action] of [
 ['missing runs', (run, report) => { report.runs = []; }],
 ['wrong tool', run => { run.tool.driver.name = 'Another scanner'; }],
 ['wrong CLI version', run => { run.tool.driver.semanticVersion = '2.27.1'; }],
 ['missing rule inventory', run => { run.tool.driver.rules.pop(); }],
 ['duplicate rules', run => { run.tool.driver.rules.push(run.tool.driver.rules[0]); }],
 ['missing invocation', run => { run.invocations = []; }],
 ['failed invocation', run => { run.invocations[0].executionSuccessful = false; }],
 ['missing results', run => { delete run.results; }],
 ['error-level result', run => { run.results.push({ ruleId: required[0], level: 'error', message: { text: 'Unsafe operation' } }); }],
 ['inherited error-level result', run => { run.tool.driver.rules[0].defaultConfiguration.level = 'error'; run.results.push({ ruleId: required[0], message: { text: 'Unsafe operation' } }); }],
 ['suppressed error result', run => { run.results.push({ ruleId: required[0], level: 'error', suppressions: [{ kind: 'inSource' }], message: { text: 'Unsafe operation' } }); }],
 ['unknown result rule', run => { run.results.push({ ruleId: 'swift/not-scanned', level: 'warning', message: { text: 'Unknown rule' } }); }],
 ['mismatched result rule index', run => { run.results.push({ ruleId: required[0], ruleIndex: 1, level: 'warning', message: { text: 'Wrong index' } }); }],
 ['fatal execution notification', run => { run.invocations[0].toolExecutionNotifications = [{ level: 'error', message: { text: 'Fatal extraction failure' } }]; }],
 ['fatal configuration notification', run => { run.invocations[0].toolConfigurationNotifications = [{ level: 'error', message: { text: 'Invalid configuration' } }]; }],
 ['fatal notification property', run => { run.invocations[0].toolExecutionNotifications = [{ level: 'warning', properties: { severity: 'fatal' }, message: { text: 'Fatal failure' } }]; }],
 ['extraction error diagnostic', run => { run.invocations[0].toolExecutionNotifications = [{ descriptor: { id: 'swift/diagnostics/extraction-errors' }, level: 'warning', message: { text: 'A file could not be extracted' } }]; }],
 ['malformed result level', run => { run.results.push({ ruleId: required[0], level: 'fatal', message: { text: 'Invalid level' } }); }],
 ['indexed fatal notification default', run => { run.tool.driver.notifications = [{ id: 'fatal', defaultConfiguration: { level: 'error' } }]; run.invocations[0].toolExecutionNotifications = [{ descriptor: { index: 0 }, message: { text: 'Fatal failure' } }]; }],
 ['extraction error result', run => { run.tool.driver.rules.push({ id: 'swift/diagnostics/extraction-errors' }); run.results.push({ ruleId: 'swift/diagnostics/extraction-errors', level: 'warning', message: { text: 'Partial extraction' } }); }],
]) test('rejects ' + name, () => assert.throws(() => validate(mutate(action))));

test('reads warnings and notes without treating them as error-level findings', () => {
 const report = mutate(run => { run.results = [{ ruleId: required[0], level: 'warning', message: { text: 'Review this warning' } }, { ruleIndex: 1, level: 'note', message: { text: 'Review this note' } }]; run.invocations[0].toolExecutionNotifications = [{ level: 'note', message: { text: 'Extraction completed' } }]; });
 const summary = validate(report); assert.equal(summary.results, 2); assert.equal(summary.warnings, 1); assert.equal(summary.notes, 1);
});
async function fixture(t, options = {}) {
 const run = await realpath(await mkdtemp(join(tmpdir(), 'hop-codeql-')));t.after(() => rm(run, { recursive: true, force: true }));
 const workspace = join(run, 'workspace'), root = join(run, 'sdk'), pack = join(root, 'qlpacks/codeql/swift-queries', sdk.queryPackVersion);
 await mkdir(workspace, { mode: 0o700 }); await mkdir(join(workspace, 'Sources')); await writeFile(join(workspace, 'Sources/Example.swift'), 'let example = 1'); await mkdir(pack, { recursive: true });
 for (const query of sdk.queries) { const p = join(pack, query.path); await mkdir(dirname(p), { recursive: true }); await writeFile(p, `/** @id ${query.id}\n * @kind ${query.kind}\n */\n`); }
 await writeFile(join(root, 'codeql'), 'synthetic metadata fixture');
 const complete = clean();
 complete.runs[0].invocations[0].toolExecutionNotifications = [{ descriptor: { id: 'swift/diagnostics/successfully-extracted-files' }, level: 'note', message: { text: 'File successfully extracted.' }, locations: [{ physicalLocation: { artifactLocation: { uri: 'Sources/Example.swift' } } }] }];
 const calls = [];
 const command = async (executable, args, environment) => {
  calls.push({ executable, args, environment });
  if (options.fail && args.includes(options.fail)) throw new Error('Synthetic command failure');
  if (args[0] === 'version') return { stdout: JSON.stringify({ version: options.version ?? sdk.version }), stderr: '' };
  if (args[0] === '--version') return { stdout: `Swift version ${sdk.extractorSwiftVersion} (swift-${sdk.extractorSwiftVersion}-RELEASE)\nTarget: x86_64-apple-macosx28.0\n`, stderr: '' };
  if (args[0] === 'resolve') return { stdout: JSON.stringify((options.queries ?? sdk.queries).map(q => join(pack, q.path))), stderr: '' };
  if (args[0] === 'database' && args[1] === 'init') {
   await mkdir(join(args[2], 'temp/tracingEnvironment'), { recursive: true });
   await writeFile(join(args[2], 'temp/tracingEnvironment/start-tracing.json'), JSON.stringify(options.tracing ?? { DYLD_INSERT_LIBRARIES: join(root, 'libtrace.dylib'), CODEQL_DIST: root }));
   return { stdout: 'Created a database', stderr: '' };
  }
  if (executable === join(run, 'bin', 'swift') && args[0] === 'build') {
   const log = join(run, 'codeql-database/log');
   await mkdir(join(log, 'swift/extractor'), { recursive: true });
   await writeFile(join(log, 'build-tracer.log'), 'Extractor /private/sdk/extractor terminated with exit code 0.');
   await writeFile(join(log, 'swift/extractor/1.log'), 'INFO [extractor/main] completed');
   return { stdout: 'Built all Swift targets', stderr: '' };
  }
  if (args[0] === 'database' && args[1] === 'finalize') return { stdout: 'Finalized extracted sources', stderr: '' };
  if (args[0] === 'database' && args[1] === 'analyze') { const output = args.find(a => a.startsWith('--output=')).slice('--output='.length); if (options.symlinkReport) await symlink(join(run, 'missing'), output); else if (!options.omitReport) await writeFile(output, JSON.stringify(options.report ?? complete)); return { stdout: 'Analysis complete', stderr: '' }; }
  throw new Error('Unexpected fixture command');
 };
 return { run, workspace, codeql: join(root, 'codeql'), command, calls };
}
async function execute(f, extra) { return runCodeql({ ...f, ...extra }); }
test('creates a fresh real-build plan, then analyzes and validates output through the callback', async t => {
 const f = await fixture(t); const summary = await execute(f);
 const create = f.calls.find(c => c.args[0] === 'database' && c.args[1] === 'init'); const analyze = f.calls.find(c => c.args[1] === 'analyze');
 assert.ok(create && analyze); assert.ok(create.args.includes('--begin-tracing'));
 const build = f.calls.find(c => c.executable === join(f.run, 'bin', 'swift'));
 assert.ok(build.args.includes('build') && build.args.includes(join(f.run, 'codeql-build')));
 assert.equal(build.environment.SEMMLE_COPY_EXECUTABLES_ROOT, join(f.run, 'c'));
 assert.ok(build.environment.DYLD_INSERT_LIBRARIES.endsWith('libtrace.dylib'));
 assert.ok(f.calls.find(c => c.args[1] === 'finalize').args.includes('--no-skip-empty'));
 assert.ok(analyze.args.includes('--no-download')); assert.ok(analyze.args.includes('--no-sarif-group-rules-by-pack')); assert.equal(summary.queries, sdk.queries.length);
 assert.deepEqual(JSON.parse(await readFile(join(f.workspace, 'hop-codeql-summary.json'))), summary);
});
for (const [name, options] of [ ['wrong version', { version: '2.27.1' }], ['incomplete discovery', { queries: sdk.queries.slice(1) }], ['command failure', { fail: 'init' }], ['missing report', { omitReport: true }], ['linked report', { symlinkReport: true }], ['unsafe report', { report: mutate(run => { run.invocations[0].executionSuccessful = false; }) }] ]) test('execution rejects ' + name, async t => { const f = await fixture(t, options); await assert.rejects(execute(f)); await assert.rejects(readFile(join(f.workspace, 'hop-codeql-summary.json'))); });
test('refuses a stale SARIF before any command', async t => { const f = await fixture(t);await writeFile(join(f.workspace, 'hop-codeql.sarif'), JSON.stringify(clean()));await assert.rejects(execute(f));assert.equal(f.calls.length, 0); });
test('refuses a no-build Swift argument before any command', async t => { const f = await fixture(t);await assert.rejects(execute(f, { swiftBuildArgs: ['build', '--show-bin-path'] }));assert.equal(f.calls.length, 0); });

test('refuses a partial target build before any command', async t => { const f = await fixture(t);await assert.rejects(execute(f, { swiftBuildArgs: ['build', '--target', 'HopCore'] }));assert.equal(f.calls.length, 0); });


test('refuses a tracing environment that overrides HOME', async t => {
 const f = await fixture(t, { tracing: { HOME: '/outside' } });
 await assert.rejects(execute(f), /tracing environment/);
 assert.ok(!f.calls.some(c => c.args[0] === 'build'));
});


const baselineMetadata = () => ({ descriptor: { id: 'swift/baseline/expected-extracted-files' }, level: 'none', message: { text: '' }, locations: [{ physicalLocation: { artifactLocation: { uri: 'Sources/Example.swift' } } }] });
const telemetryMetadata = (id, attributes) => ({ descriptor: { id }, level: 'none', message: { text: '' }, properties: { attributes, visibility: { telemetry: true, statusPage: false } } });
function withMetadata(items) {
  return mutate(run => { run.invocations[0].toolExecutionNotifications = items; });
}
test('accepts official empty baseline and CLI telemetry records without hiding them', () => {
  const items = [baselineMetadata(), telemetryMetadata('cli/file-coverage-baseline', { durationMilliseconds: 12 }), telemetryMetadata('cli/platform', { arch: 'aarch64', name: 'Mac OS X', version: '27.0.1' }), telemetryMetadata('cli/sip-enablement', { isEnabled: true })];
  assert.equal(validate(withMetadata(items)).notifications, 4);
});
for (const [name, item] of [
  ['unknown blank notification', { descriptor: { id: 'cli/unreviewed' }, level: 'none', message: { text: '' } }],
  ['blank warning', { ...baselineMetadata(), level: 'warning' }],
  ['blank error', { ...baselineMetadata(), level: 'error' }],
  ['fatal property on metadata', { ...baselineMetadata(), properties: { severity: 'fatal' } }],
  ['blank extraction failure', { ...baselineMetadata(), descriptor: { id: 'swift/diagnostics/extraction-errors' } }],
  ['baseline missing locations', { ...baselineMetadata(), locations: [] }],
  ['telemetry missing visibility', { ...telemetryMetadata('cli/sip-enablement', { isEnabled: true }), properties: { attributes: { isEnabled: true } } }],
  ['telemetry missing attributes', telemetryMetadata('cli/platform', {})],
]) test('still rejects ' + name, () => assert.throws(() => validate(withMetadata([item]))));

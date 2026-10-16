import { expectedSwiftSources, validateExtractionCoverage, validateExtractorExecution } from './codeql-coverage.mjs';
import { readPrivateNativeFile } from './native.mjs';
import { lstat, mkdir, readFile, readdir, realpath, writeFile } from 'node:fs/promises';
import { basename, dirname, isAbsolute, join, relative, sep } from 'node:path';

const sdk = JSON.parse(await readFile(new URL('./codeql-sdk.json', import.meta.url), 'utf8'));
const requiredRules = sdk.queries.filter(query => ['problem', 'path-problem'].includes(query.kind)).map(query => query.id);
const levels = new Set(['none', 'note', 'warning', 'error']);
const inside = (parent, child) => child === parent || child.startsWith(parent + sep);
const messagePresent = item => typeof item?.message?.text === 'string' && item.message.text.trim() || typeof item?.message?.markdown === 'string' && item.message.markdown.trim();


// The official CLI emits these non-finding metadata records with empty text.
// Keep them in the report; errors and extraction diagnostics still fail below.
function emptyMetadata(item, id, level) {
  if (level !== 'none' || item?.message?.text !== '' || item.message.markdown) return false;
  if (id === 'swift/baseline/expected-extracted-files') {
    return Array.isArray(item.locations) && item.locations.length > 0 && item.locations.every(location => {
      const uri = location?.physicalLocation?.artifactLocation?.uri;
      return typeof uri === 'string' && uri.trim().length > 0;
    });
  }
  const attributes = item.properties?.attributes;
  if (item.properties?.visibility?.telemetry !== true || item.properties.visibility.statusPage !== false || !attributes || typeof attributes !== 'object' || Array.isArray(attributes)) return false;
  if (id === 'cli/file-coverage-baseline') return Number.isSafeInteger(attributes.durationMilliseconds) && attributes.durationMilliseconds >= 0;
  if (id === 'cli/platform') return ['arch', 'name', 'version'].every(key => typeof attributes[key] === 'string' && attributes[key].trim().length > 0);
  if (id === 'cli/sip-enablement') return typeof attributes.isEnabled === 'boolean';
  return false;
}

export function validateCodeqlSarif(report) {
  if (report?.version !== '2.1.0' || !Array.isArray(report.runs) || report.runs.length !== 1) throw new Error('Expected one complete Swift CodeQL SARIF run');
  const run = report.runs[0], driver = run?.tool?.driver;
  if (driver?.name !== 'CodeQL' || (driver.semanticVersion ?? driver.version) !== sdk.version || !Array.isArray(driver.rules) || !driver.rules.length || !Array.isArray(run.invocations) || !run.invocations.length || !Array.isArray(run.results)) throw new Error('Incomplete CodeQL analysis');
  if (run.tool.extensions?.some(extension => extension.rules?.length)) throw new Error('Expected ungrouped CodeQL rules');
  const rules = new Map();
  for (const rule of driver.rules) {
    if (typeof rule?.id !== 'string' || !rule.id.startsWith('swift/') || rules.has(rule.id)) throw new Error('Invalid CodeQL rule inventory');
    if (rule.defaultConfiguration?.level !== undefined && !levels.has(rule.defaultConfiguration.level)) throw new Error('Invalid CodeQL rule severity');
    rules.set(rule.id, rule);
  }
  if (requiredRules.some(id => !rules.has(id) || rules.get(id).defaultConfiguration?.enabled === false)) throw new Error('Default Swift rule inventory is incomplete');
  let notifications = 0;
  for (const invocation of run.invocations) {
    if (invocation.executionSuccessful !== true || invocation.exitCode !== undefined && invocation.exitCode !== 0) throw new Error('CodeQL invocation failed');
    for (const key of ['toolExecutionNotifications', 'toolConfigurationNotifications']) {
      const items = invocation[key] ?? [];
      if (!Array.isArray(items)) throw new Error('Malformed CodeQL notifications');
      for (const item of items) {
        const descriptors = driver.notifications ?? [];
        if (!Array.isArray(descriptors)) throw new Error('Malformed CodeQL notification descriptors');
        const reference = item?.descriptor;
        const indexed = reference?.index === undefined ? undefined : descriptors[reference.index];
        if (reference?.index !== undefined && (!Number.isInteger(reference.index) || reference.index < 0 || !indexed || reference.id !== undefined && reference.id !== indexed.id)) throw new Error('Invalid CodeQL notification descriptor index');
        const descriptor = indexed ?? descriptors.find(entry => entry.id === reference?.id);
        const level = item?.level ?? descriptor?.defaultConfiguration?.level ?? 'warning';
        if (!levels.has(level) || level === 'error' || item?.properties?.severity?.toLowerCase() === 'fatal' || (descriptor?.id ?? reference?.id) === 'swift/diagnostics/extraction-errors' || (!messagePresent(item) && !emptyMetadata(item, descriptor?.id ?? reference?.id, level))) throw new Error('CodeQL reported an extraction or analysis failure');
        notifications++;
      }
    }
  }
  let warnings = 0, notes = 0;
  for (const result of run.results) {
    const indexed = result?.ruleIndex === undefined ? undefined : driver.rules[result.ruleIndex];
    if (result?.ruleIndex !== undefined && (!Number.isInteger(result.ruleIndex) || result.ruleIndex < 0 || !indexed)) throw new Error('Invalid CodeQL result rule index');
    const rule = rules.get(result?.ruleId ?? indexed?.id);
    if (!rule || indexed && indexed.id !== rule.id || !messagePresent(result)) throw new Error('Invalid CodeQL result');
    const level = result.level ?? rule.defaultConfiguration?.level ?? 'warning';
    if (!levels.has(level) || level === 'error' || rule.id === 'swift/diagnostics/extraction-errors') throw new Error('CodeQL contains error-level findings or extraction errors');
    if (level === 'warning') warnings++;
    if (level === 'note') notes++;
  }
  return { runs: 1, rules: rules.size, results: run.results.length, warnings, notes, notifications };
}

async function absent(path) {
  try { await lstat(path); }
  catch (error) { if (error.code === 'ENOENT') return; throw error; }
  throw new Error('Refusing stale CodeQL output: ' + basename(path));
}

async function jsonFile(path) {
  const metadata = await lstat(path);
  if (!metadata.isFile() || metadata.isSymbolicLink() || metadata.size === 0 || metadata.size > 64 * 1024 * 1024) throw new Error('Missing or unsafe CodeQL JSON file');
  return JSON.parse(await readFile(path, 'utf8'));
}


// The callback runs commands from workspace inside the native boundary and throws on nonzero exit or signal.
export async function runCodeql({ run, workspace, codeql, command, swiftBuildArgs = ['build', '--disable-sandbox', '--build-system', 'native'] }) {
  if (typeof command !== 'function' || ![run, workspace, codeql].every(value => typeof value === 'string' && isAbsolute(value))) throw new Error('CodeQL requires explicit private paths and a sandboxed command callback');
  const actualRun = await realpath(run), actualWorkspace = await realpath(workspace), executable = await realpath(codeql);
  const metadata = await lstat(run);
  if (run !== actualRun || workspace !== actualWorkspace || workspace !== join(run, 'workspace') || !metadata.isDirectory() || metadata.isSymbolicLink() || metadata.uid !== process.getuid() || metadata.mode & 0o077 || /\s/.test(run)) throw new Error('CodeQL requires a private canonical run/workspace and a JVM-safe run path');
  if (!Array.isArray(swiftBuildArgs) || swiftBuildArgs[0] !== 'build' || swiftBuildArgs.some(arg => typeof arg !== 'string' || !arg || /[\x00-\x1f]/.test(arg) || /^(?:-h|--help|--version|--show-bin-path|--print-manifest-job-graph|--scratch-path|--build-path|--package-path|--target|--product)(?:=|$)/.test(arg))) throw new Error('CodeQL requires an actual Swift build with its own scratch path');
  const expectedSources = await expectedSwiftSources(workspace);
  const database = join(run, 'codeql-database'), scratch = join(run, 'codeql-build');
  const output = join(workspace, 'hop-codeql.sarif'), summaryPath = join(workspace, 'hop-codeql-summary.json');
  for (const path of [database, scratch, output, summaryPath]) await absent(path);
  const root = dirname(executable), pack = join(root, 'qlpacks/codeql/swift-queries', sdk.queryPackVersion);
  const extra = ['-J=-Djava.io.tmpdir=' + join(run, 'tmp'), '--common-caches=' + join(run, 'codeql-cache'), '--logdir=' + join(run, 'codeql-logs')];
  await mkdir(join(run, 'tmp'), { recursive: true, mode: 0o700 });
  const invoke = async (file, args, environment) => {
    const result = await command(file, args, environment);
    if (typeof result?.stdout !== 'string' || typeof result.stderr !== 'string' || result.code !== undefined && result.code !== 0 || result.signal) throw new Error('CodeQL command did not complete successfully');
    return result;
  };
  const version = JSON.parse((await invoke(executable, ['version', '--format=json', ...extra])).stdout);
  if (version.version !== sdk.version) throw new Error('Review the CodeQL version pin');
  const metadataRoot = join(run, 'extractor-metadata');
  const extractorEnvironment = {};
  for (const [key, name] of Object.entries({ LOG_DIR: 'log', SCRATCH_DIR: 'scratch', TRAP_DIR: 'trap', SOURCE_ARCHIVE_DIR: 'src', DIAGNOSTIC_DIR: 'diagnostic' })) {
    extractorEnvironment['CODEQL_EXTRACTOR_SWIFT_' + key] = join(metadataRoot, name);
    await mkdir(join(metadataRoot, name), { recursive: true, mode: 0o700 });
  }
  const extractor = await invoke(join(root, 'swift/tools/osx64/extractor'), ['--version'], extractorEnvironment);
  if (!new RegExp('^Swift version ' + sdk.extractorSwiftVersion.replaceAll('.', '\\.') + '(?: |$)', 'm').test(extractor.stdout)) throw new Error('Unexpected Swift CodeQL extractor version');
  const suite = sdk.queryPack + '@' + sdk.queryPackVersion + ':' + sdk.suite;
  const discovered = JSON.parse((await invoke(executable, ['resolve', 'queries', '--format=json', '--search-path=' + join(root, 'qlpacks'), suite, ...extra])).stdout);
  if (!Array.isArray(discovered) || discovered.length !== sdk.queries.length || new Set(discovered).size !== discovered.length) throw new Error('Incomplete Swift CodeQL query discovery');
  const inventory = [];
  for (const path of discovered) {
    if (typeof path !== 'string' || !isAbsolute(path) || !inside(pack, path) || await realpath(path) !== path || !(await lstat(path)).isFile()) throw new Error('Query discovery escaped the pinned Swift pack');
    const text = await readFile(path, 'utf8');
    inventory.push({ path: relative(pack, path).split(sep).join('/'), id: /@id\s+(\S+)/.exec(text)?.[1], kind: /@kind\s+(\S+)/.exec(text)?.[1] });
  }
  inventory.sort((a, b) => a.id?.localeCompare(b.id));
  const expected = [...sdk.queries].sort((a, b) => a.id.localeCompare(b.id));
  if (JSON.stringify(inventory) !== JSON.stringify(expected)) throw new Error('Swift default query inventory differs from the reviewed bundle');
  await invoke(executable, ['database', 'init', database, '--language=swift', '--source-root=' + workspace, '--begin-tracing', '--extra-tracing-config=' + join(workspace, 'scripts/own-ci/codeql-tracing.lua'), ...extra]);
  const tracing = await jsonFile(join(database, 'temp/tracingEnvironment/start-tracing.json'));
  if (!tracing || Array.isArray(tracing) || typeof tracing !== 'object' || !Object.entries(tracing).every(([key, value]) => /^(CODEQL_|SEMMLE_|DYLD_|LD_PRELOAD)/.test(key) && typeof value === 'string' && !/[\x00\r\n]/.test(value))) throw new Error('Invalid CodeQL tracing environment');
  const copyRoot = join(run, 'c');
  await mkdir(copyRoot, { mode: 0o700 });
  tracing.SEMMLE_COPY_EXECUTABLES_ROOT = copyRoot;
  await invoke(join(run, 'bin', 'swift'), [...swiftBuildArgs, '--sdk', '/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk', '--toolchain', run, '--package-path', workspace, '--scratch-path', scratch], tracing);
  const extractorLogs = join(database, 'log/swift/extractor');
  if (await realpath(extractorLogs) !== extractorLogs) throw new Error('Linked CodeQL extractor logs');
  const logNames = (await readdir(extractorLogs)).filter(name => name.endsWith('.log'));
  const execution = validateExtractorExecution((await readPrivateNativeFile(join(database, 'log/build-tracer.log'))).toString('utf8'), await Promise.all(logNames.map(async name => (await readPrivateNativeFile(join(extractorLogs, name))).toString('utf8'))));
  await invoke(executable, ['database', 'finalize', database, '--no-skip-empty', '--threads=2', '--ram=4096', ...extra]);
  await invoke(executable, ['database', 'analyze', database, suite, '--search-path=' + join(root, 'qlpacks'), '--format=sarifv2.1.0', '--output=' + output, '--no-download', '--no-sarif-group-rules-by-pack', '--sarif-include-diagnostics', '--sarif-category=/language:swift', '--threads=2', '--ram=4096', ...extra]);
  const sarif = await jsonFile(output);
  const coverage = validateExtractionCoverage(sarif, expectedSources, workspace);
  const summary = { execution, coverage, buildSdk: '/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk', version: sdk.version, extractor: extractor.stdout.trim(), suite, queries: inventory.length, queryInventory: inventory, ...validateCodeqlSarif(sarif) };
  await writeFile(summaryPath, JSON.stringify(summary) + '\n', { flag: 'wx', mode: 0o600 });
  return summary;
}

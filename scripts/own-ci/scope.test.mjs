import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { scopedPlan, selectScope, validateScope } from './scope.mjs';

const config = JSON.parse(readFileSync(new URL('./scope.json', import.meta.url), 'utf8'));
const plan = JSON.parse(readFileSync(new URL('./plan.json', import.meta.url), 'utf8'));
const plist = version => `<dict>\n<key>CFBundleShortVersionString</key>\n<string>${version}</string>\n<key>CFBundleVersion</key>\n<string>${version}</string>\n</dict>`;
const testFile = (path, body = `final class ${path.split('/').at(-1).replace('.swift', '')}: XCTestCase {}`) => [path, body];
const sources = new Map([
  ...config.baseline.map(path => testFile(path)),
  testFile('Tests/HopUITests/CoolingControllerTests.swift'),
  testFile('Tests/HopCoreTests/AwakeCountdownTests.swift'),
  testFile('Tests/HopUITests/SoundMixerPresetsTests.swift'),
  testFile('Tests/HopCoreTests/TimerEngineTests.swift', 'final class TimerEngineTests: XCTestCase {}\nfinal class TimeFormattingTests: XCTestCase {}'),
  testFile('Tests/HopUITests/ReleaseCopyLayoutTests.swift'),
  testFile('Tests/HopUITests/TestSupport.swift', 'extension XCTestCase {}'),
  testFile('Tests/HopUITests/SettingsModuleGroupsTests.swift'),
  testFile('Tests/HopHardwareTests/HardwareFanCurveTests.swift'),
  testFile('Tests/HopUITests/MenuOrderTests.swift', 'final class MenuOrderTests: MenuTestCase {}'),
  testFile('Tests/HopCoreTests/AgentCommandTests.swift'),
  testFile('Tests/HopCoreTests/ReleaseNewsTests.swift'),
  testFile('Tests/HopUITests/PanelDismissalTests.swift'),
  testFile('Tests/HopCoreTests/ModuleVisibilityTests.swift'),
  ['Sources/Hop/KeepAwakeController.swift', ''], ['Sources/Hop/Alerts.swift', ''], ['Sources/Hop/App.swift', ''], ['Sources/Hop/Theme.swift', ''],
]);
const select = (changed, { base = '2.5.6', head = '2.5.7', basePlist = plist(base), headPlist = plist(head), extra = [], diffs = {} } = {}) =>
  selectScope({ config, changed, files: [...sources.keys(), ...extra], read: path => sources.get(path) ?? '', diff: path => diffs[path], basePlist, headPlist });
const hunk = (lines, context = 'final class AppDelegate: NSObject') =>
  `diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -10,2 +10,2 @@ ${context}\n` + lines.join('\n');
const names = selection => selection.tests.map(path => path.split('/').at(-1));

test('the checked-in map and plan are valid', () => {
  validateScope(config);
  assert.equal(scopedPlan(plan, select([]), 'a'.repeat(40), config).steps.length, config.scopedSteps.length);
});
test('documentation alone runs only the launch, update and signing baseline', () => {
  const selection = select(['docs/spec.md', 'CHANGELOG.md', 'product-spec/awake.md']);
  assert.equal(selection.mode, 'scoped');
  assert.deepEqual(selection.tests, [...config.baseline].sort());
});
test('a feature file selects its group tests and nothing unrelated', () => {
  const selection = select(['Sources/Hop/KeepAwakeController.swift']);
  assert.equal(selection.mode, 'scoped');
  assert.ok(names(selection).includes('CoolingControllerTests.swift'));
  assert.ok(names(selection).includes('AwakeCountdownTests.swift'));
  assert.ok(!names(selection).includes('SoundMixerPresetsTests.swift'));
  assert.ok(!names(selection).includes('TimerEngineTests.swift'));
});
test('every class in a selected file runs', () => {
  const selection = select(['Sources/HopCore/TimeFormatting.swift']);
  assert.ok(selection.classes.includes('HopCoreTests.TimeFormattingTests'));
  assert.ok(selection.classes.includes('HopCoreTests.TimerEngineTests'));
});
test('shared, unmapped and untested files make the check full', () => {
  for (const changed of ['Sources/Hop/App.swift', 'Sources/HopCore/ModuleCatalog.swift', 'Package.swift', 'scripts/own-ci/plan.json', 'scripts/own-ci/hop-step.mjs', 'scripts/own-ci/codeql.mjs', 'scripts/build-remuxer.sh', 'engine/rqbit/x', 'Tests/HopCoreTests/Fixtures/a.json', 'Sources/Hop/Unknown.swift', 'notes/plan.txt', 'Sources/Hop/Sub/Thing.swift'])
    assert.equal(select([changed]).mode, 'full', changed);
});
test('a prefix outside every group runs full even when a test file shares it', () => {
  assert.equal(select(['Sources/Hop/SettingsWindowView.swift']).mode, 'full');
});
test('a prefix in several groups selects the tests of all of them', () => {
  const selection = select(['Sources/HopCore/IdleWatch.swift']);
  assert.ok(names(selection).includes('CoolingControllerTests.swift'));
  assert.ok(names(selection).includes('HardwareFanCurveTests.swift'));
});
test('a selected test file with a class on another base runs full', () => {
  assert.equal(select(['Tests/HopUITests/MenuOrderTests.swift']).mode, 'full');
});
test('a feature on the build-only list runs the baseline without tests of its own', () => {
  assert.deepEqual(select(['Sources/Hop/Alerts.swift']).tests, [...config.baseline].sort());
});
test('a patch bump stays scoped; a minor or major release and other plist edits run in full', () => {
  assert.equal(select(['scripts/Info.plist']).mode, 'scoped');
  assert.ok(names(select(['scripts/Info.plist'])).includes('ReleaseCopyLayoutTests.swift'));
  assert.equal(select(['scripts/Info.plist'], { head: '2.6.0' }).mode, 'full');
  assert.equal(select(['scripts/Info.plist'], { head: '3.0.0' }).mode, 'full');
  assert.equal(select(['scripts/Info.plist'], { headPlist: plist('2.5.7').replace('</dict>', '<key>LSUIElement</key><true/></dict>') }).mode, 'full');
  assert.equal(select([], { headPlist: '' }).mode, 'full');
});
test('a changed test file runs itself; a deleted one is ignored; a helper without tests runs full', () => {
  assert.ok(names(select(['Tests/HopUITests/SoundMixerPresetsTests.swift'])).includes('SoundMixerPresetsTests.swift'));
  assert.equal(select(['Tests/HopUITests/GoneTests.swift']).mode, 'scoped');
  assert.equal(select(['Tests/HopUITests/TestSupport.swift']).mode, 'full');
});
test('the scoped plan keeps the base steps, passes the classes and drops CodeQL', () => {
  const selection = select(['Sources/Hop/KeepAwakeController.swift']);
  const scoped = scopedPlan(plan, selection, 'b'.repeat(40), config);
  assert.deepEqual(scoped.steps.map(step => step.id), config.scopedSteps);
  const tests = scoped.steps.find(step => step.id === 'hop-tests');
  assert.equal(tests.args.at(-1), '--classes=' + selection.classes.join(','));
  assert.ok(!scoped.artifacts.some(item => item.path.startsWith('hop-codeql')));
  assert.deepEqual(scoped.scope, { base: 'b'.repeat(40), tests: selection.tests });
  assert.throws(() => scopedPlan(plan, { mode: 'full' }, 'b'.repeat(40), config));
});
test('a small edit of a shared file runs the core tests and the groups its changed lines name', () => {
  const diffs = { 'Sources/Hop/App.swift': hunk(['-        guard let scheme = url.scheme, scheme == "hop" else { return }', '+        guard AgentCommandParser.urlSchemes.contains(url.scheme ?? "") else { return }']) };
  const selection = select(['Sources/Hop/App.swift'], { diffs });
  assert.equal(selection.mode, 'scoped');
  for (const name of ['AgentCommandTests.swift', 'PanelDismissalTests.swift', 'ModuleVisibilityTests.swift', ...config.baseline.map(path => path.split('/').at(-1))])
    assert.ok(names(selection).includes(name), name);
  assert.ok(!names(selection).includes('SoundMixerPresetsTests.swift'));
  assert.ok(!names(selection).includes('CoolingControllerTests.swift'));
});
test('identifiers in lowerCamel and the enclosing declaration also pick their groups', () => {
  const diffs = { 'Sources/Hop/App.swift': hunk(['+        model.keepAwake.start()'], 'func soundMixerDidChange()') };
  const selection = select(['Sources/Hop/App.swift'], { diffs });
  assert.ok(names(selection).includes('CoolingControllerTests.swift'));
  assert.ok(names(selection).includes('SoundMixerPresetsTests.swift'));
});
test('a shared file without a diff, with a large diff or next to a minor release runs full', () => {
  const big = { 'Sources/Hop/App.swift': hunk(Array.from({ length: config.shared.maxChangedLines + 1 }, (_, i) => '+let value' + i + ' = 0')) };
  assert.equal(select(['Sources/Hop/App.swift'], { diffs: { 'Sources/Hop/App.swift': '' } }).mode, 'full');
  assert.equal(select(['Sources/Hop/App.swift'], { diffs: big }).mode, 'full');
  const small = { 'Sources/Hop/App.swift': hunk(['+let spacing = 4']) };
  assert.equal(select(['Sources/Hop/App.swift'], { diffs: small }).mode, 'scoped');
  assert.equal(select(['Sources/Hop/App.swift', 'scripts/Info.plist'], { diffs: small, head: '2.6.0' }).mode, 'full');
});
test('a removed shared file and the summed size of several shared edits run full', () => {
  assert.equal(select(['Sources/Hop/SoleInstance.swift'], { diffs: { 'Sources/Hop/SoleInstance.swift': hunk(['-let lock = 1']) } }).mode, 'full');
  const half = hunk(Array.from({ length: Math.ceil(config.shared.maxChangedLines / 2) + 1 }, (_, i) => '+let value' + i + ' = 0'));
  assert.equal(select(['Sources/Hop/App.swift'], { diffs: { 'Sources/Hop/App.swift': half } }).mode, 'scoped');
  assert.equal(select(['Sources/Hop/App.swift', 'Sources/Hop/Theme.swift'], { diffs: { 'Sources/Hop/App.swift': half, 'Sources/Hop/Theme.swift': half } }).mode, 'full');
});
test('changed lines that look like diff headers still count and name their groups', () => {
  const diffs = { 'Sources/Hop/App.swift': hunk(['--- TimerEngine.start()', '+++ x']) };
  assert.ok(names(select(['Sources/Hop/App.swift'], { diffs })).includes('TimerEngineTests.swift'));
});
const tooling = ['scripts/build-app.sh', 'scripts/Hop.entitlements', 'scripts/own-ci/engine.test.mjs', 'scripts/own-ci/scope.test.mjs'];
const checkFiles = ['scripts/own-ci/scope.json', 'scripts/own-ci/scope.mjs', 'scripts/own-ci/engine.mjs', 'scripts/own-ci/network.mjs', 'scripts/own-ci/preparing-version.mjs', 'scripts/own-ci/script-syntax.mjs', 'scripts/checks.sh', 'scripts/check-release', 'scripts/build-budget.py'];
const stepIds = selection => scopedPlan(plan, selection, 'c'.repeat(40), config).steps.map(step => step.id);
test('a packaging script runs the script syntax step, release self-tests and the tests that read it, not every Swift test', () => {
  for (const path of ['scripts/build-app.sh', 'scripts/Hop.entitlements']) {
    const selection = select([path], { extra: tooling });
    assert.equal(selection.mode, 'scoped', path);
    assert.ok(stepIds(selection).includes('script-syntax'));
    assert.ok(stepIds(selection).includes('adapter-self-tests'));
    assert.ok(!stepIds(selection).includes('core-self-tests'));
    assert.ok(!stepIds(selection).includes('hop-codeql'));
    assert.ok(selection.tests.includes('Tests/HopCoreTests/SigningTests.swift'));
    assert.ok(selection.tests.includes('Tests/HopCoreTests/ReleaseNewsTests.swift'));
    assert.ok(!names(selection).includes('CoolingControllerTests.swift'));
  }
});
test('a file that picks the check, wraps the Swift steps or verifies the proof runs full', () => {
  for (const path of checkFiles) assert.equal(select([path], { extra: [...tooling, ...checkFiles] }).mode, 'full', path);
});
test('a change to a check self-test runs the self-tests with the baseline', () => {
  const selection = select(['scripts/own-ci/engine.test.mjs', 'scripts/own-ci/scope.test.mjs'], { extra: tooling });
  assert.equal(selection.mode, 'scoped');
  for (const id of ['build-budget-self-tests', 'core-self-tests', 'adapter-self-tests', 'script-syntax', 'hop-build', 'hop-tests']) assert.ok(stepIds(selection).includes(id), id);
  assert.deepEqual(selection.tests, [...config.baseline].sort());
});
test('a removed tooling file runs full and a feature fix adds no tooling steps', () => {
  assert.equal(select(['scripts/build-app.sh']).mode, 'full');
  assert.deepEqual(stepIds(select(['Sources/Hop/KeepAwakeController.swift'])), config.scopedSteps);
  assert.throws(() => scopedPlan(plan, { ...select([]), steps: ['hop-codeql'] }, 'c'.repeat(40), config));
  assert.throws(() => validateScope({ ...config, tooling: [{ name: 'x', match: ['a'], steps: ['s'], groups: ['nope'] }] }));
});
test('the scope map rejects a missing or malformed shared rule', () => {
  assert.throws(() => validateScope({ ...config, shared: undefined }));
  assert.throws(() => validateScope({ ...config, shared: { ...config.shared, maxChangedLines: 0 } }));
});

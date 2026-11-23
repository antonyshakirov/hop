import assert from 'node:assert/strict';
import test from 'node:test';
import { swiftTestBatches, summarizeTestBatches } from './hop-report.mjs';

const discovery = ['HopCoreTests.CoreTests/testCore', 'HopUITests.FirstTests/testFirst', 'HopUITests.SecondTests/testSecond', 'HopHardwareTests.FanTests/testFan', 'HopPluginAPITests.APITests/testAPI', 'HopPluginRuntimeTests.RuntimeTests/testRuntime'].join('\n');
function output(cases) {
  return cases.map(id => {
    const [suite, name] = id.split('/');
    return `Test Case '-[${suite} ${name}]' started.\nTest Case '-[${suite} ${name}]' passed (0.001 seconds).\n`;
  }).join('') + "Test Suite 'Selected tests' passed at 2026-11-16.\n";
}
function reports() {
  return swiftTestBatches(discovery, 6).map(batch => ({ id: batch.id, output: output(batch.cases) }));
}
test('UI suites run in separate processes while every discovered case remains required', () => {
  const batches = swiftTestBatches(discovery, 6);
  assert.deepEqual(batches.map(batch => batch.id), ['HopCoreTests', 'HopHardwareTests', 'HopPluginAPITests', 'HopPluginRuntimeTests', 'HopUITests.FirstTests', 'HopUITests.SecondTests']);
  for (const batch of batches) {
    const filter = new RegExp(batch.filter);
    assert.deepEqual(discovery.split('\n').filter(id => filter.test(id)).sort(), batch.cases);
  }
  assert.equal(summarizeTestBatches(discovery, reports(), 6).passed, 6);
  assert.throws(() => swiftTestBatches(discovery + '\n' + discovery, 6));
  assert.throws(() => swiftTestBatches(discovery, 7));
  for (const unknown of ['HopNewTests.NewTests/testNew', 'HopUITests.New Tests/testNew', 'unexpected output']) {
    assert.throws(() => swiftTestBatches(discovery + '\n' + unknown, 6));
    assert.throws(() => summarizeTestBatches(discovery + '\n' + unknown, reports(), 6));
  }
});
test('batch reports reject missing, duplicate, failed, skipped or foreign cases', () => {
  const valid = reports();
  const changeFirst = transform => valid.map((report, i) => i ? report : transform(report));
  const corruptOutput = transform => changeFirst(report => ({ ...report, output: transform(report.output) }));
  const invalidReports = [
    valid.slice(1), [...valid, valid[0]],
    changeFirst(report => ({ ...report, id: 'unknown' })),
    corruptOutput(() => ''),
    corruptOutput(value => value + value),
    corruptOutput(value => value.replace("' passed (", "' failed (")),
    corruptOutput(value => value.replace("' passed (", "' skipped (")),
    corruptOutput(value => value + valid[1].output),
    corruptOutput(value => value.replace("'Selected tests' passed", "'Selected tests' failed")),
  ];
  for (const invalid of invalidReports) assert.throws(() => summarizeTestBatches(discovery, invalid, 6));
});
test('scoped classes run alone, joined per target, and every named class must exist', () => {
  const classes = ['HopCoreTests.CoreTests', 'HopUITests.SecondTests'];
  const batches = swiftTestBatches(discovery, 6, classes);
  assert.deepEqual(batches.map(batch => batch.id), ['HopCoreTests', 'HopUITests.SecondTests']);
  assert.equal(batches[0].filter, '^HopCoreTests\\.(CoreTests)/');
  const scopedReports = batches.map(batch => ({ id: batch.id, output: output(batch.cases) }));
  assert.equal(summarizeTestBatches(discovery, scopedReports, 6, classes).passed, 2);
  assert.throws(() => summarizeTestBatches(discovery, scopedReports.slice(1), 6, classes));
  for (const invalid of [[], ['HopUITests.MissingTests'], ['HopCoreTests.CoreTests', 'HopCoreTests.CoreTests'], ['Other.Thing']])
    assert.throws(() => swiftTestBatches(discovery, 6, invalid));
});

import assert from 'node:assert/strict';
import test from 'node:test';
import { summarizeTests, validateMessages, validateSarif, parsePreparingVersion } from './hop-report.mjs';

const list = 'HopCoreTests.TimerTests/testOne\nHopUITests.ViewTests/testTwo\n';
const passed = `Test Case '-[HopCoreTests.TimerTests testOne]' started.
Test Case '-[HopCoreTests.TimerTests testOne]' passed (0.001 seconds).
Test Case '-[HopUITests.ViewTests testTwo]' started.
Test Case '-[HopUITests.ViewTests testTwo]' passed (0.001 seconds).
Test Suite 'All tests' passed at 2026-10-15.
`;
test('test coverage requires every discovered case exactly once and successful', () => {
  assert.equal(summarizeTests(list, passed, 2).passed, 2);
  for (const bad of [passed.replace('testTwo]\' passed', 'testTwo]\' skipped'), passed.replace(/Test Case.*testTwo.*\n/g, ''), passed + passed, passed.replace("'All tests' passed", "'Selected tests' passed")]) assert.throws(() => summarizeTests(list, bad, 2));
  assert.throws(() => summarizeTests('', passed, 2));
  assert.throws(() => summarizeTests(list, passed, 3));
});
test('incoming messages retain English and trailer restrictions', () => {
  assert.doesNotThrow(() => validateMessages(['Checks: run the complete local gate\n\nKeep the report tied to the source.']));
  for (const bad of ['\u041f\u0440\u043e\u0432\u0435\u0440\u043a\u0438: \u0433\u043e\u0442\u043e\u0432\u043e', 'Checks: pass\nCo-Authored-By: Name <synthetic@example.invalid>', 'Checks: generated with a tool']) assert.throws(() => validateMessages([bad]));
});
test('SARIF requires actual successful CodeQL analysis with rules', () => {
  const report = { version: '2.1.0', runs: [{ tool: { driver: { name: 'CodeQL', rules: [{ id: 'swift/test' }] } }, invocations: [{ executionSuccessful: true }], results: [] }] };
  assert.equal(validateSarif(report).results, 0);
  for (const bad of [{ ...report, runs: [] }, { ...report, runs: [{ ...report.runs[0], invocations: [] }] }, { ...report, runs: [{ ...report.runs[0], invocations: [{ executionSuccessful: false }] }] }, { ...report, runs: [{ ...report.runs[0], tool: { driver: { name: 'CodeQL', rules: [] } } }] }]) assert.throws(() => validateSarif(bad));
});


test('preparing version accepts only the isolated command result', () => {
  assert.equal(parsePreparingVersion('2.4.1\n'), '2.4.1');
});
for (const output of ['', 'version: notes disagree\n', '2.4.1\n2.4.2\n']) test('preparing version rejects ambiguous output ' + JSON.stringify(output), () => {
  assert.throws(() => parsePreparingVersion(output));
});

test('hardware cases participate in complete Swift test coverage', () => {
  const hardwareList = list + 'HopHardwareTests.FanPolicyTests/testHardware\n';
  const hardwarePassed = passed.replace("Test Suite 'All tests' passed", "Test Case '-[HopHardwareTests.FanPolicyTests testHardware]' started.\nTest Case '-[HopHardwareTests.FanPolicyTests testHardware]' passed (0.001 seconds).\nTest Suite 'All tests' passed");
  assert.equal(summarizeTests(hardwareList, hardwarePassed, 3).passed, 3);
  assert.throws(() => summarizeTests(hardwareList, passed, 2));
  assert.throws(() => summarizeTests(list, hardwarePassed, 2));
  assert.throws(() => summarizeTests(hardwareList, hardwarePassed.replace("testHardware]' passed", "testHardware]' failed"), 3));
});

for (const target of ['HopPluginAPITests', 'HopPluginRuntimeTests']) test(target + ' cannot disappear from discovery or execution', () => {
  const discovered = list + target + '.PluginTests/testPlugin\n';
  const executed = passed.replace("Test Suite 'All tests' passed", `Test Case '-[${target}.PluginTests testPlugin]' started.\nTest Case '-[${target}.PluginTests testPlugin]' passed (0.001 seconds).\nTest Suite 'All tests' passed`);
  assert.equal(summarizeTests(discovered, executed, 3).passed, 3);
  assert.throws(() => summarizeTests(discovered, passed, 2));
  assert.throws(() => summarizeTests(list, executed, 2));
});

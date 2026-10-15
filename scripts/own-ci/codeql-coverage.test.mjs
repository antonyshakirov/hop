import assert from 'node:assert/strict';
import test from 'node:test';
import { validateExtractionCoverage } from './codeql-coverage.mjs';
const files = ['Sources/Hop/App.swift', 'Sources/HopCore/Timer.swift'];
const report = paths => ({ runs: [{ tool: { driver: {} }, invocations: [{ toolExecutionNotifications: paths.map(uri => ({ descriptor: { id: 'swift/diagnostics/successfully-extracted-files' }, locations: [{ physicalLocation: { artifactLocation: { uri } } }] })) }] }] });
test('requires every application source even when analysis has no findings', () => {
 assert.throws(() => validateExtractionCoverage(report(['Package.swift', files[0]]), files, '/private/run'), /Timer.swift/);
 assert.equal(validateExtractionCoverage(report(files), files, '/private/run').extracted, 2);
});
test('supports indexed diagnostics and encoded absolute source locations', () => {
 const r = report(['file:///private/run/' + files[0], '/private/run/' + files[1]]);
 r.runs[0].tool.driver.notifications = [{ id: 'swift/diagnostics/successfully-extracted-files' }];
 for (const n of r.runs[0].invocations[0].toolExecutionNotifications) n.descriptor = { index: 0 };
 assert.equal(validateExtractionCoverage(r, files, '/private/run').extracted, 2);
});
test('ignores other diagnostics and rejects absent evidence', () => {
 const r = report(files);r.runs[0].invocations[0].toolExecutionNotifications[0].descriptor.id = 'swift/other';
 assert.throws(() => validateExtractionCoverage(r, files, '/private/run'), /App.swift/);
 assert.throws(() => validateExtractionCoverage({ runs: [] }, files, '/private/run'));
});

test('rejects failed extraction even if a partial database could be finalized', async () => {
 const { validateExtractorExecution } = await import('./codeql-coverage.mjs');
 const successful = 'Extractor /private/sdk/extractor terminated with exit code 0.';
 assert.equal(validateExtractorExecution(successful, ['INFO [extractor/main] completed']).invocations, 1);
 assert.throws(() => validateExtractorExecution(successful + '\nExtractor /private/sdk/extractor terminated with exit code 1.', ['INFO [extractor/main] completed']));
 assert.throws(() => validateExtractorExecution(successful, ['2026-10-16 02:00:00 ERRO [extractor/compiler] ambiguous reference']));
 assert.throws(() => validateExtractorExecution('', []));
});

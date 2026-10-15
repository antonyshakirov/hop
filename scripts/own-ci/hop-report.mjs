export function summarizeTests(discovery, output, minimum = 1675) {
  const cases = discovery.split(/\r?\n/).filter(line => /^Hop(?:Core|UI)Tests\.[^/\s]+\/\S+$/.test(line));
  if (cases.length < minimum || new Set(cases).size !== cases.length) throw new Error('Incomplete Swift test discovery');
  const started = new Set(), finished = new Set();
  for (const match of output.matchAll(/^Test Case '-\[([^\s\]]+) ([^\s\]]+)\]' (started|passed|failed|skipped)(?:\.| \([^\n]*\)\.)$/gm)) {
    const id = match[1] + '/' + match[2], status = match[3];
    if (!cases.includes(id)) throw new Error('Undiscovered Swift test ran');
    if (status === 'started') {
      if (started.has(id)) throw new Error('Repeated Swift test');
      started.add(id);
    } else {
      if (status !== 'passed' || !started.has(id) || finished.has(id)) throw new Error('Failed, skipped or repeated Swift test completion');
      finished.add(id);
    }
  }
  if (finished.size !== cases.length || started.size !== cases.length || !/^Test Suite 'All tests' passed at /m.test(output)) throw new Error('Swift test run incomplete');
  return { passed: finished.size, skipped: 0, cases: [...finished].sort() };
}

export function validateMessages(messages) {
  if (!messages.length || messages.some(message => /[\u0400-\u04ff]|^\s*co-authored-by:|generated with/im.test(message))) throw new Error('Incoming commits violate the English-only, no-trailer policy');
}

export function validateSarif(report) {
  if (report.version !== '2.1.0' || !Array.isArray(report.runs) || !report.runs.length) throw new Error('Missing CodeQL SARIF run');
  let rules = 0, results = 0;
  for (const run of report.runs) {
    const driver = run.tool?.driver;
    if (driver?.name !== 'CodeQL' || !Array.isArray(driver.rules) || !driver.rules.length || !Array.isArray(run.invocations) || !run.invocations.length || run.invocations.some(item => item.executionSuccessful !== true) || !Array.isArray(run.results)) throw new Error('CodeQL analysis incomplete');
    rules += driver.rules.length; results += run.results.length;
  }
  return { runs: report.runs.length, rules, results };
}

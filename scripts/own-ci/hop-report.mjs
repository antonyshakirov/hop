function discoveredCases(discovery, minimum) {
  const cases = discovery.split(/\r?\n/).filter(line => line.length);
  if (cases.some(line => !/^Hop(?:Core|UI|Hardware|PluginAPI|PluginRuntime)Tests\.[^/\s]+\/\S+$/.test(line)) || cases.length < minimum || new Set(cases).size !== cases.length) throw new Error('Incomplete Swift test discovery');
  return cases;
}

function completedCases(cases, output, suite) {
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
  if (finished.size !== cases.length || started.size !== cases.length || !output.split(/\r?\n/).some(line => line.startsWith(`Test Suite '${suite}' passed at `))) throw new Error('Swift test run incomplete');
  return { passed: finished.size, skipped: 0, cases: [...finished].sort() };
}

export function summarizeTests(discovery, output, minimum = 1675) {
  return completedCases(discoveredCases(discovery, minimum), output, 'All tests');
}

export function swiftTestBatches(discovery, minimum = 1675, classes) {
  let selected = discoveredCases(discovery, minimum);
  if (classes) {
    if (!Array.isArray(classes) || !classes.length || new Set(classes).size !== classes.length || classes.some(name => !/^Hop(?:Core|UI|Hardware|PluginAPI|PluginRuntime)Tests\.[A-Za-z0-9_]+$/.test(name))) throw new Error('Invalid scoped test classes');
    for (const name of classes) if (!selected.some(id => id.startsWith(name + '/'))) throw new Error('Scoped test class not discovered: ' + name);
    selected = selected.filter(id => classes.includes(id.split('/')[0]));
  }
  const groups = new Map();
  for (const id of selected) {
    const suite = id.split('/')[0];
    const group = id.startsWith('HopUITests.') ? suite : suite.split('.')[0];
    if (!groups.has(group)) groups.set(group, []);
    groups.get(group).push(id);
  }
  return [...groups].sort(([a], [b]) => a.localeCompare(b)).map(([id, cases]) => {
    const suites = [...new Set(cases.map(item => item.split('/')[0].split('.')[1]))].sort();
    const filter = id.startsWith('HopUITests.') ? '^' + id.replaceAll('.', '\\.') + '/'
      : classes ? '^' + id + '\\.(' + suites.join('|') + ')/' : '^' + id + '\\.';
    return { id, cases: cases.sort(), filter };
  });
}

export function summarizeTestBatches(discovery, reports, minimum = 1675, classes) {
  const batches = swiftTestBatches(discovery, minimum, classes);
  if (reports.length !== batches.length || new Set(reports.map(report => report.id)).size !== batches.length) throw new Error('Incomplete Swift test batches');
  const cases = batches.flatMap(batch => {
    const report = reports.find(report => report.id === batch.id);
    if (!report) throw new Error('Missing Swift test batch');
    return completedCases(batch.cases, report.output, 'Selected tests').cases;
  });
  return { passed: cases.length, skipped: 0, cases: cases.sort(), batches: batches.map(batch => batch.id) };
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


export function parsePreparingVersion(output) {
  if (typeof output !== 'string' || !/^\d+\.\d+\.\d+\s*$/.test(output)) throw new Error('Invalid preparing-version result');
  return output.trim();
}

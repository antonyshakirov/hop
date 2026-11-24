// Chooses between the full check and a scoped one from the files changed since
// a base already on origin/main. Anything the map does not cover runs in full.
const featureOf = path => {
  const name = path.split('/').at(-1).replace(/\.[^.]+$/, '');
  return /^(?:[A-Z]+(?=[A-Z][a-z])|[A-Z][a-z0-9]*|[a-z]+)/.exec(name)?.[0] ?? name;
};

const globPattern = glob => new RegExp('^' + glob.split('**').map(part =>
  part.split('*').map(text => text.replace(/[.+?^${}()|[\]\\]/g, '\\$&')).join('[^/]*')).join('.*') + '$');
const matches = (glob, path) => globPattern(glob).test(path);

const version = plist => {
  const found = /<key>CFBundleShortVersionString<\/key>\s*<string>(\d+)\.(\d+)\.(\d+)<\/string>/.exec(plist ?? '');
  return found ? found.slice(1, 4).map(Number) : undefined;
};
const withoutVersions = plist => plist.replace(/(<key>CFBundle(?:ShortVersionString|Version)<\/key>\s*<string>)[^<]*(<\/string>)/g, '$1$2');

// Changed lines of a unified diff and the enclosing declaration git prints after
// each hunk header; file headers end at the first hunk of each file.
const parseDiff = diff => {
  const changes = [], context = [];
  let inHunk = false;
  for (const line of diff.split('\n')) {
    if (line.startsWith('diff --git ')) inHunk = false;
    else if (line.startsWith('@@')) { inHunk = true; context.push(line.replace(/^@@[^@]*@@/, '')); }
    else if (inHunk && /^[+-]/.test(line)) changes.push(line.slice(1));
  }
  return { changes, context };
};
const camelParts = identifier => identifier.replace(/^_+/, '').replace(/^[a-z]/, letter => letter.toUpperCase())
  .match(/[A-Z]+(?=[A-Z][a-z])|[A-Z][a-z0-9]*|[0-9]+/g) ?? [];
const diffTokens = ({ changes, context }) => new Set([...changes, ...context].flatMap(line => (line.match(/[A-Za-z_][A-Za-z0-9_]*/g) ?? []).flatMap(camelParts)));

const testClasses = source => [...source.matchAll(/\bclass\s+([A-Za-z0-9_]+)\s*:\s*XCTestCase\b/g)].map(match => match[1]);
const otherTestBases = source => /\bclass\s+[A-Za-z0-9_]+Tests?\s*:\s*(?!\s|XCTestCase\b)/.test(source);

export function validateScope(config) {
  const strings = value => Array.isArray(value) && value.every(item => typeof item === 'string' && item.length);
  const shared = config.shared;
  if (!shared || !strings(shared.files) || !strings(shared.core) || !Number.isInteger(shared.maxChangedLines) || shared.maxChangedLines < 1) throw new Error('Invalid scope shared rule');
  if (config.schema !== 1 || !strings(config.docs) || !strings(config.full) || !strings(config.buildOnly) || !strings(config.baseline) || !strings(config.scopedSteps) || !Array.isArray(config.paths) || typeof config.groups !== 'object') throw new Error('Invalid scope map');
  for (const rule of config.paths) if (typeof rule.match !== 'string' || !(rule.group in config.groups) || rule.also !== undefined && !strings(rule.also)) throw new Error('Invalid scope path rule');
  for (const tokens of Object.values(config.groups)) if (!strings(tokens)) throw new Error('Invalid scope group');
  return config;
}

// files: tracked paths at HEAD; read(path): file text at HEAD; diff(path): the
// -U0 diff of a shared file; base and head plist texts decide the release rule.
// Returns the full mode or the exact test files.
export function selectScope({ config, changed, files, read, diff, basePlist, headPlist }) {
  validateScope(config);
  const full = reason => ({ mode: 'full', reason });
  const tests = files.filter(path => /^Tests\/[^/]+\/[^/]+\.swift$/.test(path));
  const byFeature = tokens => tests.filter(path => tokens.includes(featureOf(path)));
  const groupOf = token => Object.values(config.groups).filter(tokens => tokens.includes(token)).flat();
  const selected = new Set(config.baseline);
  let sharedChanged = 0;
  for (const path of [...changed].sort()) {
    if (config.docs.some(glob => matches(glob, path))) continue;
    const rule = config.paths.find(item => matches(item.match, path));
    if (rule) {
      for (const file of byFeature(config.groups[rule.group])) selected.add(file);
      for (const glob of rule.also ?? []) for (const file of tests.filter(item => matches(glob, item))) selected.add(file);
      continue;
    }
    if (config.full.some(glob => matches(glob, path))) return full('shared file ' + path);
    if (config.shared.files.some(glob => matches(glob, path))) {
      if (!files.includes(path)) return full('shared file removed ' + path);
      const text = diff?.(path);
      if (typeof text !== 'string' || !text.trim()) return full('no diff for shared file ' + path);
      const parsed = parseDiff(text);
      sharedChanged += parsed.changes.length;
      if (!parsed.changes.length) return full('no changed lines read for shared file ' + path);
      if (sharedChanged > config.shared.maxChangedLines) return full('large change in shared files');
      for (const glob of config.shared.core) for (const file of tests.filter(item => matches(glob, item))) selected.add(file);
      for (const token of diffTokens(parsed)) for (const file of byFeature(groupOf(token))) selected.add(file);
      continue;
    }
    if (/^Tests\/[^/]+\/[^/]+\.swift$/.test(path)) { if (files.includes(path)) selected.add(path); continue; }
    if (!/^Sources\/[^/]+\/[^/]+\.(swift|c|h|m)$/.test(path)) return full('unmapped file ' + path);
    const token = featureOf(path);
    if (config.buildOnly.includes(token)) continue;
    const found = byFeature(groupOf(token));
    if (!found.length) return full('no feature group for ' + path);
    for (const file of found) selected.add(file);
  }
  const base = version(basePlist), head = version(headPlist);
  if (!base || !head) return full('version unreadable');
  if (base[0] !== head[0] || base[1] !== head[1]) return full('minor or major release ' + head.join('.'));
  if (withoutVersions(basePlist) !== withoutVersions(headPlist)) return full('Info.plist changed beyond the version');
  const classes = [];
  for (const file of [...selected].sort()) {
    if (!files.includes(file)) return full('baseline test missing ' + file);
    const source = read(file);
    const found = testClasses(source);
    if (!found.length || otherTestBases(source)) return full('test classes not read from ' + file);
    const target = file.split('/')[1];
    for (const name of found) classes.push(target + '.' + name);
  }
  return { mode: 'scoped', tests: [...selected].sort(), classes: [...new Set(classes)].sort() };
}

export function scopedPlan(plan, selection, base, config) {
  if (selection.mode !== 'scoped') throw new Error('Scoped plan needs a scoped selection');
  const steps = plan.steps.filter(step => config.scopedSteps.includes(step.id)).map(step => step.id !== 'hop-tests' ? step
    : { ...step, args: [...step.args, '--classes=' + selection.classes.join(',')], tapMinimum: 1 });
  if (steps.length !== config.scopedSteps.length || !steps.some(step => step.id === 'hop-tests')) throw new Error('Scoped steps missing from plan');
  return { ...plan, steps, artifacts: (plan.artifacts ?? []).filter(item => !item.path.startsWith('hop-codeql')), scope: { base, tests: selection.tests } };
}

export const title = 'Live mechanics catalog: sync then rebuild';
export const state = (v) => v.phase === 'failed' ? `Failed at ${v.failedAt}` : v.phase;
export const step = (action, from, to) => ({
  Sync: to.phase === 'rebuild' ? 'sync gold catalog [rebuild requested]' : 'sync gold catalog [sync only]',
  Rebuild: 'replace pull facts from catalog',
  Fail: 'report failed stage and committed prefix',
  Done: 'finished',
}[action] || action);

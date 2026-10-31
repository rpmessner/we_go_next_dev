export const title = 'Ruleset sync: committed stages and explicit failure';
export const state = (v) => v.phase === 'failed' ? `Failed at ${v.failedAt}` : v.phase;
export const step = (action, from, to) => {
  if (action === 'Sync') {
    const condition = to.phase === 'activate' ? 'activate requested' : to.phase === 'promote' ? 'promotion only requested' : 'no further stages requested';
    return `sync definitions, keep status [${condition}]`;
  }
  if (action === 'Activate') return `activate, replace previous active [${to.phase === 'promote' ? 'promotion requested' : 'no promotion requested'}]`;
  if (action === 'Promote') return `refresh fact keys [${to.phase === 'rebuild' ? 'rebuild requested' : 'no rebuild requested'}]`;
  return {Rebuild: 'rebuild facts', Fail: 'report failed stage and committed prefix', Done: 'finished'}[action] || action;
};

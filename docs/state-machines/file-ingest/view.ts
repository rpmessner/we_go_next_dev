export const title = 'Per-file ingest';
export const state = (v) => v.phase;
export const step = (action) => ({Start: 'claim file', Parse: 'parse completed pull', Project: 'build silver and gold', Finish: 'finish', Fail: 'fail', Tick: 'deadline approaches', Timeout: 'deadline expires', Rest: 'rest'}[action] ?? action);

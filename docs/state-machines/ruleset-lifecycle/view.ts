export const title = 'Ruleset status: atomic active replacement';
export const state = (v) => `${v.statuses[1]} / ${v.statuses[2]}`;
export const step = (action) => ({Activate: 'activate one, archive previous active', ArchiveDraft: 'archive draft', Sync: 'sync without status change', RejectResetOrActiveArchive: 'reject reset or standalone active archive'}[action] || action);

export const title = "Legacy bug: re-seed demotes the active ruleset";
export const state = (v) => `${v.phase}: ${v.status}${v.startedActive ? " (started active)" : ""}`;
export const step = (action) => action === "Sync" ? "re-seed defaults status to draft" : action;

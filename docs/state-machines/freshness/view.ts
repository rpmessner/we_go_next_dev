export const title = "A rebuild is current only when facts and document agree";
export const state = (v) => `${v.phase}: facts ${v.facts}, document ${v.document}, ${v.stamp}`;
export const step = (action) => ({
  Begin: "start rebuild",
  Build: "build facts",
  Write: "write document",
  Commit: "commit consistent outputs",
  Fail: "write fails or process stops",
  Done: "terminal"
}[action] ?? action);

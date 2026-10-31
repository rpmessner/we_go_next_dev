export const title = "Live log watching";
export const state = (v: any) => v.phase;
export const step = (action: string, from: any, to: any) => {
  if (action === "Return") {
    if (from.phase === "rotating") return "new log import finishes";
    if (from.phase === "syncing") return "current sync finishes";
    return from.tracked === to.tracked ? "stale reply ignored" : "stale reply overwrites selected log";
  }
  return ({Select: "view or import newest log", Directory: "watch directory", Sync: "appended data or pending replay", Rotate: "newer log appears", Fail: "sync fails or ingest busy", Retry: "backoff expires", Write: "log written", Tick: "no writes until deadline", Stop: "watch off", Restart: "restore durable watch", Done: null}[action] ?? null);
};

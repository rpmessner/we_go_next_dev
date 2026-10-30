const LABELS: Record<string, string> = {
  waiting: "No pull yet",
  in_progress: "Pull in progress",
  importing: "Importing the pull",
  projecting: "Building pull data",
  building_gold: "Building facts",
  checking: "Running checks",
  ready: "Card ready",
  ready_partial: "Card ready, one check missing",
  failed: "Error shown on the card",
  stale: "Card marked stale",
  skipped: "Reset skipped",
};

export const title = "Pull pipeline: what the Tonight page shows for one pull";

export const state = (v: any) => LABELS[v.phase] ?? v.phase;

export const group = (v: any) =>
  ["ready", "ready_partial"].includes(v.phase)
    ? "shown"
    : ["failed", "stale"].includes(v.phase)
      ? "attention"
      : v.phase === "skipped"
        ? "hidden"
        : "working";

export const colors = { working: "blue", shown: "teal", attention: "orange", hidden: "tan" };

const STEPS: Record<string, string | null> = {
  EncounterStart: "the boss is pulled",
  EncounterEnd: "the encounter ends (log flushes)",
  ImportedShortReset: "the import finishes [pull under 10 s]",
  Imported: "the import finishes",
  Projected: "pull data is built",
  Built: "facts are built",
  ChecksDone: "the checks finish [rules unchanged]",
  CheckFailed: "a check fails",
  ChecksDoneOnOldRules: "the checks finish [rules changed meanwhile]",
  StepFailed: "a step fails",
  Retry: "the pipeline retries [under the attempt limit]",
  RulesChanged: "mechanic rules change",
  Rebuild: "the rebuild starts",
  Done: null,
};

export const step = (action: string) => (action in STEPS ? STEPS[action] : action);

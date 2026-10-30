const LABELS: Record<string, string> = {
  tonight: "Tonight (break page)",
  encounter: "Encounter detail",
  docked: "Encounter + docked panel",
  failures: "Failures",
  picker: "Question picker",
  question: "Question in the Analysis tree",
  inspector: "Evidence inspector open",
  recap_jump: "Death Recap row + Back bar",
};

export const title = "App flow: how the Analysis screens connect";

export const state = (v: any) => LABELS[v.screen] ?? v.screen;

export const group = (v: any) =>
  ["tonight", "encounter", "failures", "docked"].includes(v.screen)
    ? "existing pages"
    : v.screen === "picker"
      ? "asking"
      : v.screen === "question"
        ? "answer"
        : "evidence";

export const colors = { "existing pages": "blue", asking: "tan", answer: "teal", evidence: "purple" };

const STEPS: Record<string, string | null> = {
  OpenPullCard: "you open a pull card",
  OpenFailures: "you open Failures",
  BackToTonight: null, // the top menu works from every page; hidden to keep the chart readable
  AskWhy: "Ask why",
  AskAboutPull: "Ask about this pull",
  AskAboutMechanic: "Ask about this mechanic",
  AskFollowUp: "you ask a follow-up",
  Ask: "you ask",
  CancelPicker: "you cancel",
  OpenInspector: "citation [inspector]",
  CloseInspector: "close",
  JumpToRecap: "citation [jump]",
  BackToAnswer: "Back to the answer",
  OpenPanel: "you open the panel",
  ClosePanel: "you close the panel",
  OpenFullAnalysis: "Open full analysis",
};

export const step = (action: string) => (action in STEPS ? STEPS[action] : action);

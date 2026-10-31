const LABELS: Record<string, string> = {
  draft: "Question picked",
  computing: "Computing (built-in, no model)",
  thinking: "Agent working",
  calling_tool: "Running a Tool",
  writing: "Writing the answer",
  answered: "Answered",
  judged: "Verdict recorded",
  limit_hit: "Stopped at a limit",
  failed: "Error, Retry offered",
  cancelled: "Cancelled",
};

export const title = "Question lifecycle: one question in the Analysis tree";

export const state = (v: any) => `${LABELS[v.phase] ?? v.phase} (${v.process})`;

export const group = (v: any) =>
  ["thinking", "calling_tool", "writing", "computing"].includes(v.phase)
    ? "running"
    : ["answered", "judged"].includes(v.phase)
      ? "answered"
      : ["limit_hit", "failed", "cancelled"].includes(v.phase)
        ? "stopped"
        : "start";

export const colors = { start: "tan", running: "blue", answered: "teal", stopped: "orange" };

const STEPS: Record<string, string | null> = {
  AskBuiltin: "you ask [built-in]",
  Computed: "Tool returns",
  AskAgent: "you ask [needs AI]",
  ToolRequested: "calls a Tool [budget left]",
  OverLimit: "budget used up",
  ToolReturned: "Tool returns",
  AnswerStarted: "starts answering",
  AnswerDone: "answer done",
  Timeout: "10 min pass",
  ApiError: "AI call fails",
  Retry: "Retry",
  Cancel: "Cancel",
  ContinueWithNewCap: "Continue [once, no Tool running]",
  RecordVerdict: "you give a verdict",
  Stop: "runner stops [no Tool outstanding]",
  Crash: "process lost",
  Recover: "boot records interruption [no paid replay]",
  RestartOnDemand: "operator resumes stored snapshot",
  Done: null,
};

export const step = (action: string) => (action in STEPS ? STEPS[action] : action);

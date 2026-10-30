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

export const state = (v: any) => LABELS[v.phase] ?? v.phase;

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
  AskBuiltin: "you ask [built-in with a Tool]",
  Computed: "the Tool returns",
  AskAgent: "you ask [needs the agent]",
  ToolRequested: "the agent calls a Tool [budget left beyond the answer]",
  OverLimit: "the agent wants more [budget used up]",
  ToolReturned: "the Tool returns",
  AnswerStarted: "the agent starts answering [a turn left]",
  AnswerDone: "the answer finishes",
  Timeout: "10 minutes pass",
  ApiError: "the model call fails",
  Retry: "you press Retry",
  Cancel: "you press Cancel",
  ContinueWithNewCap: "you continue with a new cap [once, no Tool still running]",
  RecordVerdict: "you give a verdict",
  Done: null,
};

export const step = (action: string) => (action in STEPS ? STEPS[action] : action);

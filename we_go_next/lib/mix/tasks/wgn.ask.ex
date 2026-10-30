defmodule Mix.Tasks.Wgn.Ask do
  @moduledoc """
  Ask a headless, recorded Analysis question (this makes paid API requests).

      mix wgn.ask --log Archive-WoWCombatLog-090626_103607.txt --boss Sszorak --pull 5
      mix wgn.ask --log LOG_ID --question "Who died first?" --model claude-opus-5-5

  With no --question, asks corpus Q1 about the selected boss and pull.
  ANTHROPIC_API_KEY must be present in the runtime environment.
  """
  use Mix.Task
  alias WeGoNext.Analysis
  @shortdoc "Ask a recorded Analysis question using the Anthropic API (paid)"

  @impl true
  def run(args) do
    {scope, text, model} = options(args)
    Mix.Task.run("app.start")

    case Analysis.ask(scope, text, subscribe: true, model: model) do
      {:ok, question, _pid} ->
        Mix.shell().info("Analysis session #{question.session_id}; question #{question.id}")
        await(question.id)

      {:error, reason} ->
        Mix.raise(to_string(reason))
    end
  end

  defp options(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [log: :string, boss: :string, pull: :integer, question: :string, model: :string]
      )

    if rest != [] or invalid != [], do: Mix.raise("Unknown question arguments")
    log = opts[:log] || Mix.raise("--log is required")
    boss = Keyword.get(opts, :boss, "Sszorak")
    pull = Keyword.get(opts, :pull, 5)
    if pull < 1, do: Mix.raise("--pull must be positive")

    text =
      Keyword.get(
        opts,
        :question,
        "Why did #{boss} pull #{pull} wipe: what was the first thing that went wrong?"
      )

    {%{"log" => log, "boss" => boss, "pull_number" => pull}, text,
     Keyword.get(opts, :model, "claude-opus-5-5")}
  end

  defp await(id) do
    receive do
      {:analysis_question, ^id, {:state, :answered}} ->
        Mix.shell().info(Analysis.get_question(id).answer)

      {:analysis_question, ^id, {:state, state}}
      when state in [:failed, :limit_hit, :cancelled] ->
        question = Analysis.get_question(id)

        Mix.raise(
          "Question #{state}: #{question.error || "stopped; recorded progress is retained"}"
        )

      {:analysis_question, ^id, _} ->
        await(id)
    after
      610_000 -> Mix.raise("Question exceeded the wait window; inspect its recorded state")
    end
  end
end

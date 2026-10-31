defmodule Mix.Tasks.WeGoNext.SyncRaidRules do
  @moduledoc """
  Syncs code-defined raid mechanics and optionally rebuilds failures.

  Usage:

      mix we_go_next.sync_raid_rules
      mix we_go_next.sync_raid_rules the_voidspire
      mix we_go_next.sync_raid_rules current_tier --rebuild

  Synced mechanics are immediately failure-ready; `--rebuild` refreshes existing pulls.
  """

  use Mix.Task

  alias WeGoNext.Rules

  @shortdoc "Sync code-defined raid mechanics"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, invalid} =
      OptionParser.parse(args,
        strict: [rebuild: :boolean]
      )

    if invalid != [] do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    raid_slug =
      case positional do
        [] -> "current_tier"
        [slug] -> slug
        _ -> Mix.raise("Expected at most one raid slug")
      end

    report_result(Rules.sync_raid_mechanics(raid_slug, opts))
  end

  defp report_result(result) do
    case result do
      {:ok, result} ->
        Mix.shell().info(
          "Synced #{length(result.criteria)} raid mechanic(s) into the live gold catalog."
        )

        if result.rebuild do
          Mix.shell().info("Rebuilt failures: #{inspect(result.rebuild)}")
        end

      {:error, %{stage: stage, completed: completed, reason: reason}} ->
        Mix.raise(
          "Raid mechanic sync failed at #{stage}. " <>
            "Committed stages: #{inspect(completed)}. " <>
            "Earlier stages were not rolled back; retry the same command after fixing the cause. " <>
            "Failure: #{inspect(reason, limit: :infinity)}"
        )

      {:error, reason} ->
        Mix.raise("Failed to sync raid mechanics: #{inspect(reason)}")
    end
  end
end

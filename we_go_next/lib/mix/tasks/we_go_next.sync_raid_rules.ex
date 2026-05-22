defmodule Mix.Tasks.WeGoNext.SyncRaidRules do
  @moduledoc """
  Syncs code-defined raid mechanics and optionally rebuilds failures.

  Usage:

      mix we_go_next.sync_raid_rules
      mix we_go_next.sync_raid_rules the_voidspire
      mix we_go_next.sync_raid_rules midnight_season_1 --activate --failure-ready --rebuild

  `--failure-ready` makes synced mechanics available to failure rebuilds.
  """

  use Mix.Task

  alias WeGoNext.Rules

  @shortdoc "Sync code-defined raid mechanics"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, invalid} =
      OptionParser.parse(args,
        strict: [
          activate: :boolean,
          failure_ready: :boolean,
          promote: :boolean,
          rebuild: :boolean,
          version: :integer,
          name: :string
        ]
      )

    if invalid != [] do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    raid_slug =
      case positional do
        [] -> "midnight_season_1"
        [slug] -> slug
        _ -> Mix.raise("Expected at most one raid slug")
      end

    case Rules.sync_raid_mechanics(raid_slug, normalize_opts(opts)) do
      {:ok, result} ->
        Mix.shell().info(
          "Synced #{length(result.criteria)} raid mechanic(s) from #{result.ruleset.name}."
        )

        if result.promoted do
          Mix.shell().info("#{length(result.promoted.criteria)} mechanic(s) are failure-ready.")
        end

        if result.rebuild do
          Mix.shell().info("Rebuilt failures: #{inspect(result.rebuild)}")
        end

      {:error, reason} ->
        Mix.raise("Failed to sync raid mechanics: #{inspect(reason)}")
    end
  end

  defp normalize_opts(opts) do
    if Keyword.get(opts, :failure_ready) do
      opts
      |> Keyword.delete(:failure_ready)
      |> Keyword.put(:promote, true)
    else
      Keyword.delete(opts, :failure_ready)
    end
  end
end

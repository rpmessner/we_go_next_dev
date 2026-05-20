defmodule Mix.Tasks.WeGoNext.SyncRaidRules do
  @moduledoc """
  Syncs code-defined raid mechanics into editable rules.

  Usage:

      mix we_go_next.sync_raid_rules
      mix we_go_next.sync_raid_rules the_voidspire
      mix we_go_next.sync_raid_rules midnight_season_1 --activate --promote --rebuild
  """

  use Mix.Task

  alias WeGoNext.Rules

  @shortdoc "Sync code-defined raid mechanics into rules"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, invalid} =
      OptionParser.parse(args,
        strict: [
          activate: :boolean,
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

    case Rules.sync_raid_mechanics(raid_slug, opts) do
      {:ok, result} ->
        Mix.shell().info(
          "Synced #{length(result.criteria)} raid mechanic rule(s) into #{result.ruleset.name} v#{result.ruleset.version}."
        )

        if result.promoted do
          Mix.shell().info("Promoted #{length(result.promoted.criteria)} rule snapshot(s).")
        end

        if result.rebuild do
          Mix.shell().info("Rebuilt gold facts: #{inspect(result.rebuild)}")
        end

      {:error, reason} ->
        Mix.raise("Failed to sync raid mechanics: #{inspect(reason)}")
    end
  end
end

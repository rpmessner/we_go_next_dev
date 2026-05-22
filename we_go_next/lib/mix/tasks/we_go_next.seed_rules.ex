defmodule Mix.Tasks.WeGoNext.SeedRules do
  @moduledoc """
  Syncs mechanic definitions.

  Usage:

      mix we_go_next.seed_rules
      mix we_go_next.seed_rules path/to/rules.json

  With no path, this task syncs the current-tier Midnight Season 1 raid catalog.
  Passing a path imports a legacy/static JSON definition file directly.
  """

  use Mix.Task

  alias WeGoNext.Rules

  @shortdoc "Sync current-tier raid mechanics or a static JSON file"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    result =
      case args do
        [] -> Rules.sync_current_tier_mechanics()
        [path] -> Rules.seed_rules_from_file(path)
        _ -> Mix.raise("Expected zero args or one JSON rules file path")
      end

    case result do
      {:ok, %{ruleset: ruleset, criteria: criteria}} ->
        Mix.shell().info(
          "Synced #{length(criteria)} mechanic definition(s) into #{ruleset.name} v#{ruleset.version}."
        )

      {:error, reason} ->
        Mix.raise("Failed to sync mechanic definitions: #{inspect(reason)}")
    end
  end
end

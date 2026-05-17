defmodule Mix.Tasks.WeGoNext.SeedRules do
  @moduledoc """
  Seeds mechanic rules from static JSON.

  Usage:

      mix we_go_next.seed_rules
      mix we_go_next.seed_rules path/to/rules.json
  """

  use Mix.Task

  alias WeGoNext.Rules

  @shortdoc "Seed mechanic rules from static JSON"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    result =
      case args do
        [] -> Rules.seed_initial_rules()
        [path] -> Rules.seed_rules_from_file(path)
      end

    case result do
      {:ok, %{ruleset: ruleset, criteria: criteria}} ->
        Mix.shell().info(
          "Seeded #{length(criteria)} mechanic rule(s) into ruleset #{ruleset.name} v#{ruleset.version}."
        )

      {:error, reason} ->
        Mix.raise("Failed to seed mechanic rules: #{inspect(reason)}")
    end
  end
end

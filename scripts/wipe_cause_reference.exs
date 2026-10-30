defmodule WipeCauseReference do
  @moduledoc "Replays revision-2 reference silver evidence through the production gold selector."
  alias WeGoNext.Gold.FactWipeCause

  def output do
    root = Path.expand("..", __DIR__)
    evidence = Path.join(root, "docs/ai-analysis/reference-set/evidence")
    deaths = Jason.decode!(File.read!(Path.join(evidence, "q05.json")))["deaths"]
    index = File.read!(Path.join(root, "docs/ai-analysis/reference-set/index.md"))

    pulls =
      Regex.scan(~r/^\| (4\d\d) \| (.*?) \| \d+ \| (kill|wipe) \| (\d+) \|/m, index)
      |> Enum.map(fn [_, id, boss, outcome, duration] ->
        id = String.to_integer(id)
        encounter = %{id: id, name: boss, success: outcome == "kill", fight_time_ms: String.to_integer(duration)}
        observations =
          deaths
          |> Enum.filter(&(&1["pull"] == id))
          |> Enum.map(fn d ->
            %{target_guid: d["guid"], player_name: d["name"],
              died_at_ms_into_fight: d["death_ms"], killing_blow_spell_id: d["killing_spell"]}
          end)

        Map.put(encounter, :deciding_deaths, FactWipeCause.deciding_deaths(encounter, observations))
      end)

    %{reference_revision: 2, derivation_version: FactWipeCause.current_version(), pulls: pulls}
  end
end

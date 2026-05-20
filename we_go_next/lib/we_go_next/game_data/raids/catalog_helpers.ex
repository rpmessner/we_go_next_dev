defmodule WeGoNext.GameData.Raids.CatalogHelpers do
  @moduledoc false

  def boss(name, encounter_id, dbm_module_id, dbm_module_map_id, zone_id) do
    %{
      name: name,
      encounter_id: encounter_id,
      dbm_module_id: dbm_module_id,
      dbm_module_map_id: dbm_module_map_id,
      zone_id: zone_id
    }
  end

  def rule_criteria(mechanics) do
    mechanics
    |> Enum.filter(&(Map.get(&1, :track, true) != false))
    |> Enum.map(&rule_criterion/1)
  end

  defp rule_criterion(mechanic) do
    %{
      "spell_id" => mechanic.spell_id,
      "spell_name" => mechanic.name,
      "mechanic_type" => Atom.to_string(mechanic.type),
      "boss_encounter_id" => mechanic.boss_encounter_id,
      "boss_name" => mechanic.boss_name,
      "threshold" => threshold(mechanic),
      "notes" => notes(mechanic),
      "active" => true
    }
  end

  defp threshold(%{rule: %{max_hits: max_hits}}), do: %{"max_hits" => max_hits}

  defp threshold(%{rule: %{must_interrupt: must_interrupt}}),
    do: %{"must_interrupt" => must_interrupt}

  defp threshold(_mechanic), do: %{}

  defp notes(mechanic) do
    sources =
      mechanic
      |> Map.get(:sources, [])
      |> Enum.map(&Atom.to_string/1)
      |> Enum.join(", ")

    ["raid: #{mechanic.raid_name}", "sources: #{sources}", Map.get(mechanic, :notes)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" | ")
  end
end

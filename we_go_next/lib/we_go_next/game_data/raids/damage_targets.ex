defmodule WeGoNext.GameData.Raids.DamageTargets do
  @moduledoc "Encounter-scoped authored NPC classes, never a generic padding verdict."
  alias WeGoNext.GameData.Raids.{MidnightLairs, VenomousAbyss}

  def for_encounter(id) do
    VenomousAbyss.damage_targets()
    |> Map.merge(MidnightLairs.damage_targets())
    |> Enum.find_value(fn {key, value} ->
      if to_string(key) == to_string(id), do: value
    end) ||
      %{
        boss: [],
        priority: [],
        verified: false,
        notes: "No damage-target catalog for this encounter; other is unclassified, not padding."
      }
  end

  def classify(guid, targets) do
    case String.split(guid, "-") do
      [kind, _, _, _, _, npc, _] when kind in ["Creature", "Vehicle"] ->
        case Integer.parse(npc) do
          {id, ""} -> class(id, targets)
          _ -> :other
        end

      _ ->
        :other
    end
  end

  defp class(id, targets) do
    cond do
      id in targets.boss -> :boss
      id in targets.priority -> :priority
      true -> :other
    end
  end
end

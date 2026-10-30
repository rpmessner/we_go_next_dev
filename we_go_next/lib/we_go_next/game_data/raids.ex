defmodule WeGoNext.GameData.Raids do
  @moduledoc "Index of code-defined raid mechanic catalogs."

  alias WeGoNext.GameData.Raids.{
    CurrentTier,
    Dreamrift,
    MarchOnQuelDanas,
    MidnightLairs,
    MidnightSeason1,
    VenomousAbyss,
    Voidspire
  }

  def all do
    Enum.map(CurrentTier.raids(), & &1.info())
  end

  def by_slug(slug)

  def by_slug("current_tier"), do: CurrentTier
  def by_slug("the_venomous_abyss"), do: VenomousAbyss
  def by_slug("venomous_abyss"), do: VenomousAbyss
  def by_slug("midnight_lairs"), do: MidnightLairs
  def by_slug("midnight_season_1"), do: MidnightSeason1
  def by_slug("the_voidspire"), do: Voidspire
  def by_slug("voidspire"), do: Voidspire
  def by_slug("the_dreamrift"), do: Dreamrift
  def by_slug("dreamrift"), do: Dreamrift
  def by_slug("march_on_quel_danas"), do: MarchOnQuelDanas
  def by_slug("march_on_queldanas"), do: MarchOnQuelDanas
  def by_slug(_slug), do: nil

  def by_dbm_module_map_id(module_map_id)

  def by_dbm_module_map_id(1307), do: Voidspire
  def by_dbm_module_map_id(1308), do: MarchOnQuelDanas
  def by_dbm_module_map_id(1314), do: Dreamrift
  def by_dbm_module_map_id(_module_map_id), do: nil

  def by_boss_encounter_id(encounter_id) when is_binary(encounter_id) do
    case Integer.parse(encounter_id) do
      {id, ""} -> by_boss_encounter_id(id)
      {_id, _rest} -> nil
      :error -> nil
    end
  end

  def by_boss_encounter_id(encounter_id) when is_integer(encounter_id) do
    Enum.find(CurrentTier.raids(), fn raid_module ->
      Enum.any?(raid_module.bosses(), &(&1.encounter_id == encounter_id))
    end)
  end

  def by_boss_encounter_id(_encounter_id), do: nil

  def interruptible_spells do
    CurrentTier.mechanics()
    |> Enum.filter(&(&1.mechanic_type == :interrupt))
  end
end

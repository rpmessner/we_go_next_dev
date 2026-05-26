defmodule WeGoNext.GameData.DefensiveBuffs do
  @moduledoc """
  Known player defensive cooldown buff spell metadata.

  This list is intentionally narrow. It gates the silver defensive-window
  projection so we do not turn every aura into a generic buff warehouse.
  """

  @buffs [
    %{id: 642, name: "Divine Shield", category: "immunity"},
    %{id: 1022, name: "Blessing of Protection", category: "external"},
    %{id: 31850, name: "Ardent Defender", category: "personal"},
    %{id: 33206, name: "Pain Suppression", category: "external"},
    %{id: 47585, name: "Dispersion", category: "immunity"},
    %{id: 47788, name: "Guardian Spirit", category: "external"},
    %{id: 48707, name: "Anti-Magic Shell", category: "personal"},
    %{id: 48792, name: "Icebound Fortitude", category: "personal"},
    %{id: 61336, name: "Survival Instincts", category: "personal"},
    %{id: 6940, name: "Blessing of Sacrifice", category: "external"},
    %{id: 86659, name: "Guardian of Ancient Kings", category: "personal"},
    %{id: 104773, name: "Unending Resolve", category: "personal"},
    %{id: 108271, name: "Astral Shift", category: "personal"},
    %{id: 108416, name: "Dark Pact", category: "personal"},
    %{id: 110959, name: "Greater Invisibility", category: "personal"},
    %{id: 115203, name: "Fortifying Brew", category: "personal"},
    %{id: 118038, name: "Die by the Sword", category: "personal"},
    %{id: 122278, name: "Dampen Harm", category: "personal"},
    %{id: 122783, name: "Diffuse Magic", category: "personal"},
    %{id: 184364, name: "Enraged Regeneration", category: "personal"},
    %{id: 184662, name: "Shield of Vengeance", category: "personal"},
    %{id: 186265, name: "Aspect of the Turtle", category: "immunity"},
    %{id: 187827, name: "Metamorphosis", category: "personal"},
    %{id: 196555, name: "Netherwalk", category: "immunity"},
    %{id: 198589, name: "Blur", category: "personal"},
    %{id: 204018, name: "Blessing of Spellwarding", category: "external"},
    %{id: 22812, name: "Barkskin", category: "personal"},
    %{id: 235450, name: "Prismatic Barrier", category: "personal"},
    %{id: 23920, name: "Spell Reflection", category: "personal"},
    %{id: 243435, name: "Fortifying Brew", category: "personal"},
    %{id: 31224, name: "Cloak of Shadows", category: "immunity"},
    %{id: 31230, name: "Cheat Death", category: "personal"},
    %{id: 363916, name: "Obsidian Scales", category: "personal"},
    %{id: 374348, name: "Renewing Blaze", category: "personal"},
    %{id: 45438, name: "Ice Block", category: "immunity"},
    %{id: 498, name: "Divine Protection", category: "personal"},
    %{id: 5277, name: "Evasion", category: "personal"},
    %{id: 55342, name: "Mirror Image", category: "personal"},
    %{id: 871, name: "Shield Wall", category: "personal"},
    %{id: 97463, name: "Rallying Cry", category: "external"}
  ]

  @by_id Map.new(@buffs, &{&1.id, &1})
  @ids MapSet.new(Map.keys(@by_id))

  def all, do: @buffs
  def ids, do: @ids
  def get(spell_id) when is_integer(spell_id), do: Map.get(@by_id, spell_id)
  def get(_spell_id), do: nil
end

defmodule WeGoNext.GameData.Raids.MarchOnQuelDanas do
  @moduledoc """
  Curated mechanic catalog for March on Quel'Danas.
  """

  import WeGoNext.GameData.Raids.CatalogHelpers

  @raid_name "March on Quel'Danas"
  @raid_slug "march_on_quel_danas"

  def info do
    %{
      name: @raid_name,
      slug: @raid_slug,
      product: "wow",
      channel: "retail",
      zone_ids: [2913],
      dbm_module_map_ids: [1308],
      tier: "Midnight Season 1"
    }
  end

  def bosses do
    [
      boss("Belo'ren, Child of Al'ar", 3182, 2739, 1308, 2913),
      boss("Midnight Falls", 3183, 2740, 1308, 2913)
    ]
  end

  def mechanics do
    []
  end

  def rule_criteria, do: rule_criteria(mechanics())
end

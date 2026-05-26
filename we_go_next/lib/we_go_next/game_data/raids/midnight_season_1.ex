defmodule WeGoNext.GameData.Raids.MidnightSeason1 do
  @moduledoc """
  Aggregate catalog for Midnight Season 1 current-tier raids.
  """

  alias WeGoNext.GameData.Raids.{Dreamrift, MarchOnQuelDanas, Voidspire}

  @raid_modules [Voidspire, Dreamrift, MarchOnQuelDanas]

  def info do
    %{
      name: "Midnight Season 1",
      slug: "midnight_season_1",
      product: "wow",
      channel: "retail",
      raid_slugs: Enum.map(@raid_modules, & &1.info().slug),
      tier: "Midnight Season 1"
    }
  end

  def raids, do: @raid_modules

  def bosses, do: Enum.flat_map(@raid_modules, & &1.bosses())

  def mechanics, do: Enum.flat_map(@raid_modules, & &1.mechanics())

  def rule_criteria, do: Enum.flat_map(@raid_modules, & &1.rule_criteria())
end

defmodule WeGoNext.GameData.Raids.CurrentTier do
  @moduledoc """
  Default Midnight catalog, including current progression and Season 1 coverage.

  One live mechanics catalog serves imported history as well as current pulls; do not
  drop the Season 1 criteria when syncing The Venomous Abyss and Midnight Lairs.
  """

  alias WeGoNext.GameData.Raids.{MidnightLairs, MidnightSeason1, VenomousAbyss}

  def raids, do: MidnightSeason1.raids() ++ [VenomousAbyss, MidnightLairs]

  def info do
    %{
      name: "Midnight Current Tier",
      slug: "current_tier",
      product: "wow",
      channel: "retail",
      raid_slugs: Enum.map(raids(), & &1.info().slug),
      tier: "Midnight"
    }
  end

  def bosses, do: Enum.flat_map(raids(), & &1.bosses())
  def mechanics, do: Enum.flat_map(raids(), & &1.mechanics())
  def rule_criteria, do: Enum.flat_map(raids(), & &1.rule_criteria())
end

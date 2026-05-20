defmodule WeGoNext.GameData.Raids do
  @moduledoc "Index of code-defined raid mechanic catalogs."

  alias WeGoNext.GameData.Raids.{Dreamrift, MarchOnQuelDanas, MidnightSeason1, Voidspire}

  def all do
    [
      Voidspire.info(),
      Dreamrift.info(),
      MarchOnQuelDanas.info()
    ]
  end

  def by_slug(slug)

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
end

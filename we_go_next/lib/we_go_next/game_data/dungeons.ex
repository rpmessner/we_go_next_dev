defmodule WeGoNext.GameData.Dungeons do
  @moduledoc "Index of all Midnight Season 1 M+ dungeons."

  alias WeGoNext.GameData.Dungeons.AlgetharAcademy
  alias WeGoNext.GameData.Dungeons.MagistersTerrace
  alias WeGoNext.GameData.Dungeons.MaisaraCaverns
  alias WeGoNext.GameData.Dungeons.NexusPointXenas
  alias WeGoNext.GameData.Dungeons.PitOfSaron
  alias WeGoNext.GameData.Dungeons.SeatOfTheTriumvirate
  alias WeGoNext.GameData.Dungeons.Skyreach
  alias WeGoNext.GameData.Dungeons.WindrunnerSpire

  def all do
    [
      AlgetharAcademy.info(),
      MagistersTerrace.info(),
      MaisaraCaverns.info(),
      NexusPointXenas.info(),
      PitOfSaron.info(),
      SeatOfTheTriumvirate.info(),
      Skyreach.info(),
      WindrunnerSpire.info(),
    ]
  end

  def by_slug(slug)

  def by_slug("algethar_academy"), do: AlgetharAcademy
  def by_slug("magisters_terrace"), do: MagistersTerrace
  def by_slug("maisara_caverns"), do: MaisaraCaverns
  def by_slug("nexus_point_xenas"), do: NexusPointXenas
  def by_slug("pit_of_saron"), do: PitOfSaron
  def by_slug("seat_of_the_triumvirate"), do: SeatOfTheTriumvirate
  def by_slug("skyreach"), do: Skyreach
  def by_slug("windrunner_spire"), do: WindrunnerSpire
  def by_slug(_), do: nil

  def by_map_id(map_id)

  def by_map_id(402), do: AlgetharAcademy
  def by_map_id(558), do: MagistersTerrace
  def by_map_id(560), do: MaisaraCaverns
  def by_map_id(559), do: NexusPointXenas
  def by_map_id(556), do: PitOfSaron
  def by_map_id(239), do: SeatOfTheTriumvirate
  def by_map_id(161), do: Skyreach
  def by_map_id(557), do: WindrunnerSpire
  def by_map_id(_), do: nil

  def all_interruptible_spells do
    [
      AlgetharAcademy.interruptible_spells(),
      MagistersTerrace.interruptible_spells(),
      MaisaraCaverns.interruptible_spells(),
      NexusPointXenas.interruptible_spells(),
      PitOfSaron.interruptible_spells(),
      SeatOfTheTriumvirate.interruptible_spells(),
      Skyreach.interruptible_spells(),
      WindrunnerSpire.interruptible_spells(),
    ]
    |> List.flatten()
  end
end

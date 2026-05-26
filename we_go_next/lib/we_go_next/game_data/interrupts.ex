defmodule WeGoNext.GameData.Interrupts do
  @moduledoc "Shared accessors for code-defined interruptible spell IDs."

  alias WeGoNext.GameData.{Dungeons, Raids}

  def spell_id_list do
    dungeon_ids =
      Dungeons.all_interruptible_spells()
      |> Enum.map(& &1.id)

    raid_ids =
      Raids.interruptible_spells()
      |> Enum.map(& &1.spell_id)

    dungeon_ids
    |> Kernel.++(raid_ids)
    |> Enum.uniq()
  end

  def spell_ids, do: MapSet.new(spell_id_list())
end

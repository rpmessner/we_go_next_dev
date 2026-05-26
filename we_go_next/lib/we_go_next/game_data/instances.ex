defmodule WeGoNext.GameData.Instances do
  @moduledoc """
  Maps WoW Journal Instance IDs to instance names.

  These are the instance IDs that appear in ENCOUNTER_START events.
  Add new entries as we encounter them in combat logs.
  """

  @instance_names %{
    # Midnight Season 1 M+ Dungeons
    658 => "Pit of Saron",
    1209 => "Skyreach",
    2526 => "Algeth'ar Academy",
    2805 => "Windrunner Spire",
    2811 => "Nexus Point Xenas",
    2915 => "Maisara Caverns",
    # Could also be Seat of the Triumvirate or Magister's Terrace - add when seen

    # Midnight Raids
    2912 => "The Voidspire",
    2913 => "March on Quel'Danas",
    2939 => "The Dreamrift"
  }

  @doc "Returns the instance name for a journal instance ID, or nil if unknown."
  def name(instance_id) when is_binary(instance_id) do
    case Integer.parse(instance_id) do
      {id, _} -> name(id)
      :error -> nil
    end
  end

  def name(instance_id) when is_integer(instance_id) do
    Map.get(@instance_names, instance_id)
  end

  def name(_), do: nil
end

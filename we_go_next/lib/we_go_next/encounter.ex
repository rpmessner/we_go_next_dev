defmodule WeGoNext.Encounter do
  @moduledoc """
  Represents a WoW raid encounter with metadata and events.
  """

  defstruct [
    :id,
    :name,
    :difficulty_id,
    :difficulty_name,
    :group_size,
    :instance_id,
    :start_time,
    :end_time,
    :success,
    :fight_time_ms,
    events: []
  ]

  @difficulty_names %{
    14 => "Normal",
    15 => "Heroic",
    16 => "Mythic",
    17 => "Looking For Raid"
  }

  @doc """
  Creates a new encounter from an ENCOUNTER_START event.
  """
  def start(fields, timestamp) do
    [_event_type, encounter_id, encounter_name, difficulty_id, group_size, instance_id] = fields

    %__MODULE__{
      id: encounter_id,
      name: encounter_name,
      difficulty_id: String.to_integer(difficulty_id),
      difficulty_name: get_difficulty_name(difficulty_id),
      group_size: String.to_integer(group_size),
      instance_id: instance_id,
      start_time: timestamp,
      events: []
    }
  end

  @doc """
  Completes an encounter with ENCOUNTER_END data.
  """
  def finish(encounter, fields, timestamp) do
    [_event_type, _encounter_id, _encounter_name, _difficulty_id, _group_size, success, fight_time] = fields

    %{encounter |
      end_time: timestamp,
      success: success == "1",
      fight_time_ms: String.to_integer(fight_time)
    }
  end

  @doc """
  Adds a combat event to the encounter.
  """
  def add_event(encounter, event) do
    %{encounter | events: [event | encounter.events]}
  end

  @doc """
  Gets the fight duration in seconds.
  """
  def fight_time_sec(%__MODULE__{fight_time_ms: ms}) when is_integer(ms) do
    ms / 1000
  end
  def fight_time_sec(_), do: 0

  defp get_difficulty_name(difficulty_id) when is_binary(difficulty_id) do
    difficulty_id
    |> String.to_integer()
    |> get_difficulty_name()
  end

  defp get_difficulty_name(difficulty_id) when is_integer(difficulty_id) do
    Map.get(@difficulty_names, difficulty_id, "Unknown (#{difficulty_id})")
  end
end

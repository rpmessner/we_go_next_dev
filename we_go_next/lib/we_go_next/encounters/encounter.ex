defmodule WeGoNext.Encounters.Encounter do
  @moduledoc """
  Ecto schema for persisted encounter records.
  Stores encounter metadata and raw log lines for later analysis.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.CombatLogFile

  @difficulty_names %{
    14 => "Normal",
    15 => "Heroic",
    16 => "Mythic",
    17 => "Looking For Raid"
  }

  schema "encounters" do
    field :wow_encounter_id, :string
    field :name, :string
    field :difficulty_id, :integer
    field :difficulty_name, :string
    field :group_size, :integer
    field :instance_id, :string
    field :start_time, :utc_datetime_usec
    field :end_time, :utc_datetime_usec
    field :success, :boolean
    field :fight_time_ms, :integer
    field :raw_log, :string
    field :start_byte, :integer
    field :end_byte, :integer

    belongs_to :combat_log_file, CombatLogFile

    timestamps()
  end

  @doc false
  def changeset(encounter, attrs) do
    encounter
    |> cast(attrs, [
      :wow_encounter_id,
      :name,
      :difficulty_id,
      :difficulty_name,
      :group_size,
      :instance_id,
      :start_time,
      :end_time,
      :success,
      :fight_time_ms,
      :raw_log,
      :start_byte,
      :end_byte,
      :combat_log_file_id
    ])
    |> validate_required([:wow_encounter_id, :name, :combat_log_file_id])
  end

  @doc """
  Creates an Ecto encounter from the in-memory Encounter struct and raw log lines.
  """
  def from_parsed(parsed_encounter, raw_lines, combat_log_file_id, start_byte, end_byte) do
    %{
      wow_encounter_id: parsed_encounter.id,
      name: parsed_encounter.name,
      difficulty_id: parsed_encounter.difficulty_id,
      difficulty_name: parsed_encounter.difficulty_name,
      group_size: parsed_encounter.group_size,
      instance_id: parsed_encounter.instance_id,
      start_time: to_utc_datetime(parsed_encounter.start_time),
      end_time: to_utc_datetime(parsed_encounter.end_time),
      success: parsed_encounter.success,
      fight_time_ms: parsed_encounter.fight_time_ms,
      raw_log: Enum.join(raw_lines, ""),
      start_byte: start_byte,
      end_byte: end_byte,
      combat_log_file_id: combat_log_file_id
    }
  end

  @doc """
  Converts this Ecto record back to an in-memory Encounter struct for analysis.
  """
  def to_encounter_struct(%__MODULE__{} = enc) do
    alias WeGoNext.Encounter

    # Parse the raw log to get events
    events = parse_raw_log(enc.raw_log)

    %Encounter{
      id: enc.wow_encounter_id,
      name: enc.name,
      difficulty_id: enc.difficulty_id,
      difficulty_name: enc.difficulty_name,
      group_size: enc.group_size,
      instance_id: enc.instance_id,
      start_time: enc.start_time,
      end_time: enc.end_time,
      success: enc.success,
      fight_time_ms: enc.fight_time_ms,
      events: events
    }
  end

  defp to_utc_datetime(nil), do: nil

  defp to_utc_datetime(%NaiveDateTime{} = ndt) do
    DateTime.from_naive!(ndt, "Etc/UTC")
  end

  defp to_utc_datetime(%DateTime{} = dt), do: dt

  defp parse_raw_log(nil), do: []
  defp parse_raw_log(""), do: []

  defp parse_raw_log(raw_log) do
    alias WeGoNext.LogReader

    raw_log
    |> String.split("\n", trim: true)
    |> Enum.map(&LogReader.parse_line/1)
    |> Enum.reject(fn {status, _, _} -> status == :invalid end)
    |> Enum.map(fn {timestamp, event_type, fields} ->
      %{timestamp: timestamp, type: event_type, data: fields}
    end)
  end

  @doc """
  Returns human-readable difficulty name for a difficulty ID.
  """
  def difficulty_name(difficulty_id) when is_integer(difficulty_id) do
    Map.get(@difficulty_names, difficulty_id, "Unknown (#{difficulty_id})")
  end
end

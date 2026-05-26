defmodule WeGoNext.Encounters.Encounter do
  @moduledoc """
  Ecto schema for persisted encounter records.
  Stores transitional import bookkeeping for combat log encounter boundaries.
  Events are parsed on-demand from the combat log file via CombatLogParser.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.CombatLogFile

  @difficulty_names %{
    8 => "M+",
    14 => "Normal",
    15 => "Heroic",
    16 => "Mythic",
    17 => "Looking For Raid"
  }

  schema "encounters" do
    field(:wow_encounter_id, :string)
    field(:name, :string)
    field(:difficulty_id, :integer)
    field(:difficulty_name, :string)
    field(:group_size, :integer)
    field(:instance_id, :string)
    field(:start_time, :utc_datetime_usec)
    field(:end_time, :utc_datetime_usec)
    field(:success, :boolean)
    field(:fight_time_ms, :integer)
    field(:start_byte, :integer)
    field(:end_byte, :integer)
    # Mark as reset (intentional boss reset to clear debuffs)
    field(:is_reset, :boolean, default: false)
    # Explicit bridge target for medallion UI routes. This is not persisted on
    # public.encounters; it is attached by WeGoNext.Gold.EncounterIdentity.
    field(:dim_encounter_id, :integer, virtual: true)

    belongs_to(:combat_log_file, CombatLogFile)

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
      :start_byte,
      :end_byte,
      :combat_log_file_id,
      :is_reset
    ])
    |> validate_required([:wow_encounter_id, :name, :combat_log_file_id])
  end

  @doc """
  Creates an Ecto encounter from the in-memory Encounter struct.
  """
  def from_parsed(parsed_encounter, _raw_lines, combat_log_file_id, start_byte, end_byte) do
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
      start_byte: start_byte,
      end_byte: end_byte,
      combat_log_file_id: combat_log_file_id
    }
  end

  @doc """
  Converts this Ecto record back to an in-memory Encounter struct for legacy
  diagnostics and projection parity checks.
  Parses events from the combat log file using stored byte offsets.
  """
  def to_encounter_struct(%__MODULE__{} = enc) do
    alias WeGoNext.{Encounter, Repo, CombatLogFile, CombatLogParser}

    clf = Repo.get!(CombatLogFile, enc.combat_log_file_id)

    # Format start_time for the Zig parser
    start_ts = format_timestamp_for_zig(enc.start_time)

    events =
      case CombatLogParser.parse_events(clf.file_path, enc.start_byte, enc.end_byte, start_ts) do
        {:ok, evts} -> evts
        {:error, _} -> []
      end

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

  defp format_timestamp_for_zig(%DateTime{} = dt) do
    ms = div(elem(dt.microsecond, 0), 1000)

    "#{dt.month}/#{dt.day}/#{dt.year} #{String.pad_leading("#{dt.hour}", 2, "0")}:#{String.pad_leading("#{dt.minute}", 2, "0")}:#{String.pad_leading("#{dt.second}", 2, "0")}.#{ms}-0"
  end

  defp format_timestamp_for_zig(%NaiveDateTime{} = dt) do
    ms = div(elem(dt.microsecond, 0), 1000)

    "#{dt.month}/#{dt.day}/#{dt.year} #{String.pad_leading("#{dt.hour}", 2, "0")}:#{String.pad_leading("#{dt.minute}", 2, "0")}:#{String.pad_leading("#{dt.second}", 2, "0")}.#{ms}-0"
  end

  defp format_timestamp_for_zig(nil), do: "1/1/2000 00:00:00.000-0"

  @doc """
  Converts this Ecto record to a lightweight Encounter struct (no events).
  """
  def to_lightweight_struct(%__MODULE__{} = enc) do
    alias WeGoNext.Encounter

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
      events: []
    }
  end

  defp to_utc_datetime(nil), do: nil

  defp to_utc_datetime(%NaiveDateTime{} = ndt) do
    DateTime.from_naive!(ndt, "Etc/UTC")
  end

  defp to_utc_datetime(%DateTime{} = dt), do: dt

  @doc """
  Returns human-readable difficulty name for a difficulty ID.
  """
  def difficulty_name(difficulty_id) when is_integer(difficulty_id) do
    Map.get(@difficulty_names, difficulty_id, "Unknown (#{difficulty_id})")
  end
end

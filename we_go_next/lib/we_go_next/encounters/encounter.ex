defmodule WeGoNext.Encounters.Encounter do
  @moduledoc """
  Ecto schema for persisted encounter records.
  Stores encounter metadata. Events are stored in the encounter_events table.
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
    field :start_byte, :integer
    field :end_byte, :integer
    # Pre-computed analysis results (deaths, damage, failures, summary)
    field :analysis, :map, default: %{}
    # Storage tier for future use
    field :storage_tier, :string, default: "hot"
    # Mark as reset (intentional boss reset to clear debuffs)
    field :is_reset, :boolean, default: false

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
      :start_byte,
      :end_byte,
      :combat_log_file_id,
      :analysis,
      :storage_tier,
      :is_reset
    ])
    |> validate_required([:wow_encounter_id, :name, :combat_log_file_id])
  end

  @doc """
  Creates an Ecto encounter from the in-memory Encounter struct.

  Options:
    - :analysis - pre-computed analysis results to cache (map)
  """
  def from_parsed(parsed_encounter, _raw_lines, combat_log_file_id, start_byte, end_byte, opts \\ []) do
    analysis = Keyword.get(opts, :analysis, %{})

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
      combat_log_file_id: combat_log_file_id,
      analysis: analysis,
      storage_tier: "hot"
    }
  end

  @doc """
  Converts this Ecto record back to an in-memory Encounter struct for analysis.
  Loads events from the encounter_events table.
  """
  def to_encounter_struct(%__MODULE__{} = enc) do
    alias WeGoNext.Encounter

    # Load events from database
    events = load_events_from_db(enc.id)

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

  # Load events from database and convert to the format analyzers expect
  defp load_events_from_db(encounter_id) do
    import Ecto.Query

    alias WeGoNext.Repo
    alias WeGoNext.Encounters.EncounterEvent

    EncounterEvent
    |> where([e], e.encounter_id == ^encounter_id)
    |> order_by([e], asc: e.timestamp)
    |> Repo.all()
    |> Enum.map(&event_to_map/1)
  end

  # Convert EncounterEvent to the map format analyzers expect
  # Analyzers expect: %{timestamp: _, type: _, data: []}
  # Since we've normalized the data, we convert back to this format
  defp event_to_map(%WeGoNext.Encounters.EncounterEvent{} = event) do
    %{
      timestamp: event.timestamp,
      type: event.event_type,
      # Normalized data - analyzers can now access fields directly
      source_guid: event.source_guid,
      source_name: event.source_name,
      source_flags: event.source_flags,
      target_guid: event.target_guid,
      target_name: event.target_name,
      target_flags: event.target_flags,
      spell_id: event.spell_id,
      spell_name: event.spell_name,
      spell_school: event.spell_school,
      amount: event.amount,
      overkill: event.overkill,
      absorbed: event.absorbed,
      extra_spell_id: event.extra_spell_id,
      extra_spell_name: event.extra_spell_name,
      extra: event.extra,
      time_into_fight: event.time_into_fight
    }
  end

  @doc """
  Converts this Ecto record to a lightweight Encounter struct (no events).
  Use when you have cached analysis and don't need to re-parse raw_log.
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

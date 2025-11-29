defmodule WeGoNext.Encounters.EncounterEvent do
  @moduledoc """
  Ecto schema for normalized combat log events.

  Each event represents a single line from the WoW combat log, parsed and
  normalized into structured fields. This allows analyzers to query events
  directly from the database rather than re-parsing raw log text.

  ## Event Types

  Common event types include:
  - SPELL_DAMAGE, SPELL_PERIODIC_DAMAGE, SWING_DAMAGE - Damage events
  - SPELL_HEAL, SPELL_PERIODIC_HEAL - Healing events
  - SPELL_AURA_APPLIED, SPELL_AURA_REMOVED - Buff/debuff tracking
  - SPELL_INTERRUPT - Successful interrupts
  - SPELL_CAST_START, SPELL_CAST_SUCCESS - Cast tracking
  - UNIT_DIED - Death events
  - COMBATANT_INFO - Player info (class, spec, gear)

  ## Field Usage by Event Type

  All events have: event_type, timestamp, time_into_fight

  Damage events use: source_*, target_*, spell_*, amount, overkill, absorbed
  Death events use: target_* (the unit that died)
  Interrupt events use: source_* (interrupter), target_* (caster), spell_* (interrupt ability), extra_spell_* (interrupted spell)
  Aura events use: source_*, target_*, spell_*
  COMBATANT_INFO uses: source_* (the player), extra (class_id, spec_id, etc.)
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.Encounters.Encounter

  schema "encounter_events" do
    belongs_to :encounter, Encounter

    # Core timing
    field :event_type, :string
    field :timestamp, :utc_datetime_usec
    field :time_into_fight, :float

    # Common prefix (source/target for most events)
    field :source_guid, :string
    field :source_name, :string
    field :source_flags, :integer
    field :target_guid, :string
    field :target_name, :string
    field :target_flags, :integer

    # Spell info (for spell events)
    field :spell_id, :integer
    field :spell_name, :string
    field :spell_school, :integer

    # Damage/healing amounts
    field :amount, :integer
    field :overkill, :integer
    field :absorbed, :integer

    # For interrupts - the spell that was interrupted
    field :extra_spell_id, :integer
    field :extra_spell_name, :string

    # For COMBATANT_INFO and other variable data
    field :extra, :map

    timestamps()
  end

  @required_fields [:encounter_id, :event_type]
  @optional_fields [
    :timestamp,
    :time_into_fight,
    :source_guid,
    :source_name,
    :source_flags,
    :target_guid,
    :target_name,
    :target_flags,
    :spell_id,
    :spell_name,
    :spell_school,
    :amount,
    :overkill,
    :absorbed,
    :extra_spell_id,
    :extra_spell_name,
    :extra
  ]

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:encounter_id)
  end

  @doc """
  Checks if a GUID belongs to a player (starts with "Player-").
  """
  def player_guid?(guid) when is_binary(guid), do: String.starts_with?(guid, "Player-")
  def player_guid?(_), do: false

  @doc """
  Checks if a GUID belongs to an NPC (starts with "Creature-" or "Vehicle-").
  """
  def npc_guid?(guid) when is_binary(guid) do
    String.starts_with?(guid, "Creature-") or String.starts_with?(guid, "Vehicle-")
  end
  def npc_guid?(_), do: false
end

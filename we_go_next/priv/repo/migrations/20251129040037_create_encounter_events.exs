defmodule WeGoNext.Repo.Migrations.CreateEncounterEvents do
  use Ecto.Migration

  def change do
    create table(:encounter_events) do
      add :encounter_id, references(:encounters, on_delete: :delete_all), null: false

      # Core timing
      add :event_type, :string, null: false
      add :timestamp, :utc_datetime_usec
      add :time_into_fight, :float

      # Common prefix (source/target for most events)
      add :source_guid, :string
      add :source_name, :string
      add :source_flags, :integer
      add :target_guid, :string
      add :target_name, :string
      add :target_flags, :integer

      # Spell info (for spell events)
      add :spell_id, :integer
      add :spell_name, :string
      add :spell_school, :integer

      # Damage/healing amounts
      add :amount, :integer
      add :overkill, :integer
      add :absorbed, :integer

      # For interrupts - the spell that was interrupted
      add :extra_spell_id, :integer
      add :extra_spell_name, :string

      # For COMBATANT_INFO and other variable data
      add :extra, :map

      timestamps()
    end

    # Primary lookup - all events for an encounter
    create index(:encounter_events, [:encounter_id])

    # Query by event type (e.g., all UNIT_DIED events)
    create index(:encounter_events, [:encounter_id, :event_type])

    # Query by target (e.g., all damage to a specific player)
    create index(:encounter_events, [:encounter_id, :target_guid])

    # Timeline queries
    create index(:encounter_events, [:encounter_id, :timestamp])
  end
end

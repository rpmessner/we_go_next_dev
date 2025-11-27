defmodule WeGoNext.Repo.Migrations.CreateMechanicCriteria do
  use Ecto.Migration

  def change do
    create table(:mechanic_criteria) do
      # Spell/ability identification
      add :spell_id, :integer, null: false
      add :spell_name, :string, null: false

      # Mechanic classification
      add :mechanic_type, :string, null: false
      # Types: avoidable, interrupt, soak, spread, stack, tank_mechanic, healer_mechanic

      # Optional: link to specific boss (nil = applies globally)
      add :boss_encounter_id, :string
      add :boss_name, :string

      # Failure threshold configuration (JSON for flexibility)
      # Examples:
      #   {"max_hits": 0} - any hit is a failure
      #   {"max_hits": 2} - more than 2 hits is a failure
      #   {"must_interrupt": true} - cast completing is a failure
      add :threshold, :map, default: %{}

      # Human-readable notes for coaching
      add :notes, :text

      # Whether this criteria is currently active
      add :active, :boolean, default: true

      timestamps()
    end

    # Index for quick lookup by spell_id (most common query)
    create index(:mechanic_criteria, [:spell_id])

    # Index for boss-specific criteria lookup
    create index(:mechanic_criteria, [:boss_encounter_id])

    # Unique constraint: one criteria per spell per boss (or global)
    create unique_index(:mechanic_criteria, [:spell_id, :boss_encounter_id],
      name: :mechanic_criteria_spell_boss_unique
    )
  end
end

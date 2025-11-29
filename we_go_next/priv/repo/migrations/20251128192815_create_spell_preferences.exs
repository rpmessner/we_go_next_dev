defmodule WeGoNext.Repo.Migrations.CreateSpellPreferences do
  use Ecto.Migration

  def change do
    create table(:spell_preferences) do
      add :spell_id, :integer, null: false
      add :spell_name, :string, null: false
      add :encounter_id, :integer, null: false
      add :hidden, :boolean, default: false, null: false

      timestamps()
    end

    # One preference per spell per encounter
    create unique_index(:spell_preferences, [:spell_id, :encounter_id])
    create index(:spell_preferences, [:encounter_id])
  end
end

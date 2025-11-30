defmodule WeGoNext.Repo.Migrations.AddDifficultyToCriteria do
  use Ecto.Migration

  def change do
    alter table(:mechanic_criteria) do
      # Difficulty level for this criteria (nil = applies to all difficulties)
      # WoW difficulty IDs: 14=Normal, 15=Heroic, 16=Mythic
      add :difficulty_id, :integer
    end

    # Drop the old unique constraint (spell_id + boss_encounter_id)
    drop unique_index(:mechanic_criteria, [:spell_id, :boss_encounter_id],
      name: :mechanic_criteria_spell_boss_unique
    )

    # New unique constraint includes difficulty
    create unique_index(:mechanic_criteria, [:spell_id, :boss_encounter_id, :difficulty_id],
      name: :mechanic_criteria_spell_boss_difficulty_unique
    )

    # Index for difficulty-based lookups
    create index(:mechanic_criteria, [:difficulty_id])
  end
end

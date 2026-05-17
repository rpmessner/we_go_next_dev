defmodule WeGoNext.Repo.Migrations.CreateRulesLayer do
  use Ecto.Migration

  def change do
    execute("CREATE SCHEMA IF NOT EXISTS rules", "DROP SCHEMA IF EXISTS rules CASCADE")

    create table(:ruleset, prefix: "rules") do
      add(:name, :string, null: false)
      add(:status, :string, null: false, default: "draft")
      add(:version, :integer, null: false, default: 1)
      add(:activated_at, :utc_datetime_usec)
      add(:archived_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:ruleset, [:status], prefix: "rules"))

    create(
      unique_index(:ruleset, [:status],
        prefix: "rules",
        name: :ruleset_one_active_index,
        where: "status = 'active'"
      )
    )

    create table(:mechanic_criterion, prefix: "rules") do
      add(:ruleset_id, references(:ruleset, prefix: "rules", on_delete: :delete_all), null: false)

      add(:spell_id, :integer, null: false)
      add(:spell_name, :string, null: false)
      add(:mechanic_type, :string, null: false)
      add(:boss_encounter_id, :string)
      add(:boss_name, :string)
      add(:difficulty_id, :integer)
      add(:threshold, :map, null: false, default: %{})
      add(:notes, :text)
      add(:active, :boolean, null: false, default: true)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:mechanic_criterion, [:ruleset_id], prefix: "rules"))
    create(index(:mechanic_criterion, [:spell_id], prefix: "rules"))
    create(index(:mechanic_criterion, [:boss_encounter_id], prefix: "rules"))
    create(index(:mechanic_criterion, [:difficulty_id], prefix: "rules"))

    execute(
      """
      CREATE UNIQUE INDEX mechanic_criterion_ruleset_spell_scope_index
      ON rules.mechanic_criterion (
        ruleset_id,
        spell_id,
        COALESCE(boss_encounter_id, ''),
        COALESCE(difficulty_id, 0)
      )
      """,
      "DROP INDEX IF EXISTS rules.mechanic_criterion_ruleset_spell_scope_index"
    )
  end
end

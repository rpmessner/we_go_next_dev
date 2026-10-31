defmodule WeGoNext.Repo.Migrations.CollapseLiveMechanicsCatalog do
  use Ecto.Migration

  def up do
    # Preserve dimension ids/criterion keys and every existing fact. Only obsolete
    # lifecycle metadata disappears; the next sync retires unlisted definitions.
    alter table(:dim_mechanic_criterion, prefix: "gold") do
      add(:valid_from, :utc_datetime_usec)
      add(:valid_until, :utc_datetime_usec)
      remove(:source_rule_id)
      remove(:ruleset_id)
      remove(:ruleset_version)
    end

    alter table(:fact_failure, prefix: "gold") do
      remove(:ruleset_id)
      remove(:ruleset_version)
    end

    create constraint(:dim_mechanic_criterion, :valid_mechanic_window,
      prefix: "gold",
      check: "valid_from IS NULL OR valid_until IS NULL OR valid_from < valid_until"
    )

    drop(table(:mechanic_criterion, prefix: "rules"))
    drop(table(:ruleset, prefix: "rules"))
  end

  def down do
    raise "The retired ruleset lifecycle cannot be reconstructed; restore a backup to roll back"
  end
end

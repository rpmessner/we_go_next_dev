defmodule WeGoNext.Repo.Migrations.AddRulesIdentityToGoldDimMechanicCriterion do
  use Ecto.Migration

  def change do
    alter table(:dim_mechanic_criterion, prefix: "gold") do
      add(:source_rule_id, :bigint, null: false)
      add(:ruleset_id, :bigint, null: false)
      add(:ruleset_version, :integer, null: false)
    end

    create(unique_index(:dim_mechanic_criterion, [:source_rule_id], prefix: "gold"))
    create(index(:dim_mechanic_criterion, [:ruleset_id], prefix: "gold"))
    create(index(:dim_mechanic_criterion, [:ruleset_version], prefix: "gold"))
  end
end

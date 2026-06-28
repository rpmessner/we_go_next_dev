defmodule WeGoNext.Repo.Migrations.AllowPublicMirrorCriteriaWithoutSourceRule do
  use Ecto.Migration

  def change do
    alter table(:dim_mechanic_criterion, prefix: "gold") do
      modify(:source_rule_id, :bigint, null: true)
    end
  end
end

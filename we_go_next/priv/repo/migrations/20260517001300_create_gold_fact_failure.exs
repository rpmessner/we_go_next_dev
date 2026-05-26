defmodule WeGoNext.Repo.Migrations.CreateGoldFactFailure do
  use Ecto.Migration

  def change do
    create table(:fact_failure, primary_key: false, prefix: "gold") do
      add(:encounter_id, references(:encounters, prefix: "public", on_delete: :delete_all),
        null: false
      )

      add(:player_dim_id, references(:dim_player, prefix: "gold"), null: false)

      add(:criterion_id, references(:mechanic_criteria, prefix: "public", on_delete: :delete_all),
        null: false
      )

      add(:failure_count, :integer, null: false)
      add(:total_damage, :bigint, null: false, default: 0)
    end

    execute(
      """
      ALTER TABLE gold.fact_failure
      ADD CONSTRAINT fact_failure_pkey
      PRIMARY KEY (encounter_id, player_dim_id, criterion_id)
      """,
      "ALTER TABLE gold.fact_failure DROP CONSTRAINT fact_failure_pkey"
    )

    create(index(:fact_failure, [:player_dim_id], prefix: "gold"))
    create(index(:fact_failure, [:criterion_id], prefix: "gold"))
  end
end

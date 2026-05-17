defmodule WeGoNext.Repo.Migrations.ReworkGoldFailureDimensions do
  use Ecto.Migration

  def change do
    drop_if_exists(table(:fact_failure, prefix: "gold"))

    create table(:dim_encounter, prefix: "gold") do
      add(:source_file_path, :text)
      add(:source_head_sha256, :string)
      add(:wow_encounter_id, :string, null: false)
      add(:name, :string, null: false)
      add(:difficulty_id, :integer)
      add(:difficulty_name, :string)
      add(:group_size, :integer)
      add(:instance_id, :string)
      add(:start_time, :utc_datetime_usec)
      add(:end_time, :utc_datetime_usec)
      add(:success, :boolean)
      add(:fight_time_ms, :integer)
      add(:start_byte, :bigint)
      add(:end_byte, :bigint)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:dim_encounter, [:wow_encounter_id], prefix: "gold"))
    create(index(:dim_encounter, [:source_head_sha256, :start_byte], prefix: "gold"))

    create table(:dim_mechanic_criterion, prefix: "gold") do
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

    create(index(:dim_mechanic_criterion, [:spell_id], prefix: "gold"))
    create(index(:dim_mechanic_criterion, [:boss_encounter_id], prefix: "gold"))
    create(index(:dim_mechanic_criterion, [:difficulty_id], prefix: "gold"))

    create table(:fact_failure, primary_key: false, prefix: "gold") do
      add(:encounter_dim_id, references(:dim_encounter, prefix: "gold"), null: false)
      add(:player_dim_id, references(:dim_player, prefix: "gold"), null: false)

      add(:criterion_dim_id, references(:dim_mechanic_criterion, prefix: "gold"), null: false)

      add(:failure_count, :integer, null: false)
      add(:total_damage, :bigint, null: false, default: 0)
    end

    execute(
      """
      ALTER TABLE gold.fact_failure
      ADD CONSTRAINT fact_failure_pkey
      PRIMARY KEY (encounter_dim_id, player_dim_id, criterion_dim_id)
      """,
      "ALTER TABLE gold.fact_failure DROP CONSTRAINT fact_failure_pkey"
    )

    create(index(:fact_failure, [:player_dim_id], prefix: "gold"))
    create(index(:fact_failure, [:criterion_dim_id], prefix: "gold"))
  end
end

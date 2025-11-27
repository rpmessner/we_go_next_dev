defmodule CombatLogParser.Repo.Migrations.CreateEncounters do
  use Ecto.Migration

  def change do
    create table(:encounters) do
      add :wow_encounter_id, :string, null: false
      add :name, :string, null: false
      add :difficulty_id, :integer
      add :difficulty_name, :string
      add :group_size, :integer
      add :instance_id, :string
      add :start_time, :utc_datetime_usec
      add :end_time, :utc_datetime_usec
      add :success, :boolean
      add :fight_time_ms, :integer
      add :raw_log, :text
      add :start_byte, :bigint
      add :end_byte, :bigint
      add :combat_log_file_id, references(:combat_log_files, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:encounters, [:combat_log_file_id])
    create index(:encounters, [:wow_encounter_id])
    create index(:encounters, [:start_time])
  end
end

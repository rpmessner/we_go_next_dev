defmodule CombatLogParser.Repo.Migrations.CreateCombatLogFiles do
  use Ecto.Migration

  def change do
    create table(:combat_log_files) do
      add :file_path, :string, null: false
      add :file_size, :bigint
      add :file_mtime, :utc_datetime
      add :last_parsed_byte, :bigint, default: 0
      add :last_parsed_at, :utc_datetime
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:combat_log_files, [:file_path])
    create index(:combat_log_files, [:user_id])
  end
end

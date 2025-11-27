defmodule CombatLogParser.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :string, null: false
      add :wow_logs_path, :string
      add :last_loaded_log, :string

      timestamps()
    end

    create unique_index(:users, [:name])
  end
end

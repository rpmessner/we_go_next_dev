defmodule WeGoNext.Repo.Migrations.AddIsCompleteToCombatLogFiles do
  use Ecto.Migration

  def change do
    alter table(:combat_log_files) do
      add :is_complete, :boolean, default: false, null: false
    end
  end
end

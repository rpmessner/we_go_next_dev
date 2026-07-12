defmodule WeGoNext.Repo.Migrations.AddWatchEnabledToCombatLogFiles do
  use Ecto.Migration

  def change do
    alter table(:combat_log_files) do
      add(:watch_enabled, :boolean, null: false, default: false)
    end
  end
end

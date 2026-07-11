defmodule WeGoNext.Repo.Migrations.AddPublishEnabledToCombatLogFiles do
  use Ecto.Migration

  def change do
    alter table(:combat_log_files) do
      add(:publish_enabled, :boolean, null: false, default: false)
    end
  end
end

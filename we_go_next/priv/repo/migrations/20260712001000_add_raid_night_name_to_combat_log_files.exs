defmodule WeGoNext.Repo.Migrations.AddRaidNightNameToCombatLogFiles do
  use Ecto.Migration

  def change do
    alter table(:combat_log_files) do
      add(:raid_night_name, :string)
    end
  end
end

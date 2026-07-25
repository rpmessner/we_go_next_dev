defmodule WeGoNext.Repo.Migrations.AddTalentsToSilverPlayerInfo do
  use Ecto.Migration

  def change do
    alter table(:player_info, prefix: "silver") do
      # nil = COMBATANT_INFO talent payload absent (unknown); [] = genuinely
      # no talents. Rows are [%{"node_id", "entry_id", "rank"}].
      add(:talents, {:array, :map})
    end
  end
end

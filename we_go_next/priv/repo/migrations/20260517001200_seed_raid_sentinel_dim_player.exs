defmodule WeGoNext.Repo.Migrations.SeedRaidSentinelDimPlayer do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO gold.dim_player (player_guid, player_name, class_id, spec_id)
    VALUES ('__RAID__', 'Raid', NULL, NULL)
    ON CONFLICT (player_guid) DO NOTHING
    """)
  end

  def down do
    execute("DELETE FROM gold.dim_player WHERE player_guid = '__RAID__'")
  end
end

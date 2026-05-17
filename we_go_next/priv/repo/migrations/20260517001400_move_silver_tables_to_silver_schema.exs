defmodule WeGoNext.Repo.Migrations.MoveSilverTablesToSilverSchema do
  use Ecto.Migration

  @table_pairs [
    {:silver_damage_taken, :damage_taken},
    {:silver_damage_done, :damage_done},
    {:silver_death, :death},
    {:silver_interrupt_opportunity, :interrupt_opportunity},
    {:silver_debuff_application, :debuff_application},
    {:silver_player_info, :player_info}
  ]

  def up do
    execute("CREATE SCHEMA IF NOT EXISTS silver")

    Enum.each(@table_pairs, fn {old_name, new_name} ->
      execute("ALTER TABLE public.#{old_name} SET SCHEMA silver")
      execute("ALTER TABLE silver.#{old_name} RENAME TO #{new_name}")
    end)
  end

  def down do
    Enum.each(Enum.reverse(@table_pairs), fn {old_name, new_name} ->
      execute("ALTER TABLE silver.#{new_name} RENAME TO #{old_name}")
      execute("ALTER TABLE silver.#{old_name} SET SCHEMA public")
    end)

    execute("DROP SCHEMA IF EXISTS silver")
  end
end

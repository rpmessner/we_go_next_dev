defmodule WeGoNext.Repo.Migrations.DropLegacyModelLayerArtifacts do
  use Ecto.Migration

  def up do
    alter table(:encounters) do
      remove_if_exists(:analysis, :map)
      remove_if_exists(:storage_tier, :string)
    end

    drop_if_exists(table(:spell_preferences))
    drop_if_exists(table(:mechanic_criteria))
  end

  def down do
    raise "legacy model-layer artifact removal is irreversible"
  end
end

defmodule WeGoNext.Repo.Migrations.AddForceShowToSpellPreferences do
  use Ecto.Migration

  def change do
    alter table(:spell_preferences) do
      add :force_show, :boolean, default: false
    end
  end
end

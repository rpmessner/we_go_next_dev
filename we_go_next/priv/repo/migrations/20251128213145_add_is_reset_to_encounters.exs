defmodule WeGoNext.Repo.Migrations.AddIsResetToEncounters do
  use Ecto.Migration

  def change do
    alter table(:encounters) do
      add :is_reset, :boolean, default: false, null: false
    end
  end
end

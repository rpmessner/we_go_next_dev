defmodule WeGoNext.Repo.Migrations.DropEncounterEvents do
  use Ecto.Migration

  def change do
    drop table(:encounter_events)
  end
end

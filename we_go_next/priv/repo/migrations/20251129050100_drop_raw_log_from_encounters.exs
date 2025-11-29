defmodule WeGoNext.Repo.Migrations.DropRawLogFromEncounters do
  use Ecto.Migration

  def change do
    alter table(:encounters) do
      remove :raw_log, :text
    end
  end
end

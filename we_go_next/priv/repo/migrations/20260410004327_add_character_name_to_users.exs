defmodule WeGoNext.Repo.Migrations.AddCharacterNameToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :character_name, :string
    end
  end
end

defmodule WeGoNext.Repo.Migrations.CreateGoldSchema do
  use Ecto.Migration

  def up do
    execute("CREATE SCHEMA IF NOT EXISTS gold")
  end

  def down do
    execute("DROP SCHEMA IF EXISTS gold")
  end
end

defmodule WeGoNext.Repo.Migrations.AddAnalysisSessionPlaybooks do
  use Ecto.Migration

  def change do
    alter table(:sessions, prefix: "analysis") do
      add :loaded_playbooks, {:array, :map}, null: false, default: []
    end
  end
end

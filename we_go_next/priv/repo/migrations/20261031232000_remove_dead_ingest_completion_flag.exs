defmodule WeGoNext.Repo.Migrations.RemoveDeadIngestCompletionFlag do
  use Ecto.Migration

  def change do
    alter table(:combat_log_files) do
      remove(:is_complete, :boolean, default: false, null: false)
    end
  end
end

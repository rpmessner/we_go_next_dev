defmodule WeGoNext.Repo.Migrations.AddIngestReparseCursor do
  use Ecto.Migration

  def change do
    alter table(:combat_log_files) do
      add(:reparse_from_byte, :bigint)
    end
  end
end

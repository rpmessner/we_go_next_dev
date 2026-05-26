defmodule WeGoNext.Repo.Migrations.AddSourceAndHeadSha256ToCombatLogFiles do
  use Ecto.Migration

  def change do
    alter table(:combat_log_files) do
      add(:source, :string, null: false, default: "live")
      add(:head_sha256, :string)
    end

    create(
      constraint(:combat_log_files, :combat_log_files_source_check,
        check: "source IN ('live', 'warcraftlogs_archive')"
      )
    )
  end
end

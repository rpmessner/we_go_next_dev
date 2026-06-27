defmodule WeGoNext.Repo.Migrations.AddWarcraftLogsReportLinkToCombatLogFiles do
  use Ecto.Migration

  def change do
    alter table(:combat_log_files) do
      add(:warcraft_logs_report_url, :text)
      add(:warcraft_logs_report_code, :string)
      add(:warcraft_logs_fight_id, :integer)
      add(:warcraft_logs_linked_at, :utc_datetime_usec)
    end

    create(index(:combat_log_files, [:warcraft_logs_report_code]))
    create(
      index(:combat_log_files, [:warcraft_logs_report_code, :warcraft_logs_fight_id],
        name: :combat_log_files_wcl_report_fight_index
      )
    )
  end
end

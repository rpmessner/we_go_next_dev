defmodule WeGoNext.Repo.Migrations.AddPublicReports do
  use Ecto.Migration

  def change do
    create table(:public_reports) do
      add(:slug, :string, null: false)
      add(:title, :string, null: false)
      add(:enabled, :boolean, null: false, default: true)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:public_reports, [:slug]))

    alter table(:dim_encounter, prefix: "gold") do
      add(:public_report_id, references(:public_reports, prefix: "public", on_delete: :delete_all))
    end

    drop_if_exists(unique_index(:dim_encounter, [:source_encounter_key], prefix: "gold"))

    create(
      unique_index(:dim_encounter, [:source_encounter_key],
        prefix: "gold",
        name: :dim_encounter_source_encounter_key_parser_index,
        where: "public_report_id IS NULL"
      )
    )

    create(
      unique_index(:dim_encounter, [:public_report_id, :source_encounter_key],
        prefix: "gold",
        name: :dim_encounter_report_source_key_index,
        where: "public_report_id IS NOT NULL"
      )
    )
  end
end

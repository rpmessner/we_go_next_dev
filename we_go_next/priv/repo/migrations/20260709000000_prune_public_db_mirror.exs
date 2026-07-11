defmodule WeGoNext.Repo.Migrations.PrunePublicDbMirror do
  use Ecto.Migration

  def up do
    drop_if_exists(
      unique_index(:dim_encounter, [:public_report_id, :source_encounter_key],
        prefix: "gold",
        name: :dim_encounter_report_source_key_index
      )
    )

    drop_if_exists(
      unique_index(:dim_encounter, [:source_encounter_key],
        prefix: "gold",
        name: :dim_encounter_source_encounter_key_parser_index
      )
    )

    alter table(:dim_encounter, prefix: "gold") do
      remove(:public_report_id, references(:public_reports, prefix: "public", on_delete: :delete_all))
    end

    create(
      unique_index(:dim_encounter, [:source_encounter_key],
        prefix: "gold",
        name: :dim_encounter_source_encounter_key_parser_index
      )
    )
  end

  def down do
    drop_if_exists(
      unique_index(:dim_encounter, [:source_encounter_key],
        prefix: "gold",
        name: :dim_encounter_source_encounter_key_parser_index
      )
    )

    alter table(:dim_encounter, prefix: "gold") do
      add(:public_report_id, references(:public_reports, prefix: "public", on_delete: :delete_all))
    end

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

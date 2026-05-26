defmodule WeGoNext.Repo.Migrations.CreateSourceDataDbmTables do
  use Ecto.Migration

  def change do
    execute(
      "CREATE SCHEMA IF NOT EXISTS source_data",
      "DROP SCHEMA IF EXISTS source_data CASCADE"
    )

    create table(:source_import, prefix: "source_data") do
      add(:source_system, :string, null: false)
      add(:source_path, :text, null: false)
      add(:product, :string, null: false)
      add(:build_version, :string)
      add(:build_key, :string)
      add(:addon_revision, :string)
      add(:locale, :string)
      add(:content_hash, :string, null: false)
      add(:metadata, :map, null: false, default: %{})
      add(:imported_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:source_import, [:source_system, :source_path, :content_hash],
        prefix: "source_data",
        name: :source_import_identity_index
      )
    )

    create(index(:source_import, [:source_system], prefix: "source_data"))
    create(index(:source_import, [:content_hash], prefix: "source_data"))

    create table(:dbm_mechanic_candidate, prefix: "source_data") do
      add(
        :source_import_id,
        references(:source_import, prefix: "source_data", on_delete: :delete_all), null: false)

      add(:module_addon, :string)
      add(:module_id, :integer)
      add(:module_map_id, :integer)
      add(:module_revision, :string)
      add(:encounter_id, :integer)
      add(:zone_id, :integer)
      add(:creature_ids, {:array, :integer}, null: false, default: [])

      add(:warning_var, :string, null: false)
      add(:warning_constructor, :string, null: false)
      add(:spell_id, :integer, null: false)
      add(:role_filter, :string)
      add(:label_tokens, {:array, :string}, null: false, default: [])
      add(:alert_tokens, {:array, :string}, null: false, default: [])
      add(:inference_tags, {:array, :string}, null: false, default: [])
      add(:inferred_mechanic_type, :string)
      add(:confidence, :string, null: false, default: "low")
      add(:review_status, :string, null: false, default: "inferred")

      add(:source_file, :text, null: false)
      add(:source_line, :integer, null: false)
      add(:source_line_text, :text, null: false)
      add(:raw_args, :text, null: false)
      add(:comment, :text)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:dbm_mechanic_candidate, [:source_import_id], prefix: "source_data"))
    create(index(:dbm_mechanic_candidate, [:spell_id], prefix: "source_data"))
    create(index(:dbm_mechanic_candidate, [:encounter_id], prefix: "source_data"))
    create(index(:dbm_mechanic_candidate, [:inferred_mechanic_type], prefix: "source_data"))

    create(
      unique_index(:dbm_mechanic_candidate, [:source_import_id, :source_line, :warning_var],
        prefix: "source_data",
        name: :dbm_mechanic_candidate_source_line_index
      )
    )
  end
end

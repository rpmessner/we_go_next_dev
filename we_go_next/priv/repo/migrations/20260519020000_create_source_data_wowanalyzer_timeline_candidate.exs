defmodule WeGoNext.Repo.Migrations.CreateSourceDataWowAnalyzerTimelineCandidate do
  use Ecto.Migration

  def change do
    create table(:wowanalyzer_timeline_candidate, prefix: "source_data") do
      add(
        :source_import_id,
        references(:source_import, prefix: "source_data", on_delete: :delete_all),
        null: false
      )

      add(:raid_slug, :string, null: false)
      add(:raid_name, :string)
      add(:encounter_id, :integer, null: false)
      add(:encounter_name, :string, null: false)

      add(:timeline_type, :string, null: false)
      add(:event_type, :string, null: false)
      add(:spell_id, :integer, null: false)
      add(:boss_only, :boolean)
      add(:comment, :text)

      add(:inference_tags, {:array, :string}, null: false, default: [])
      add(:inferred_mechanic_type, :string)
      add(:confidence, :string, null: false, default: "low")
      add(:review_status, :string, null: false, default: "inferred")

      add(:repository_revision, :string, null: false)
      add(:repository_license, :string, null: false)
      add(:source_file, :text, null: false)
      add(:source_line, :integer, null: false)
      add(:source_line_text, :text, null: false)
      add(:raw_entry, :map, null: false, default: %{})

      add(:product, :string, null: false, default: "wow")
      add(:channel, :string, null: false, default: "retail")
      add(:build_version, :string)
      add(:build_key, :string)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:wowanalyzer_timeline_candidate, [:source_import_id], prefix: "source_data"))
    create(index(:wowanalyzer_timeline_candidate, [:spell_id], prefix: "source_data"))
    create(index(:wowanalyzer_timeline_candidate, [:encounter_id], prefix: "source_data"))

    create(
      index(:wowanalyzer_timeline_candidate, [:inferred_mechanic_type],
        prefix: "source_data",
        name: :wowanalyzer_timeline_candidate_mechanic_type_index
      )
    )

    create(
      index(:wowanalyzer_timeline_candidate, [:product, :channel, :build_key],
        prefix: "source_data",
        name: :wowanalyzer_timeline_candidate_build_scope_index
      )
    )

    create(
      unique_index(
        :wowanalyzer_timeline_candidate,
        [:source_import_id, :source_line, :timeline_type, :spell_id],
        prefix: "source_data",
        name: :wowanalyzer_timeline_candidate_source_line_index
      )
    )
  end
end

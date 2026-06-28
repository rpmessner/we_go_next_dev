defmodule WeGoNext.Repo.Migrations.CreateMirrorUploads do
  use Ecto.Migration

  def change do
    create table(:mirror_uploads) do
      add(:source_encounter_key, :string, null: false)
      add(:state, :string, null: false, default: "pending")
      add(:last_error, :text)
      add(:published_at, :utc_datetime_usec)
      add(:attempt_count, :integer, null: false, default: 0)
      add(:last_attempted_at, :utc_datetime_usec)
      add(:batch_id, :string)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:mirror_uploads, [:source_encounter_key]))
    create(index(:mirror_uploads, [:state, :updated_at]))
  end
end

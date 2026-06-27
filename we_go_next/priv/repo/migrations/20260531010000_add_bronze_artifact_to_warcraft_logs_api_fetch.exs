defmodule WeGoNext.Repo.Migrations.AddBronzeArtifactToWarcraftLogsApiFetch do
  use Ecto.Migration

  def change do
    alter table(:warcraft_logs_api_fetch, prefix: "source_data") do
      add(:artifact_path, :text, null: false)
      add(:artifact_hash, :string, null: false)
      add(:artifact_bytes, :bigint, null: false)
    end

    create(index(:warcraft_logs_api_fetch, [:artifact_hash], prefix: "source_data"))
  end
end

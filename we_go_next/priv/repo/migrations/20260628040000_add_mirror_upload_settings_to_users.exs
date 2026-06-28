defmodule WeGoNext.Repo.Migrations.AddMirrorUploadSettingsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:mirror_public_base_url, :text)
      add(:mirror_ingest_token_encrypted, :text)
      add(:mirror_ingest_token_set_at, :utc_datetime_usec)
    end
  end
end

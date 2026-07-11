defmodule WeGoNext.Repo.Migrations.ReplaceMirrorUploadSettingsWithDocumentR2Credentials do
  use Ecto.Migration

  def change do
    alter table(:users) do
      remove(:mirror_public_base_url, :text)
      remove(:mirror_ingest_token_encrypted, :text)
      remove(:mirror_ingest_token_set_at, :utc_datetime_usec)

      add(:document_r2_endpoint, :text)
      add(:document_r2_bucket, :text)
      add(:document_r2_access_key_id, :text)
      add(:document_r2_secret_access_key_encrypted, :text)
      add(:document_r2_secret_access_key_set_at, :utc_datetime_usec)
    end
  end
end

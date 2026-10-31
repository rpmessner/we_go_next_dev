defmodule WeGoNext.Repo.Migrations.RemovePublicMirror do
  use Ecto.Migration

  def change do
    drop(table(:mirror_uploads))
    drop(table(:public_reports))

    alter table(:combat_log_files) do
      remove(:publish_enabled, :boolean, null: false, default: false)
    end

    alter table(:users) do
      remove(:document_r2_endpoint, :text)
      remove(:document_r2_bucket, :text)
      remove(:document_r2_access_key_id, :text)
      remove(:document_r2_secret_access_key_encrypted, :text)
      remove(:document_r2_secret_access_key_set_at, :utc_datetime_usec)
    end
  end
end

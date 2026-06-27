defmodule WeGoNext.Repo.Migrations.AddWarcraftLogsCredentialsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:warcraft_logs_client_name, :string)
      add(:warcraft_logs_api_key_encrypted, :text)
      add(:warcraft_logs_api_key_set_at, :utc_datetime_usec)
    end
  end
end

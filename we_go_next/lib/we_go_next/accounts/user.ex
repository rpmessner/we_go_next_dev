defmodule WeGoNext.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field(:name, :string, default: "default")
    field(:wow_logs_path, :string)
    field(:last_loaded_log, :string)
    field(:character_name, :string)
    field(:warcraft_logs_client_name, :string)
    field(:warcraft_logs_api_key_encrypted, :string)
    field(:warcraft_logs_api_key_set_at, :utc_datetime_usec)
    field(:document_r2_endpoint, :string)
    field(:document_r2_bucket, :string)
    field(:document_r2_access_key_id, :string)
    field(:document_r2_secret_access_key_encrypted, :string)
    field(:document_r2_secret_access_key_set_at, :utc_datetime_usec)
    field(:is_admin, :boolean, default: false)

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :wow_logs_path, :last_loaded_log, :character_name])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end

  def settings_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :wow_logs_path,
      :last_loaded_log,
      :character_name,
      :warcraft_logs_client_name,
      :warcraft_logs_api_key_encrypted,
      :warcraft_logs_api_key_set_at,
      :document_r2_endpoint,
      :document_r2_bucket,
      :document_r2_access_key_id,
      :document_r2_secret_access_key_encrypted,
      :document_r2_secret_access_key_set_at
    ])
  end
end

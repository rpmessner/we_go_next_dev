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
    field(:mirror_public_base_url, :string)
    field(:mirror_ingest_token_encrypted, :string)
    field(:mirror_ingest_token_set_at, :utc_datetime_usec)
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
      :mirror_public_base_url,
      :mirror_ingest_token_encrypted,
      :mirror_ingest_token_set_at
    ])
  end
end

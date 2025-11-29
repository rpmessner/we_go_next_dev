defmodule WeGoNext.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string, default: "default"
    field :wow_logs_path, :string
    field :last_loaded_log, :string
    field :is_admin, :boolean, default: false

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :wow_logs_path, :last_loaded_log])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end

  def settings_changeset(user, attrs) do
    user
    |> cast(attrs, [:wow_logs_path, :last_loaded_log])
  end
end

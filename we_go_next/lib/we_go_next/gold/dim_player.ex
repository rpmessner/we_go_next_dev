defmodule WeGoNext.Gold.DimPlayer do
  @moduledoc """
  Gold dimension row for a player.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @schema_prefix "gold"

  schema "dim_player" do
    field(:player_guid, :string)
    field(:player_name, :string)
    field(:class_id, :integer)
    field(:spec_id, :integer)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(dim_player, attrs) do
    dim_player
    |> cast(attrs, [:player_guid, :player_name, :class_id, :spec_id])
    |> validate_required([:player_guid, :player_name])
    |> unique_constraint(:player_guid)
  end
end

defmodule WeGoNext.Gold.DimPlayer do
  @moduledoc """
  Gold dimension row for a player.
  """

  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset

  alias WeGoNext.Repo
  alias WeGoNext.Silver.PlayerInfo

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

  @doc """
  Upserts gold player dimension rows from silver player info for an encounter.

  Existing rows are updated in-place by `player_guid` using Type 1 dimension
  behavior for mutable player metadata.
  """
  @spec upsert_from_silver(pos_integer()) :: {non_neg_integer(), nil | [term()]}
  def upsert_from_silver(encounter_dim_id) when is_integer(encounter_dim_id) do
    now = DateTime.utc_now()

    rows =
      from(player_info in PlayerInfo,
        where: player_info.encounter_dim_id == ^encounter_dim_id,
        select: %{
          player_guid: player_info.player_guid,
          player_name: player_info.player_name,
          class_id: player_info.class_id,
          spec_id: player_info.spec_id,
          inserted_at: ^now,
          updated_at: ^now
        }
      )

    Repo.insert_all(__MODULE__, rows,
      on_conflict: {:replace, [:player_name, :class_id, :spec_id, :updated_at]},
      conflict_target: [:player_guid]
    )
  end
end

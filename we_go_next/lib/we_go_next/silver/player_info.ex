defmodule WeGoNext.Silver.PlayerInfo do
  @moduledoc """
  Silver projection row for encounter-scoped player metadata.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.Encounters.Encounter

  @detected_roles ~w(tank healer dps unknown)

  @schema_prefix "silver"

  schema "player_info" do
    field(:player_guid, :string)
    field(:player_name, :string)
    field(:class_id, :integer)
    field(:spec_id, :integer)
    field(:item_level, :integer)
    field(:detected_role, :string, default: "unknown")

    belongs_to(:encounter, Encounter)

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @doc false
  def changeset(player_info, attrs) do
    player_info
    |> cast(attrs, [
      :encounter_id,
      :player_guid,
      :player_name,
      :class_id,
      :spec_id,
      :item_level,
      :detected_role
    ])
    |> validate_required([:encounter_id, :player_guid, :player_name, :detected_role])
    |> validate_inclusion(:detected_role, @detected_roles)
    |> unique_constraint([:encounter_id, :player_guid], name: :silver_player_info_natural_key)
    |> check_constraint(:detected_role, name: :silver_player_info_detected_role_check)
  end

  def detected_roles, do: @detected_roles
end

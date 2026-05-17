defmodule WeGoNext.Silver.DamageDone do
  @moduledoc """
  Silver projection row for damage done by a player to a target and spell.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.Gold.DimEncounter

  @schema_prefix "silver"

  schema "damage_done" do
    field(:source_guid, :string)
    field(:target_guid, :string)
    field(:spell_id, :integer)
    field(:total_amount, :integer, default: 0)
    field(:hit_count, :integer, default: 0)
    field(:max_hit, :integer, default: 0)

    belongs_to(:encounter, DimEncounter, foreign_key: :encounter_dim_id)

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @doc false
  def changeset(damage_done, attrs) do
    damage_done
    |> cast(attrs, [
      :encounter_dim_id,
      :source_guid,
      :target_guid,
      :spell_id,
      :total_amount,
      :hit_count,
      :max_hit
    ])
    |> validate_required([
      :encounter_dim_id,
      :source_guid,
      :target_guid,
      :spell_id,
      :total_amount,
      :hit_count,
      :max_hit
    ])
    |> unique_constraint([:encounter_dim_id, :source_guid, :target_guid, :spell_id],
      name: :silver_damage_done_natural_key
    )
  end
end

defmodule WeGoNext.Silver.DamageTaken do
  @moduledoc """
  Silver projection row for damage taken by a player from a source and spell.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.Encounters.Encounter

  @schema_prefix "silver"

  schema "damage_taken" do
    field(:target_guid, :string)
    field(:source_guid, :string)
    field(:spell_id, :integer)
    field(:total_amount, :integer, default: 0)
    field(:hit_count, :integer, default: 0)
    field(:max_hit, :integer, default: 0)
    field(:overkill_total, :integer, default: 0)
    field(:source_is_npc, :boolean, default: false)

    belongs_to(:encounter, Encounter)

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @doc false
  def changeset(damage_taken, attrs) do
    damage_taken
    |> cast(attrs, [
      :encounter_id,
      :target_guid,
      :source_guid,
      :spell_id,
      :total_amount,
      :hit_count,
      :max_hit,
      :overkill_total,
      :source_is_npc
    ])
    |> validate_required([
      :encounter_id,
      :target_guid,
      :source_guid,
      :spell_id,
      :total_amount,
      :hit_count,
      :max_hit,
      :overkill_total,
      :source_is_npc
    ])
    |> unique_constraint([:encounter_id, :target_guid, :source_guid, :spell_id],
      name: :silver_damage_taken_natural_key
    )
  end
end

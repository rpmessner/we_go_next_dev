defmodule WeGoNext.Silver.Death do
  @moduledoc """
  Silver projection row for a player death and its damage recap.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.Encounters.Encounter

  @schema_prefix "silver"

  schema "death" do
    field(:target_guid, :string)
    field(:died_at_ms_into_fight, :integer)
    field(:killing_blow_spell_id, :integer)
    field(:killing_blow_source_guid, :string)
    field(:damage_recap, {:array, :map}, default: [])

    belongs_to(:encounter, Encounter)

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @doc false
  def changeset(death, attrs) do
    death
    |> cast(attrs, [
      :encounter_id,
      :target_guid,
      :died_at_ms_into_fight,
      :killing_blow_spell_id,
      :killing_blow_source_guid,
      :damage_recap
    ])
    |> validate_required([:encounter_id, :target_guid, :died_at_ms_into_fight, :damage_recap])
    |> unique_constraint([:encounter_id, :target_guid, :died_at_ms_into_fight],
      name: :silver_death_natural_key
    )
  end
end

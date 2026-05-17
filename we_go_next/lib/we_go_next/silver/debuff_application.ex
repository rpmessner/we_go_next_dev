defmodule WeGoNext.Silver.DebuffApplication do
  @moduledoc """
  Silver projection row for a debuff application on a player.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.Encounters.Encounter

  @schema_prefix "silver"

  schema "debuff_application" do
    field(:target_guid, :string)
    field(:source_guid, :string)
    field(:spell_id, :integer)
    field(:applied_at_ms_into_fight, :integer)
    field(:duration_ms, :integer)
    field(:stack_count, :integer, default: 1)

    belongs_to(:encounter, Encounter)

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @doc false
  def changeset(debuff_application, attrs) do
    debuff_application
    |> cast(attrs, [
      :encounter_id,
      :target_guid,
      :source_guid,
      :spell_id,
      :applied_at_ms_into_fight,
      :duration_ms,
      :stack_count
    ])
    |> validate_required([
      :encounter_id,
      :target_guid,
      :source_guid,
      :spell_id,
      :applied_at_ms_into_fight,
      :stack_count
    ])
    |> unique_constraint(
      [:encounter_id, :target_guid, :source_guid, :spell_id, :applied_at_ms_into_fight],
      name: :silver_debuff_application_natural_key
    )
  end
end

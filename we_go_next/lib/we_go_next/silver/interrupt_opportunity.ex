defmodule WeGoNext.Silver.InterruptOpportunity do
  @moduledoc """
  Silver projection row for a successful or missed interrupt opportunity.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.Encounters.Encounter

  @schema_prefix "silver"

  schema "interrupt_opportunity" do
    field(:target_npc_guid, :string)
    field(:interrupted_spell_id, :integer)
    field(:opportunity_ms_into_fight, :integer)
    field(:success, :boolean)
    field(:interrupter_guid, :string)
    field(:interrupting_spell_id, :integer)

    belongs_to(:encounter, Encounter)

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @doc false
  def changeset(interrupt_opportunity, attrs) do
    interrupt_opportunity
    |> cast(attrs, [
      :encounter_id,
      :target_npc_guid,
      :interrupted_spell_id,
      :opportunity_ms_into_fight,
      :success,
      :interrupter_guid,
      :interrupting_spell_id
    ])
    |> validate_required([
      :encounter_id,
      :target_npc_guid,
      :interrupted_spell_id,
      :opportunity_ms_into_fight,
      :success
    ])
    |> unique_constraint(
      [:encounter_id, :target_npc_guid, :interrupted_spell_id, :opportunity_ms_into_fight],
      name: :silver_interrupt_opportunity_natural_key
    )
  end
end

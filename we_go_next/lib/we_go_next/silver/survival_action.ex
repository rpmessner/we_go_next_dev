defmodule WeGoNext.Silver.SurvivalAction do
  @moduledoc """
  Silver usage-grain row: one catalog-gated survival action use per event.

  Covers defensive casts, healthstones, and health potions from
  `WeGoNext.GameData.SurvivalActions`. Rows are target-aware: `caster_guid` is
  the player who pressed the button and `target_guid` is the player who
  received the effect, so externals cast on other players are captured.
  Consumable rows carry the joined heal amount/overheal when the resulting
  `SPELL_HEAL` was observed.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.Gold.DimEncounter

  @schema_prefix "silver"

  schema "survival_action" do
    field(:caster_guid, :string)
    field(:target_guid, :string)
    field(:spell_id, :integer)
    field(:spell_name, :string)
    field(:kind, :string)
    field(:category, :string)
    field(:used_at_ms_into_fight, :integer)
    field(:heal_amount, :integer)
    field(:overheal_amount, :integer)

    belongs_to(:encounter, DimEncounter, foreign_key: :encounter_dim_id)

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @doc false
  def changeset(survival_action, attrs) do
    survival_action
    |> cast(attrs, [
      :encounter_dim_id,
      :caster_guid,
      :target_guid,
      :spell_id,
      :spell_name,
      :kind,
      :category,
      :used_at_ms_into_fight,
      :heal_amount,
      :overheal_amount
    ])
    |> validate_required([
      :encounter_dim_id,
      :caster_guid,
      :target_guid,
      :spell_id,
      :spell_name,
      :kind,
      :category,
      :used_at_ms_into_fight
    ])
    |> validate_number(:heal_amount, greater_than_or_equal_to: 0)
    |> validate_number(:overheal_amount, greater_than_or_equal_to: 0)
    |> unique_constraint(
      [
        :encounter_dim_id,
        :caster_guid,
        :target_guid,
        :spell_id,
        :used_at_ms_into_fight
      ],
      name: :silver_survival_action_natural_key
    )
  end
end

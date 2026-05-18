defmodule WeGoNext.Silver.DamageTakenEvent do
  @moduledoc """
  Event-grain silver observation for a single damage-taken hit.

  This table is intentionally narrower than a raw combat-log warehouse. It keeps
  only player damage-taken events needed for rule review, candidate matching, and
  future failure classifiers that need to inspect individual hits instead of only
  aggregate player/source/spell totals.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.Gold.DimEncounter

  @schema_prefix "silver"

  schema "damage_taken_event" do
    field(:combat_log_event_index, :integer)
    field(:event_type, :string)
    field(:occurred_at_ms_into_fight, :integer)
    field(:timestamp, :string)
    field(:target_guid, :string)
    field(:target_name, :string)
    field(:source_guid, :string)
    field(:source_name, :string)
    field(:source_is_npc, :boolean, default: false)
    field(:spell_id, :integer)
    field(:spell_name, :string)
    field(:spell_school, :integer)
    field(:amount, :integer, default: 0)
    field(:overkill, :integer, default: 0)

    belongs_to(:encounter, DimEncounter, foreign_key: :encounter_dim_id)

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @doc false
  def changeset(damage_taken_event, attrs) do
    damage_taken_event
    |> cast(attrs, [
      :encounter_dim_id,
      :combat_log_event_index,
      :event_type,
      :occurred_at_ms_into_fight,
      :timestamp,
      :target_guid,
      :target_name,
      :source_guid,
      :source_name,
      :source_is_npc,
      :spell_id,
      :spell_name,
      :spell_school,
      :amount,
      :overkill
    ])
    |> validate_required([
      :encounter_dim_id,
      :combat_log_event_index,
      :event_type,
      :occurred_at_ms_into_fight,
      :target_guid,
      :source_guid,
      :source_is_npc,
      :spell_id,
      :amount,
      :overkill
    ])
    |> unique_constraint([:encounter_dim_id, :combat_log_event_index],
      name: :silver_damage_taken_event_natural_key
    )
  end
end

defmodule WeGoNext.Silver.DefensiveBuffWindow do
  @moduledoc """
  Silver projection row for known player defensive cooldown buff windows.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.Gold.DimEncounter

  @schema_prefix "silver"

  schema "defensive_buff_window" do
    field(:target_guid, :string)
    field(:source_guid, :string)
    field(:spell_id, :integer)
    field(:spell_name, :string)
    field(:category, :string)
    field(:started_at_ms_into_fight, :integer)
    field(:ended_at_ms_into_fight, :integer)
    field(:duration_ms, :integer)

    belongs_to(:encounter, DimEncounter, foreign_key: :encounter_dim_id)

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @doc false
  def changeset(defensive_buff_window, attrs) do
    defensive_buff_window
    |> cast(attrs, [
      :encounter_dim_id,
      :target_guid,
      :source_guid,
      :spell_id,
      :spell_name,
      :category,
      :started_at_ms_into_fight,
      :ended_at_ms_into_fight,
      :duration_ms
    ])
    |> validate_required([
      :encounter_dim_id,
      :target_guid,
      :source_guid,
      :spell_id,
      :spell_name,
      :category,
      :started_at_ms_into_fight
    ])
    |> validate_number(:duration_ms, greater_than_or_equal_to: 0)
    |> unique_constraint(
      [
        :encounter_dim_id,
        :target_guid,
        :source_guid,
        :spell_id,
        :started_at_ms_into_fight
      ],
      name: :silver_defensive_buff_window_natural_key
    )
  end
end

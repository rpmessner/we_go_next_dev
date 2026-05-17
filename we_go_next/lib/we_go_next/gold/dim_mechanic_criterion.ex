defmodule WeGoNext.Gold.DimMechanicCriterion do
  @moduledoc """
  Gold dimension row for mechanic failure criteria.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @mechanic_types ~w(avoidable interrupt soak spread stack tank_mechanic healer_mechanic)

  @schema_prefix "gold"

  schema "dim_mechanic_criterion" do
    field(:spell_id, :integer)
    field(:spell_name, :string)
    field(:mechanic_type, :string)
    field(:boss_encounter_id, :string)
    field(:boss_name, :string)
    field(:difficulty_id, :integer)
    field(:threshold, :map, default: %{})
    field(:notes, :string)
    field(:active, :boolean, default: true)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(dim_criterion, attrs) do
    dim_criterion
    |> cast(attrs, [
      :spell_id,
      :spell_name,
      :mechanic_type,
      :boss_encounter_id,
      :boss_name,
      :difficulty_id,
      :threshold,
      :notes,
      :active
    ])
    |> validate_required([:spell_id, :spell_name, :mechanic_type, :threshold, :active])
    |> validate_inclusion(:mechanic_type, @mechanic_types)
  end

  def mechanic_types, do: @mechanic_types
end

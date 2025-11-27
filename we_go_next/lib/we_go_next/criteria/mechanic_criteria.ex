defmodule WeGoNext.Criteria.MechanicCriteria do
  @moduledoc """
  Ecto schema for mechanic criteria - defines what abilities to track and how to identify failures.

  Mechanic types:
  - :avoidable - Damage that players should avoid (standing in fire)
  - :interrupt - Casts that must be interrupted
  - :soak - Damage that needs to be shared/soaked
  - :spread - Debuffs requiring players to spread out
  - :stack - Mechanics requiring players to group up
  - :tank_mechanic - Tank-specific mechanics (swaps, positioning)
  - :healer_mechanic - Mechanics requiring healing response
  """
  use Ecto.Schema
  import Ecto.Changeset

  @mechanic_types ~w(avoidable interrupt soak spread stack tank_mechanic healer_mechanic)

  schema "mechanic_criteria" do
    field :spell_id, :integer
    field :spell_name, :string
    field :mechanic_type, :string
    field :boss_encounter_id, :string
    field :boss_name, :string
    field :threshold, :map, default: %{}
    field :notes, :string
    field :active, :boolean, default: true

    timestamps()
  end

  @doc false
  def changeset(criteria, attrs) do
    criteria
    |> cast(attrs, [
      :spell_id,
      :spell_name,
      :mechanic_type,
      :boss_encounter_id,
      :boss_name,
      :threshold,
      :notes,
      :active
    ])
    |> validate_required([:spell_id, :spell_name, :mechanic_type])
    |> validate_inclusion(:mechanic_type, @mechanic_types)
    |> unique_constraint([:spell_id, :boss_encounter_id], name: :mechanic_criteria_spell_boss_unique)
  end

  @doc """
  Returns all valid mechanic types.
  """
  def mechanic_types, do: @mechanic_types

  @doc """
  Returns a human-readable label for a mechanic type.
  """
  def type_label("avoidable"), do: "Avoidable Damage"
  def type_label("interrupt"), do: "Must Interrupt"
  def type_label("soak"), do: "Soak Mechanic"
  def type_label("spread"), do: "Spread Out"
  def type_label("stack"), do: "Stack Up"
  def type_label("tank_mechanic"), do: "Tank Mechanic"
  def type_label("healer_mechanic"), do: "Healer Mechanic"
  def type_label(_), do: "Unknown"

  @doc """
  Returns the CSS color class for a mechanic type.
  """
  def type_color("avoidable"), do: "text-red-400"
  def type_color("interrupt"), do: "text-yellow-400"
  def type_color("soak"), do: "text-blue-400"
  def type_color("spread"), do: "text-purple-400"
  def type_color("stack"), do: "text-green-400"
  def type_color("tank_mechanic"), do: "text-wow-tank"
  def type_color("healer_mechanic"), do: "text-wow-healer"
  def type_color(_), do: "text-zinc-400"

  @doc """
  Checks if an event matches this criteria's failure condition.

  Returns {:failure, reason} or :ok
  """
  def check_failure(%__MODULE__{mechanic_type: "avoidable", threshold: threshold}, hit_count) do
    max_hits = Map.get(threshold, "max_hits", 0)

    if hit_count > max_hits do
      {:failure, "took #{hit_count} hit(s), max allowed: #{max_hits}"}
    else
      :ok
    end
  end

  def check_failure(%__MODULE__{mechanic_type: "interrupt"}, cast_completed?) do
    if cast_completed? do
      {:failure, "cast was not interrupted"}
    else
      :ok
    end
  end

  def check_failure(%__MODULE__{}, _), do: :ok
end

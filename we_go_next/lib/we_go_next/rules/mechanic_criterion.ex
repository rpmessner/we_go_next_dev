defmodule WeGoNext.Rules.MechanicCriterion do
  @moduledoc """
  Authored mechanic rule criterion.

  These rows are business configuration owned by the rules layer. They are not
  silver event data and are not gold fact snapshots until promoted.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.Rules.Ruleset

  @mechanic_types ~w(avoidable interrupt soak spread stack tank_mechanic healer_mechanic)

  @schema_prefix "rules"

  schema "mechanic_criterion" do
    field(:spell_id, :integer)
    field(:spell_name, :string)
    field(:mechanic_type, :string)
    field(:boss_encounter_id, :string)
    field(:boss_name, :string)
    field(:difficulty_id, :integer)
    field(:threshold, :map, default: %{})
    field(:notes, :string)
    field(:active, :boolean, default: true)

    belongs_to(:ruleset, Ruleset)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(mechanic_criterion, attrs) do
    mechanic_criterion
    |> cast(attrs, [
      :ruleset_id,
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
    |> normalize_interrupt_threshold()
    |> validate_required([
      :ruleset_id,
      :spell_id,
      :spell_name,
      :mechanic_type,
      :threshold,
      :active
    ])
    |> validate_inclusion(:mechanic_type, @mechanic_types)
    |> validate_threshold()
    |> foreign_key_constraint(:ruleset_id)
    |> unique_constraint([:ruleset_id, :spell_id, :boss_encounter_id, :difficulty_id],
      name: :mechanic_criterion_ruleset_spell_scope_index
    )
  end

  def mechanic_types, do: @mechanic_types

  defp normalize_interrupt_threshold(changeset) do
    if get_field(changeset, :mechanic_type) == "interrupt" and
         get_field(changeset, :threshold) in [
           nil,
           %{}
         ] do
      put_change(changeset, :threshold, %{"must_interrupt" => true})
    else
      changeset
    end
  end

  defp validate_threshold(changeset) do
    case {get_field(changeset, :mechanic_type), get_field(changeset, :threshold)} do
      {"avoidable", threshold} ->
        validate_avoidable_threshold(changeset, threshold)

      {"interrupt", threshold} ->
        validate_interrupt_threshold(changeset, threshold)

      {type, threshold}
      when type in ~w(soak spread stack tank_mechanic healer_mechanic) ->
        validate_empty_threshold(changeset, threshold)

      _ ->
        changeset
    end
  end

  defp validate_avoidable_threshold(changeset, %{"max_hits" => max_hits} = threshold)
       when map_size(threshold) == 1 and is_integer(max_hits) and max_hits >= 0,
       do: changeset

  defp validate_avoidable_threshold(changeset, _threshold) do
    add_error(changeset, :threshold, "must contain only max_hits as a non-negative integer")
  end

  defp validate_interrupt_threshold(changeset, %{"must_interrupt" => must_interrupt} = threshold)
       when map_size(threshold) == 1 and is_boolean(must_interrupt),
       do: changeset

  defp validate_interrupt_threshold(changeset, _threshold) do
    add_error(changeset, :threshold, "must contain only must_interrupt as a boolean")
  end

  defp validate_empty_threshold(changeset, threshold) when threshold in [nil, %{}], do: changeset

  defp validate_empty_threshold(changeset, _threshold) do
    add_error(changeset, :threshold, "must be empty until this mechanic type has fact semantics")
  end
end

defmodule WeGoNext.Gold.DimMechanicCriterion do
  @moduledoc "Live mechanics catalog and stable key dimension for failure facts."
  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.Mechanics.{CriterionThreshold, Taxonomy}
  alias WeGoNext.Mirror.Keys

  @schema_prefix "gold"
  schema "dim_mechanic_criterion" do
    field(:criterion_key, :string)
    field(:product, :string, default: "wow")
    field(:channel, :string, default: "retail")
    field(:build_version, :string)
    field(:build_key, :string)
    field(:spell_id, :integer)
    field(:spell_name, :string)
    field(:mechanic_type, :string)
    field(:boss_encounter_id, :string)
    field(:boss_name, :string)
    field(:difficulty_id, :integer)
    field(:threshold, :map, default: %{})
    field(:notes, :string)
    field(:active, :boolean, default: true)
    field(:valid_from, :utc_datetime_usec)
    field(:valid_until, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(criterion, attrs) do
    criterion
    |> cast(attrs, [
      :criterion_key,
      :product,
      :channel,
      :build_version,
      :build_key,
      :spell_id,
      :spell_name,
      :mechanic_type,
      :boss_encounter_id,
      :boss_name,
      :difficulty_id,
      :threshold,
      :notes,
      :active,
      :valid_from,
      :valid_until
    ])
    |> CriterionThreshold.validate()
    |> put_criterion_key()
    |> validate_required([
      :criterion_key,
      :product,
      :channel,
      :spell_id,
      :spell_name,
      :mechanic_type,
      :threshold,
      :active
    ])
    |> validate_inclusion(:mechanic_type, Taxonomy.rule_types())
    |> validate_window()
    |> unique_constraint(:criterion_key)
  end

  def mechanic_types, do: Taxonomy.rule_types()

  defp validate_window(changeset) do
    case {get_field(changeset, :valid_from), get_field(changeset, :valid_until)} do
      {%DateTime{} = from, %DateTime{} = until} ->
        if DateTime.compare(from, until) == :lt,
          do: changeset,
          else: add_error(changeset, :valid_until, "must be after valid_from")

      _ ->
        changeset
    end
  end

  defp put_criterion_key(changeset) do
    fields =
      Map.new(
        [
          :product,
          :channel,
          :build_key,
          :boss_encounter_id,
          :difficulty_id,
          :spell_id,
          :mechanic_type,
          :threshold,
          :valid_from,
          :valid_until
        ],
        &{&1, get_field(changeset, &1)}
      )

    if get_field(changeset, :criterion_key) ||
         Enum.any?(
           [
             fields.product,
             fields.channel,
             fields.spell_id,
             fields.mechanic_type,
             fields.threshold
           ],
           &is_nil/1
         ) do
      changeset
    else
      put_change(changeset, :criterion_key, Keys.criterion_key(fields))
    end
  end
end

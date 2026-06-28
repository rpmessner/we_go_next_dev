defmodule WeGoNext.Gold.DimMechanicCriterion do
  @moduledoc """
  Gold dimension row for mechanic failure criteria.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.Mirror.Keys

  @mechanic_types ~w(avoidable interrupt soak spread stack tank_mechanic healer_mechanic targeted_cone)

  @schema_prefix "gold"

  schema "dim_mechanic_criterion" do
    field(:criterion_key, :string)
    field(:source_rule_id, :integer)
    field(:ruleset_id, :integer)
    field(:ruleset_version, :integer)
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

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(dim_criterion, attrs) do
    dim_criterion
    |> cast(attrs, [
      :source_rule_id,
      :criterion_key,
      :ruleset_id,
      :ruleset_version,
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
      :active
    ])
    |> put_criterion_key()
    |> validate_required([
      :criterion_key,
      :source_rule_id,
      :ruleset_id,
      :ruleset_version,
      :product,
      :channel,
      :spell_id,
      :spell_name,
      :mechanic_type,
      :threshold,
      :active
    ])
    |> validate_inclusion(:mechanic_type, @mechanic_types)
    |> validate_number(:ruleset_version, greater_than: 0)
    |> unique_constraint(:source_rule_id)
    |> unique_constraint(:criterion_key)
  end

  @doc false
  def mirror_changeset(dim_criterion, attrs) do
    dim_criterion
    |> cast(attrs, [
      :criterion_key,
      :ruleset_id,
      :ruleset_version,
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
      :active
    ])
    |> put_criterion_key()
    |> validate_required([
      :criterion_key,
      :ruleset_id,
      :ruleset_version,
      :product,
      :channel,
      :spell_id,
      :spell_name,
      :mechanic_type,
      :threshold,
      :active
    ])
    |> validate_inclusion(:mechanic_type, @mechanic_types)
    |> validate_number(:ruleset_version, greater_than: 0)
    |> unique_constraint(:criterion_key)
  end

  def mechanic_types, do: @mechanic_types

  defp put_criterion_key(changeset) do
    if get_field(changeset, :criterion_key) do
      changeset
    else
      fields = fields_for_key(changeset)

      if key_ready?(fields) do
        put_change(changeset, :criterion_key, Keys.criterion_key(fields))
      else
        changeset
      end
    end
  end

  defp fields_for_key(changeset) do
    %{
      product: get_field(changeset, :product),
      channel: get_field(changeset, :channel),
      build_key: get_field(changeset, :build_key),
      boss_encounter_id: get_field(changeset, :boss_encounter_id),
      difficulty_id: get_field(changeset, :difficulty_id),
      spell_id: get_field(changeset, :spell_id),
      mechanic_type: get_field(changeset, :mechanic_type),
      threshold: get_field(changeset, :threshold)
    }
  end

  defp key_ready?(fields) do
    fields.product && fields.channel && fields.spell_id && fields.mechanic_type &&
      fields.threshold
  end
end

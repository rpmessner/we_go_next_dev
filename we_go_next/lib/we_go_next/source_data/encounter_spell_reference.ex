defmodule WeGoNext.SourceData.EncounterSpellReference do
  @moduledoc """
  Build-scoped source-data relationship between an encounter and a spell.

  These rows are evidence for candidate review. They do not imply an active rule
  or a gold fact by themselves.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.SourceData.SourceImport

  @schema_prefix "source_data"

  schema "encounter_spell_reference" do
    belongs_to(:source_import, SourceImport)

    field(:encounter_id, :integer)
    field(:spell_id, :integer)
    field(:difficulty_id, :integer, default: 0)
    field(:relationship_type, :string, default: "mechanic")

    field(:product, :string)
    field(:channel, :string, default: "retail")
    field(:build_version, :string)
    field(:build_key, :string)
    field(:locale, :string, default: "enUS")

    field(:source_system, :string)
    field(:source_priority, :integer, default: 100)
    field(:metadata, :map, default: %{})

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(encounter_spell_reference, attrs) do
    encounter_spell_reference
    |> cast(attrs, [
      :source_import_id,
      :encounter_id,
      :spell_id,
      :difficulty_id,
      :relationship_type,
      :product,
      :channel,
      :build_version,
      :build_key,
      :locale,
      :source_system,
      :source_priority,
      :metadata
    ])
    |> validate_required([
      :encounter_id,
      :spell_id,
      :difficulty_id,
      :relationship_type,
      :product,
      :channel,
      :build_key,
      :locale,
      :source_system,
      :source_priority,
      :metadata
    ])
    |> validate_number(:difficulty_id, greater_than_or_equal_to: 0)
    |> validate_number(:source_priority, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:source_import_id)
    |> unique_constraint(
      [
        :encounter_id,
        :spell_id,
        :difficulty_id,
        :relationship_type,
        :product,
        :channel,
        :build_key,
        :locale,
        :source_system
      ],
      name: :encounter_spell_reference_identity_index
    )
  end
end

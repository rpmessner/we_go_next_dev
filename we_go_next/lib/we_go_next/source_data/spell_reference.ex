defmodule WeGoNext.SourceData.SpellReference do
  @moduledoc """
  Build-scoped spell reference row promoted from external source data.

  Lower `source_priority` values win lookups when multiple source systems provide
  metadata for the same product, channel, build, locale, and spell id.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.SourceData.SourceImport

  @schema_prefix "source_data"

  schema "spell_reference" do
    belongs_to(:source_import, SourceImport)

    field(:spell_id, :integer)
    field(:current_name, :string)
    field(:localized_names, :map, default: %{})

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
  def changeset(spell_reference, attrs) do
    spell_reference
    |> cast(attrs, [
      :source_import_id,
      :spell_id,
      :current_name,
      :localized_names,
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
      :spell_id,
      :current_name,
      :localized_names,
      :product,
      :channel,
      :build_key,
      :locale,
      :source_system,
      :source_priority,
      :metadata
    ])
    |> validate_number(:source_priority, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:source_import_id)
    |> unique_constraint([:spell_id, :product, :channel, :build_key, :locale, :source_system],
      name: :spell_reference_identity_index
    )
  end
end

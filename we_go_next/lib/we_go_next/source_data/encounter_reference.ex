defmodule WeGoNext.SourceData.EncounterReference do
  @moduledoc """
  Build-scoped encounter reference row promoted from external source data.

  This is encounter metadata, not pull-grain analytics. Pulls remain keyed by
  `gold.dim_encounter.id`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.SourceData.SourceImport

  @schema_prefix "source_data"

  schema "encounter_reference" do
    belongs_to(:source_import, SourceImport)

    field(:encounter_id, :integer)
    field(:current_name, :string)
    field(:localized_names, :map, default: %{})
    field(:zone_id, :integer)
    field(:zone_name, :string)
    field(:instance_id, :integer)
    field(:instance_name, :string)

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
  def changeset(encounter_reference, attrs) do
    encounter_reference
    |> cast(attrs, [
      :source_import_id,
      :encounter_id,
      :current_name,
      :localized_names,
      :zone_id,
      :zone_name,
      :instance_id,
      :instance_name,
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
    |> unique_constraint(
      [:encounter_id, :product, :channel, :build_key, :locale, :source_system],
      name: :encounter_reference_identity_index
    )
  end
end

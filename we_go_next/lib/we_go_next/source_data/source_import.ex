defmodule WeGoNext.SourceData.SourceImport do
  @moduledoc """
  Versioned source-data import record.

  These records describe non-combat-log source inputs such as DBM addon modules
  or future game-data extracts. They are intentionally separate from
  `combat_log_files`, which remains the operational catalog for raw combat logs.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @schema_prefix "source_data"

  schema "source_import" do
    field(:source_system, :string)
    field(:source_path, :string)
    field(:product, :string)
    field(:build_version, :string)
    field(:build_key, :string)
    field(:addon_revision, :string)
    field(:locale, :string)
    field(:content_hash, :string)
    field(:metadata, :map, default: %{})
    field(:imported_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(source_import, attrs) do
    source_import
    |> cast(attrs, [
      :source_system,
      :source_path,
      :product,
      :build_version,
      :build_key,
      :addon_revision,
      :locale,
      :content_hash,
      :metadata,
      :imported_at
    ])
    |> validate_required([
      :source_system,
      :source_path,
      :product,
      :content_hash,
      :metadata,
      :imported_at
    ])
    |> unique_constraint([:source_system, :source_path, :content_hash],
      name: :source_import_identity_index
    )
  end
end

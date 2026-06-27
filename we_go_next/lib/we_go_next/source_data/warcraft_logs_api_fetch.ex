defmodule WeGoNext.SourceData.WarcraftLogsApiFetch do
  @moduledoc """
  Raw Warcraft Logs API response captured as source-data evidence.

  These rows are external parser evidence for validation and investigation.
  They are not local combat-log inputs, active rules, promoted criteria, or
  gold fact inputs.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.SourceData.SourceImport

  @schema_prefix "source_data"

  schema "warcraft_logs_api_fetch" do
    belongs_to(:source_import, SourceImport)

    field(:report_code, :string)
    field(:fight_id, :integer)
    field(:source_url, :string)
    field(:api_endpoint, :string)
    field(:api_version, :string, default: "v2")

    field(:query_name, :string)
    field(:query_document, :string)
    field(:query_hash, :string)
    field(:query_variables, :map, default: %{})
    field(:request_params, :map, default: %{})
    field(:request_hash, :string)

    field(:fetched_at, :utc_datetime_usec)
    field(:response_hash, :string)
    field(:response_payload, :map, default: %{})
    field(:metadata, :map, default: %{})
    field(:artifact_path, :string)
    field(:artifact_hash, :string)
    field(:artifact_bytes, :integer)

    field(:product, :string, default: "wow")
    field(:channel, :string, default: "retail")
    field(:build_version, :string)
    field(:build_key, :string)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(fetch, attrs) do
    fetch
    |> cast(attrs, [
      :source_import_id,
      :report_code,
      :fight_id,
      :source_url,
      :api_endpoint,
      :api_version,
      :query_name,
      :query_document,
      :query_hash,
      :query_variables,
      :request_params,
      :request_hash,
      :fetched_at,
      :response_hash,
      :response_payload,
      :metadata,
      :artifact_path,
      :artifact_hash,
      :artifact_bytes,
      :product,
      :channel,
      :build_version,
      :build_key
    ])
    |> validate_required([
      :source_import_id,
      :report_code,
      :fight_id,
      :source_url,
      :api_version,
      :query_name,
      :query_hash,
      :query_variables,
      :request_params,
      :request_hash,
      :fetched_at,
      :response_hash,
      :response_payload,
      :metadata,
      :artifact_path,
      :artifact_hash,
      :artifact_bytes,
      :product,
      :channel
    ])
    |> validate_number(:fight_id, greater_than: 0)
    |> foreign_key_constraint(:source_import_id)
    |> unique_constraint(:source_import_id)
  end
end

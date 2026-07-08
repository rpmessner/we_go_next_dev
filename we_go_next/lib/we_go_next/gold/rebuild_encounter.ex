defmodule WeGoNext.Gold.RebuildEncounter do
  @moduledoc """
  Coordinates gold-layer rebuilds for one encounter dimension.

  Importers and backfill tasks should call this boundary instead of knowing
  which gold dimensions or facts need to be rebuilt for an encounter.
  """

  alias WeGoNext.Documents
  alias WeGoNext.Gold.{DimEncounter, FactFailure}
  alias WeGoNext.Mirror.Outbox

  @type rebuild_result :: %{
          fact_failure: map(),
          document: map()
        }

  @doc """
  Rebuilds all currently supported gold outputs for one encounter.

  Options are passed through to fact builders, including explicit ruleset
  selection via `:ruleset_id`.
  """
  @spec rebuild(pos_integer() | DimEncounter.t(), keyword()) ::
          {:ok, rebuild_result()} | {:error, term()}
  def rebuild(encounter_or_id, opts \\ [])

  def rebuild(%DimEncounter{id: encounter_dim_id}, opts) do
    rebuild(encounter_dim_id, opts)
  end

  def rebuild(encounter_dim_id, opts) when is_integer(encounter_dim_id) and is_list(opts) do
    case FactFailure.rebuild_for_encounter(encounter_dim_id, rebuild_opts(opts)) do
      {:ok, result} ->
        with {:ok, document_result} <- maybe_generate_document(encounter_dim_id, opts) do
          maybe_enqueue_mirror_upload(encounter_dim_id, opts)
          {:ok, %{fact_failure: result, document: document_result}}
        end

      {:error, :active_ruleset_not_found} ->
        with {:ok, document_result} <- maybe_generate_document(encounter_dim_id, opts) do
          {:ok,
           %{
             fact_failure: %{deleted: 0, inserted: 0, skipped: :active_ruleset_not_found},
             document: document_result
           }}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_generate_document(encounter_dim_id, opts) do
    if Keyword.get(opts, :generate_document, true) do
      Documents.generate_for_encounter(encounter_dim_id)
    else
      {:ok, %{skipped: :disabled}}
    end
  end

  defp maybe_enqueue_mirror_upload(encounter_dim_id, opts) do
    if Keyword.get(opts, :enqueue_mirror_upload, true) do
      case Outbox.enqueue_for_encounter(encounter_dim_id) do
        {:ok, _upload} -> :ok
        {:error, _reason} -> :ok
      end
    end
  end

  defp rebuild_opts(opts) do
    cond do
      Keyword.has_key?(opts, :ruleset_id) -> [ruleset_id: Keyword.fetch!(opts, :ruleset_id)]
      Keyword.has_key?(opts, :ruleset) -> [ruleset: Keyword.fetch!(opts, :ruleset)]
      true -> [ruleset: :active]
    end
  end
end

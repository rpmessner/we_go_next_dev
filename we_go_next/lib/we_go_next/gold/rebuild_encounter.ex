defmodule WeGoNext.Gold.RebuildEncounter do
  @moduledoc """
  Coordinates gold-layer rebuilds for one encounter dimension.

  Importers and backfill tasks should call this boundary instead of knowing
  which gold dimensions or facts need to be rebuilt for an encounter.
  """

  import Ecto.Query
  alias WeGoNext.{Documents, Freshness, Repo}
  alias WeGoNext.Gold.{DimEncounter, FactFailure, FactWipeCause}

  @type rebuild_result :: %{
          fact_failure: map(),
          fact_wipe_cause: map(),
          document: map()
        }

  @doc """
  Rebuilds all currently supported gold outputs for one encounter.

  Failure facts always use the live mechanics catalog.
  """
  @spec rebuild(pos_integer() | DimEncounter.t(), keyword()) ::
          {:ok, rebuild_result()} | {:error, term()}
  def rebuild(encounter_or_id, opts \\ [])

  def rebuild(%DimEncounter{id: encounter_dim_id}, opts) do
    rebuild(encounter_dim_id, opts)
  end

  def rebuild(encounter_dim_id, opts) when is_integer(encounter_dim_id) and is_list(opts) do
    # Keep the durable partial marker outside the output transaction. A failed
    # write (or process death after writing the file) rolls back facts, not this
    # marker. Readers validate document stamps against the live dimension.
    # Session locks span both commits and serialize coordinated rebuilds.
    Repo.checkout(fn ->
      Repo.query!("SELECT pg_advisory_lock($1, $2)", [181_806, encounter_dim_id])

      try do
        case mark_partial(encounter_dim_id) do
          {0, _} -> {:error, :encounter_not_found}
          {1, _} -> rebuild_transaction(encounter_dim_id, opts)
        end
      after
        Repo.query!("SELECT pg_advisory_unlock($1, $2)", [181_806, encounter_dim_id])
      end
    end)
  end

  defp mark_partial(id) do
    from(e in DimEncounter, where: e.id == ^id)
    |> Repo.update_all(set: [failure_derivation_version: Freshness.partial_stamp()])
  end

  defp rebuild_transaction(id, opts) do
    Repo.transaction(fn ->
      with {:ok, wipe_cause} <- FactWipeCause.rebuild_for_encounter(id),
           {:ok, result} <- rebuild_other_outputs(id, opts) do
        if not Keyword.get(opts, :generate_document, true), do: mark_partial(id)
        Map.put(result, :fact_wipe_cause, wipe_cause)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp rebuild_other_outputs(encounter_dim_id, opts) do
    case FactFailure.rebuild_for_encounter(encounter_dim_id) do
      {:ok, result} ->
        with {:ok, document_result} <- maybe_generate_document(encounter_dim_id, opts) do
          {:ok, %{fact_failure: result, document: document_result}}
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
end

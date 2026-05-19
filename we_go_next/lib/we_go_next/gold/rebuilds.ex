defmodule WeGoNext.Gold.Rebuilds do
  @moduledoc """
  Operator-facing gold rebuild helpers.

  The CLI task and LiveView controls both use this boundary so gold fact
  recomputation keeps one implementation path.
  """

  import Ecto.Query

  alias WeGoNext.Gold.{DimEncounter, FactFailure, RebuildEncounter}
  alias WeGoNext.Repo

  @type status :: %{
          gold_encounters_count: non_neg_integer(),
          failure_facts_count: non_neg_integer()
        }

  @type totals :: %{
          encounters: non_neg_integer(),
          deleted: non_neg_integer(),
          inserted: non_neg_integer(),
          skipped: non_neg_integer()
        }

  @doc """
  Returns compact medallion counts for operator status surfaces.
  """
  @spec status() :: status()
  def status do
    %{
      gold_encounters_count: Repo.aggregate(DimEncounter, :count),
      failure_facts_count: Repo.aggregate(FactFailure, :count)
    }
  end

  @doc """
  Rebuilds supported gold facts for every known gold encounter.
  """
  @spec rebuild_all(keyword()) :: {:ok, totals()} | {:error, map()}
  def rebuild_all(opts \\ [ruleset: :active]) do
    rebuild_encounters(encounter_ids(), opts)
  end

  @doc """
  Rebuilds supported gold facts for the given encounter ids.
  """
  @spec rebuild_encounters([pos_integer()], keyword()) :: {:ok, totals()} | {:error, map()}
  def rebuild_encounters(encounter_ids, opts \\ [ruleset: :active]) when is_list(encounter_ids) do
    rebuild_opts = normalize_rebuild_opts(opts)
    totals = %{encounters: length(encounter_ids), deleted: 0, inserted: 0, skipped: 0}

    Enum.reduce_while(encounter_ids, {:ok, totals}, fn encounter_id, {:ok, totals} ->
      case RebuildEncounter.rebuild(encounter_id, rebuild_opts) do
        {:ok, %{fact_failure: result}} ->
          {:cont, {:ok, add_result(totals, result)}}

        {:error, reason} ->
          {:halt, {:error, %{encounter_id: encounter_id, reason: reason, totals: totals}}}
      end
    end)
  end

  defp encounter_ids do
    DimEncounter
    |> order_by([encounter], asc: encounter.id)
    |> select([encounter], encounter.id)
    |> Repo.all()
  end

  defp normalize_rebuild_opts([]), do: [ruleset: :active]
  defp normalize_rebuild_opts(opts), do: opts

  defp add_result(totals, result) do
    %{
      totals
      | deleted: totals.deleted + Map.get(result, :deleted, 0),
        inserted: totals.inserted + Map.get(result, :inserted, 0),
        skipped: totals.skipped + skipped_count(result)
    }
  end

  defp skipped_count(%{skipped: _reason}), do: 1
  defp skipped_count(_result), do: 0
end

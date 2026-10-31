defmodule WeGoNext.Rules do
  @moduledoc """
  One live mechanics catalog, authored in code and synced directly to gold.

  Sync is atomic. Removed definitions are retired, never deleted, so existing
  facts keep their stable criterion keys. Rebuild is a separate, retryable stage.
  """
  import Ecto.Query

  alias WeGoNext.GameData.Raids
  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, Rebuilds}
  alias WeGoNext.{Repo, SourceData}
  alias WeGoNext.Rules.SyncFlow

  def sync_current_tier_mechanics(opts \\ []), do: sync_raid_mechanics("current_tier", opts)
  def sync_current_tier_rules(opts \\ []), do: sync_current_tier_mechanics(opts)

  def sync_raid_mechanics(raid, opts \\ []) do
    run_sync_flow(:sync, SyncFlow.initial(opts), %{criteria: [], rebuild: nil}, raid, opts)
  end

  defp run_sync_flow(:done, ctx, result, _raid, _opts),
    do: {:ok, Map.put(result, :completed, ctx.completed)}

  defp run_sync_flow(stage, ctx, result, raid, opts) do
    case safely_run_stage(stage, result, raid, opts) do
      {:ok, updated} ->
        {:ok, next, ctx, _} = SyncFlow.step(stage, :succeeded, ctx)
        run_sync_flow(next, ctx, updated, raid, opts)

      {:error, reason} ->
        {:ok, :failed, ctx, _} = SyncFlow.step(stage, :failed, ctx)
        {:error, %{stage: stage, reason: reason, completed: ctx.completed, result: result}}
    end
  end

  defp safely_run_stage(stage, result, raid, opts) do
    run_stage(stage, result, raid, opts)
  rescue
    exception ->
      {:error, %{exception: exception.__struct__, message: Exception.message(exception)}}
  end

  defp run_stage(:sync, result, raid, opts) do
    with {:ok, catalog} <- raid_module(raid),
         {:ok, criteria} <- sync_catalog(catalog, opts) do
      {:ok, %{result | criteria: criteria}}
    end
  end

  defp run_stage(:rebuild, result, _raid, _opts) do
    with {:ok, rebuild} <- Rebuilds.rebuild_all() do
      {:ok, %{result | rebuild: rebuild}}
    end
  end

  defp sync_catalog(catalog, opts) do
    Repo.transaction(fn ->
      # Serialize full and single-raid syncs; no activation/promotion window.
      Repo.query!("SELECT pg_advisory_xact_lock(181810)")
      criteria = Enum.map(catalog.rule_criteria(), &upsert_criterion!(&1, opts))
      kept_ids = Enum.map(criteria, & &1.id)
      scope = retirement_scope(catalog)

      retired =
        scope
        |> where([c], c.active and c.id not in ^kept_ids)
        |> Repo.all()

      Enum.each(retired, fn criterion ->
        criterion |> Ecto.Changeset.change(active: false) |> Repo.update!()
        invalidate_failures(criterion)
      end)

      criteria
    end)
  end

  defp retirement_scope(WeGoNext.GameData.Raids.CurrentTier), do: DimMechanicCriterion

  defp retirement_scope(catalog) do
    bosses = catalog.mechanics() |> Enum.map(& &1.boss_encounter_id) |> Enum.uniq()
    where(DimMechanicCriterion, [c], c.boss_encounter_id in ^bosses)
  end

  defp upsert_criterion!(attrs, opts) do
    attrs = reference_names(attrs, opts)
    changeset = DimMechanicCriterion.changeset(%DimMechanicCriterion{}, attrs)
    key = Ecto.Changeset.get_field(changeset, :criterion_key)
    existing = key && Repo.get_by(DimMechanicCriterion, criterion_key: key)
    changeset = DimMechanicCriterion.changeset(existing || %DimMechanicCriterion{}, attrs)

    if changeset.valid? and changeset.changes == %{} do
      existing
    else
      case Repo.insert_or_update(changeset) do
        {:ok, criterion} ->
          invalidate_failures(criterion)
          criterion

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end
  end

  defp invalidate_failures(criterion) do
    query =
      if criterion.boss_encounter_id do
        where(DimEncounter, [e], e.wow_encounter_id == ^criterion.boss_encounter_id)
      else
        DimEncounter
      end

    Repo.update_all(query, set: [failure_derivation_version: nil])
  end

  defp reference_names(attrs, opts) do
    attrs
    |> put_name("spell_name", SourceData.resolve_spell_name(attrs["spell_id"], opts))
    |> put_name("boss_name", SourceData.resolve_encounter_name(attrs["boss_encounter_id"], opts))
  end

  defp put_name(attrs, _key, nil), do: attrs
  defp put_name(attrs, key, name), do: Map.put(attrs, key, name)

  defp raid_module(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :rule_criteria, 0) and
         function_exported?(module, :info, 0),
       do: {:ok, module},
       else: {:error, :invalid_raid_catalog}
  end

  defp raid_module(slug) when is_binary(slug) do
    case Raids.by_slug(slug) do
      nil -> {:error, :raid_catalog_not_found}
      module -> {:ok, module}
    end
  end
end

defmodule WeGoNext.Gold.FactFailure.Rebuilder do
  @moduledoc """
  Rebuild orchestration for `gold.fact_failure`.

  Loads encounter scope, refreshes conformed players, replaces the pull's facts,
  then stamps completion. All builders select from the live gold catalog.
  """

  import Ecto.Query

  alias WeGoNext.Gold.{DimEncounter, DimPlayer, FactFailure}
  alias WeGoNext.Gold.FactFailure.Derivation
  alias WeGoNext.Gold.FactFailure.{Query, RuleSelector}
  alias WeGoNext.Gold.FactFailure.Builders.{AvoidableDamage, MissedInterrupt, TargetedCone}
  alias WeGoNext.Repo

  @raid_player_guid "__RAID__"
  @builders [AvoidableDamage, MissedInterrupt, TargetedCone]

  @spec rebuild_for_encounter(pos_integer(), keyword()) ::
          {:ok, %{deleted: non_neg_integer(), inserted: non_neg_integer()}} | {:error, term()}
  def rebuild_for_encounter(encounter_dim_id, opts)
      when is_integer(encounter_dim_id) and is_list(opts) do
    Repo.transaction(fn ->
      ensure_raid_sentinel!()

      dim_encounter =
        case Repo.get(DimEncounter, encounter_dim_id) do
          %DimEncounter{} = dim_encounter -> dim_encounter
          nil -> Repo.rollback(:encounter_not_found)
        end

      DimPlayer.upsert_from_silver(dim_encounter.id)

      deleted = delete_existing_facts!(dim_encounter.id)

      case insert_builder_rows(dim_encounter.id, DateTime.utc_now()) do
        {:ok, inserted} ->
          dim_encounter
          |> Ecto.Changeset.change(failure_derivation_version: Derivation.current_version())
          |> Repo.update!()

          %{deleted: deleted, inserted: inserted}

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp ensure_raid_sentinel! do
    Repo.insert_all(
      DimPlayer,
      [
        %{
          player_guid: @raid_player_guid,
          player_name: "Raid"
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:player_guid]
    )
  end

  defp delete_existing_facts!(encounter_dim_id) do
    {deleted, _} =
      from(failure in FactFailure,
        where: failure.encounter_dim_id == ^encounter_dim_id
      )
      |> Repo.delete_all()

    deleted
  end

  defp insert_builder_rows(encounter_dim_id, rebuilt_at) do
    sql =
      Query.insert_sql(
        builders: @builders,
        base_ctes: [
          Query.encounter_scope_cte(),
          RuleSelector.selected_criteria_cte()
        ],
        builder_opts: [raid_player_guid: @raid_player_guid]
      )

    case Repo.query(sql, [encounter_dim_id, Derivation.current_version(), rebuilt_at]) do
      {:ok, %{num_rows: inserted}} -> {:ok, inserted}
      {:error, reason} -> {:error, reason}
    end
  end
end

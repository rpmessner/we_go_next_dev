defmodule WeGoNext.Gold.FactFailure.Rebuilder do
  @moduledoc """
  Rebuild orchestration for `gold.fact_failure`.

  This module owns the stable rebuild flow: resolve ruleset, load encounter
  scope, refresh conformed players, delete stale facts for the same
  encounter/ruleset, then insert rows emitted by the registered mechanic
  builders.
  """

  import Ecto.Query

  alias WeGoNext.Gold.{DimEncounter, DimPlayer, FactFailure}
  alias WeGoNext.Gold.FactFailure.{Query, RuleSelector}
  alias WeGoNext.Gold.FactFailure.Builders.{AvoidableDamage, MissedInterrupt}
  alias WeGoNext.Repo
  alias WeGoNext.Rules.Ruleset

  @raid_player_guid "__RAID__"
  @builders [AvoidableDamage, MissedInterrupt]

  @spec rebuild_for_encounter(pos_integer(), keyword()) ::
          {:ok, %{deleted: non_neg_integer(), inserted: non_neg_integer()}} | {:error, term()}
  def rebuild_for_encounter(encounter_dim_id, opts)
      when is_integer(encounter_dim_id) and is_list(opts) do
    Repo.transaction(fn ->
      ensure_raid_sentinel!()

      ruleset_id =
        case resolve_ruleset_id(opts) do
          {:ok, ruleset_id} -> ruleset_id
          {:error, reason} -> Repo.rollback(reason)
        end

      dim_encounter =
        case Repo.get(DimEncounter, encounter_dim_id) do
          %DimEncounter{} = dim_encounter -> dim_encounter
          nil -> Repo.rollback(:encounter_not_found)
        end

      DimPlayer.upsert_from_silver(dim_encounter.id)

      deleted = delete_existing_facts!(dim_encounter.id, ruleset_id)

      case insert_builder_rows(dim_encounter.id, ruleset_id) do
        {:ok, inserted} -> %{deleted: deleted, inserted: inserted}
        {:error, reason} -> Repo.rollback(reason)
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

  defp resolve_ruleset_id(opts) do
    cond do
      Keyword.has_key?(opts, :ruleset_id) ->
        opts
        |> Keyword.fetch!(:ruleset_id)
        |> get_ruleset_id()

      Keyword.get(opts, :ruleset, :active) == :active ->
        get_active_ruleset_id()

      true ->
        {:error, :unsupported_ruleset_option}
    end
  end

  defp get_ruleset_id(ruleset_id) do
    case Repo.get(Ruleset, ruleset_id) do
      %Ruleset{id: id} -> {:ok, id}
      nil -> {:error, :ruleset_not_found}
    end
  end

  defp get_active_ruleset_id do
    case Repo.get_by(Ruleset, status: "active") do
      %Ruleset{id: id} -> {:ok, id}
      nil -> {:error, :active_ruleset_not_found}
    end
  end

  defp delete_existing_facts!(encounter_dim_id, ruleset_id) do
    {deleted, _} =
      from(failure in FactFailure,
        join: criterion in assoc(failure, :criterion),
        where:
          failure.encounter_dim_id == ^encounter_dim_id and
            criterion.ruleset_id == ^ruleset_id
      )
      |> Repo.delete_all()

    deleted
  end

  defp insert_builder_rows(encounter_dim_id, ruleset_id) do
    sql =
      Query.insert_sql(
        builders: @builders,
        base_ctes: [
          Query.encounter_scope_cte(),
          RuleSelector.selected_criteria_cte()
        ],
        builder_opts: [raid_player_guid: @raid_player_guid]
      )

    case Repo.query(sql, [encounter_dim_id, ruleset_id]) do
      {:ok, %{num_rows: inserted}} -> {:ok, inserted}
      {:error, reason} -> {:error, reason}
    end
  end
end

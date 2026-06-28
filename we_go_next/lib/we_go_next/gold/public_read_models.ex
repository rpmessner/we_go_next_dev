defmodule WeGoNext.Gold.PublicReadModels do
  @moduledoc """
  Gold-only read models for the hosted public mirror.

  These queries intentionally depend only on mirrored gold tables. Public
  LiveViews should use this module instead of parser/operator read models that
  can touch silver, rules, accounts, or transitional public tables.
  """

  import Ecto.Query

  alias WeGoNext.Gold.{DimEncounter, FactFailure}
  alias WeGoNext.Repo

  @type filters :: %{
          optional(:limit) => pos_integer()
        }

  @doc """
  Lists mirrored encounters with aggregate failure counts.
  """
  @spec list_encounters(filters()) :: [map()]
  def list_encounters(filters \\ %{}) when is_map(filters) do
    limit = Map.get(filters, :limit, 50)

    DimEncounter
    |> where([encounter], not is_nil(encounter.source_encounter_key))
    |> join(:left, [encounter], failure in FactFailure,
      on: failure.encounter_dim_id == encounter.id
    )
    |> group_by([encounter, failure], encounter.id)
    |> order_by([encounter, failure], desc_nulls_last: encounter.start_time, desc: encounter.id)
    |> limit(^limit)
    |> select([encounter, failure], %{
      source_encounter_key: encounter.source_encounter_key,
      wow_encounter_id: encounter.wow_encounter_id,
      name: encounter.name,
      difficulty_id: encounter.difficulty_id,
      difficulty_name: encounter.difficulty_name,
      group_size: encounter.group_size,
      instance_id: encounter.instance_id,
      start_time: encounter.start_time,
      end_time: encounter.end_time,
      success: encounter.success,
      fight_time_ms: encounter.fight_time_ms,
      failure_count: coalesce(sum(failure.failure_count), 0),
      total_damage: coalesce(sum(failure.total_damage), 0),
      failing_player_count: count(failure.player_dim_id, :distinct),
      criterion_count: count(failure.criterion_dim_id, :distinct)
    })
    |> Repo.all()
    |> Enum.map(&normalize_aggregate_row/1)
  end

  @doc """
  Returns one encounter's failure breakdown by player and criterion.
  """
  @spec encounter_failures(String.t()) :: {:ok, map()} | {:error, :not_found}
  def encounter_failures(source_encounter_key) when is_binary(source_encounter_key) do
    case Repo.get_by(DimEncounter, source_encounter_key: source_encounter_key) do
      %DimEncounter{} = encounter ->
        rows = failure_rows(encounter.id)

        {:ok,
         %{
           encounter: encode_encounter(encounter),
           counts: counts(rows),
           failures: rows,
           player_groups: group_by_player(rows)
         }}

      nil ->
        {:error, :not_found}
    end
  end

  defp failure_rows(encounter_dim_id) do
    FactFailure
    |> join(:inner, [failure], player in assoc(failure, :player))
    |> join(:inner, [failure, player], criterion in assoc(failure, :criterion))
    |> where([failure, player, criterion], failure.encounter_dim_id == ^encounter_dim_id)
    |> order_by([failure, player, criterion],
      asc: player.player_name,
      desc: failure.failure_count,
      asc: criterion.spell_name
    )
    |> select([failure, player, criterion], %{
      player_guid: player.player_guid,
      player_name: player.player_name,
      class_id: player.class_id,
      spec_id: player.spec_id,
      criterion_key: criterion.criterion_key,
      spell_id: criterion.spell_id,
      spell_name: criterion.spell_name,
      mechanic_type: criterion.mechanic_type,
      boss_encounter_id: criterion.boss_encounter_id,
      boss_name: criterion.boss_name,
      difficulty_id: criterion.difficulty_id,
      threshold: criterion.threshold,
      failure_count: failure.failure_count,
      total_damage: failure.total_damage,
      derivation_version: failure.derivation_version,
      rebuilt_at: failure.rebuilt_at
    })
    |> Repo.all()
  end

  defp encode_encounter(%DimEncounter{} = encounter) do
    %{
      source_encounter_key: encounter.source_encounter_key,
      wow_encounter_id: encounter.wow_encounter_id,
      name: encounter.name,
      difficulty_id: encounter.difficulty_id,
      difficulty_name: encounter.difficulty_name,
      group_size: encounter.group_size,
      instance_id: encounter.instance_id,
      start_time: encounter.start_time,
      end_time: encounter.end_time,
      success: encounter.success,
      fight_time_ms: encounter.fight_time_ms
    }
  end

  defp counts(rows) do
    %{
      failure_count: Enum.sum(Enum.map(rows, & &1.failure_count)),
      total_damage: Enum.sum(Enum.map(rows, & &1.total_damage)),
      failing_player_count: rows |> Enum.map(& &1.player_guid) |> Enum.uniq() |> length(),
      criterion_count: rows |> Enum.map(& &1.criterion_key) |> Enum.uniq() |> length()
    }
  end

  defp group_by_player(rows) do
    rows
    |> Enum.group_by(&{&1.player_guid, &1.player_name})
    |> Enum.map(fn {{player_guid, player_name}, failures} ->
      %{
        player_guid: player_guid,
        player_name: player_name,
        failure_count: Enum.sum(Enum.map(failures, & &1.failure_count)),
        total_damage: Enum.sum(Enum.map(failures, & &1.total_damage)),
        failures: failures
      }
    end)
    |> Enum.sort_by(&{String.downcase(&1.player_name || ""), &1.player_guid || ""})
  end

  defp normalize_aggregate_row(row) do
    %{
      row
      | failure_count: to_integer(row.failure_count),
        total_damage: to_integer(row.total_damage),
        failing_player_count: to_integer(row.failing_player_count),
        criterion_count: to_integer(row.criterion_count)
    }
  end

  defp to_integer(%Decimal{} = value), do: Decimal.to_integer(value)
  defp to_integer(value), do: value
end

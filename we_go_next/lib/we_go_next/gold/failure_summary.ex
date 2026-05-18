defmodule WeGoNext.Gold.FailureSummary do
  @moduledoc """
  Read model for cross-encounter mechanic failure summaries.
  """

  import Ecto.Query

  alias WeGoNext.Gold.FactFailure
  alias WeGoNext.Repo

  @type filters :: %{
          optional(:start_date) => Date.t(),
          optional(:end_date) => Date.t()
        }

  @type row :: %{
          player_dim_id: pos_integer(),
          player_guid: String.t(),
          player_name: String.t(),
          criterion_dim_id: pos_integer(),
          spell_id: integer(),
          spell_name: String.t(),
          mechanic_type: String.t(),
          boss_name: String.t() | nil,
          difficulty_id: integer() | nil,
          failure_count: non_neg_integer(),
          total_damage: non_neg_integer(),
          encounter_count: non_neg_integer(),
          latest_start_time: DateTime.t() | nil
        }

  @doc """
  Returns mechanic failure facts grouped by player and criterion.
  """
  @spec list_grouped_failures(filters()) :: [row()]
  def list_grouped_failures(filters \\ %{}) when is_map(filters) do
    FactFailure
    |> join(:inner, [failure], player in assoc(failure, :player))
    |> join(:inner, [failure, player], criterion in assoc(failure, :criterion))
    |> join(:inner, [failure, player, criterion], encounter in assoc(failure, :encounter))
    |> apply_start_date(Map.get(filters, :start_date))
    |> apply_end_date(Map.get(filters, :end_date))
    |> group_by([failure, player, criterion, encounter], [
      player.id,
      player.player_guid,
      player.player_name,
      criterion.id,
      criterion.spell_id,
      criterion.spell_name,
      criterion.mechanic_type,
      criterion.boss_name,
      criterion.difficulty_id
    ])
    |> order_by([failure, player, criterion, encounter],
      asc: player.player_name,
      desc: fragment("sum(?)", failure.failure_count),
      asc: criterion.spell_name
    )
    |> select([failure, player, criterion, encounter], %{
      player_dim_id: player.id,
      player_guid: player.player_guid,
      player_name: player.player_name,
      criterion_dim_id: criterion.id,
      spell_id: criterion.spell_id,
      spell_name: criterion.spell_name,
      mechanic_type: criterion.mechanic_type,
      boss_name: criterion.boss_name,
      difficulty_id: criterion.difficulty_id,
      failure_count: fragment("sum(?)::integer", failure.failure_count),
      total_damage: fragment("sum(?)::bigint", failure.total_damage),
      encounter_count: fragment("count(DISTINCT ?)::integer", encounter.id),
      latest_start_time: max(encounter.start_time)
    })
    |> Repo.all()
  end

  @doc """
  Groups summary rows by player for rendering.
  """
  @spec group_by_player([row()]) :: [map()]
  def group_by_player(rows) when is_list(rows) do
    rows
    |> Enum.group_by(&{&1.player_dim_id, &1.player_guid, &1.player_name})
    |> Enum.map(fn {{player_dim_id, player_guid, player_name}, failures} ->
      %{
        player_dim_id: player_dim_id,
        player_guid: player_guid,
        player_name: player_name,
        failure_count: Enum.sum(Enum.map(failures, & &1.failure_count)),
        total_damage: Enum.sum(Enum.map(failures, & &1.total_damage)),
        failures: failures
      }
    end)
    |> Enum.sort_by(&{String.downcase(&1.player_name || ""), &1.player_guid || ""})
  end

  defp apply_start_date(query, %Date{} = date) do
    {:ok, start_at} = DateTime.new(date, ~T[00:00:00], "Etc/UTC")
    where(query, [failure, player, criterion, encounter], encounter.start_time >= ^start_at)
  end

  defp apply_start_date(query, _date), do: query

  defp apply_end_date(query, %Date{} = date) do
    {:ok, exclusive_end_at} = DateTime.new(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")

    where(
      query,
      [failure, player, criterion, encounter],
      encounter.start_time < ^exclusive_end_at
    )
  end

  defp apply_end_date(query, _date), do: query
end

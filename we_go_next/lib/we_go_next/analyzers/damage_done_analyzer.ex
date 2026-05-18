defmodule WeGoNext.Analyzers.DamageDoneAnalyzer do
  @moduledoc """
  Analyzes damage dealt by players during combat encounters.

  This is a diagnostic tool, not a damage meter. It provides:
  - Simple DPS breakdown by role (tank vs DPS/healer)
  - Underperformer detection (low DPS players who didn't die)

  Tank detection reuses the same heuristic as DamageTakenAnalyzer:
  top 2 players receiving NPC melee damage are considered tanks.
  """

  alias WeGoNext.Encounter

  defmodule PlayerDPS do
    @moduledoc "Damage done statistics for a single player"
    defstruct [
      :player_name,
      :player_guid,
      # :tank or :dps_healer
      :role,
      total: 0,
      dps: 0.0,
      # seconds (full fight or time until death)
      active_time: 0.0
    ]
  end

  @doc """
  Analyzes an encounter and returns damage done statistics for all players.

  Returns a map with:
    - :tanks - list of %PlayerDPS{} for tanks, sorted by DPS
    - :dps_healers - list of %PlayerDPS{} for DPS/healers, sorted by DPS
    - :all - combined list sorted by DPS descending
    - :fight_duration - encounter duration in seconds

  Requires tank_guids from DamageTakenAnalyzer for role detection.
  """
  def analyze(%Encounter{} = encounter, opts \\ []) do
    tank_guids = Keyword.get(opts, :tank_guids, MapSet.new())
    fight_duration = Encounter.fight_time_sec(encounter)

    # Events are now loaded from DB in chronological order
    players =
      encounter.events
      |> Enum.reduce(%{}, fn event, acc -> process_event(event, acc) end)

    # Calculate DPS and assign roles
    players_with_stats =
      players
      |> Map.values()
      |> Enum.map(fn player ->
        role = if MapSet.member?(tank_guids, player.player_guid), do: :tank, else: :dps_healer
        dps = if fight_duration > 0, do: player.total / fight_duration, else: 0.0
        %{player | role: role, dps: dps, active_time: fight_duration}
      end)
      |> Enum.sort_by(& &1.dps, :desc)

    {tanks, dps_healers} = Enum.split_with(players_with_stats, &(&1.role == :tank))

    %{
      tanks: Enum.sort_by(tanks, & &1.dps, :desc),
      dps_healers: Enum.sort_by(dps_healers, & &1.dps, :desc),
      all: players_with_stats,
      fight_duration: fight_duration
    }
  end

  @doc """
  Identifies underperformers: players with significantly low DPS who didn't die.

  Players who died have an excuse for low DPS. This function filters them out
  and flags only those who survived but performed poorly.

  Returns list of %{player_name, dps, median_dps, percent_of_median, reason}
  """
  def identify_underperformers(damage_done, deaths, opts \\ []) do
    # 70% of median
    threshold = Keyword.get(opts, :threshold, 0.7)

    # Get set of players who died
    dead_guids = deaths |> Enum.map(& &1.player_guid) |> MapSet.new()

    # Filter to DPS/healers only (tanks have different expectations)
    dps_healers = damage_done.dps_healers

    # Split into survivors and dead
    {survivors, _dead} =
      Enum.split_with(dps_healers, fn p ->
        not MapSet.member?(dead_guids, p.player_guid)
      end)

    # Need at least 3 survivors to calculate meaningful median
    if length(survivors) < 3 do
      []
    else
      # Calculate median DPS of survivors
      survivor_dps = Enum.map(survivors, & &1.dps) |> Enum.sort()
      median_dps = median(survivor_dps)

      # Flag those below threshold
      survivors
      |> Enum.filter(fn p -> p.dps < median_dps * threshold end)
      |> Enum.map(fn p ->
        percent = if median_dps > 0, do: p.dps / median_dps * 100, else: 0

        %{
          player_name: p.player_name,
          player_guid: p.player_guid,
          dps: p.dps,
          median_dps: median_dps,
          percent_of_median: percent,
          reason: :low_dps
        }
      end)
      |> Enum.sort_by(& &1.percent_of_median)
    end
  end

  @doc """
  Annotates players with death information for display.

  Returns the damage_done map with players annotated with death time if applicable.
  """
  def annotate_with_deaths(damage_done, deaths) do
    death_times = Map.new(deaths, fn d -> {d.player_guid, d.time_into_fight} end)

    annotate_list = fn players ->
      Enum.map(players, fn p ->
        case Map.get(death_times, p.player_guid) do
          nil -> Map.put(p, :death_time, nil)
          time -> Map.put(p, :death_time, time)
        end
      end)
    end

    %{
      damage_done
      | tanks: annotate_list.(damage_done.tanks),
        dps_healers: annotate_list.(damage_done.dps_healers),
        all: annotate_list.(damage_done.all)
    }
  end

  # Process damage events where source is a player (now using normalized fields)
  defp process_event(%{type: type} = event, players)
       when type in ["SPELL_DAMAGE", "SPELL_PERIODIC_DAMAGE", "SWING_DAMAGE", "RANGE_DAMAGE"] do
    source_guid = event.source_guid
    source_name = event.source_name
    target_guid = event.target_guid
    amount = event.amount || 0

    # Only count damage done BY players TO npcs (boss/add damage)
    if player_guid?(source_guid) and npc_guid?(target_guid) do
      update_player_damage(players, source_guid, source_name, amount)
    else
      players
    end
  end

  defp process_event(_event, players), do: players

  defp update_player_damage(players, guid, name, amount) do
    Map.update(players, guid, new_player(guid, name, amount), fn player ->
      %{player | total: player.total + amount}
    end)
  end

  defp new_player(guid, name, amount) do
    %PlayerDPS{
      player_guid: guid,
      player_name: name,
      total: amount
    }
  end

  defp player_guid?(guid) when is_binary(guid), do: String.starts_with?(guid, "Player-")
  defp player_guid?(_), do: false

  defp npc_guid?(guid) when is_binary(guid), do: String.starts_with?(guid, "Creature-")
  defp npc_guid?(_), do: false

  defp median([]), do: 0

  defp median(list) do
    sorted = Enum.sort(list)
    len = length(sorted)
    mid = div(len, 2)

    if rem(len, 2) == 0 do
      (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
    else
      Enum.at(sorted, mid)
    end
  end

  @doc """
  Formats DPS for display (e.g., "45.2k")
  """
  def format_dps(dps) when is_float(dps) do
    cond do
      dps >= 1_000_000 -> "#{Float.round(dps / 1_000_000, 1)}M"
      dps >= 1000 -> "#{Float.round(dps / 1000, 1)}k"
      true -> "#{Float.round(dps, 0) |> trunc()}"
    end
  end

  def format_dps(dps) when is_integer(dps), do: format_dps(dps / 1)

  @doc """
  Formats total damage for display (e.g., "12.5M")
  """
  def format_damage(num) when is_integer(num) and num >= 1_000_000 do
    "#{Float.round(num / 1_000_000, 1)}M"
  end

  def format_damage(num) when is_integer(num) and num >= 1000 do
    "#{Float.round(num / 1000, 0) |> trunc()}k"
  end

  def format_damage(num), do: to_string(num)
end

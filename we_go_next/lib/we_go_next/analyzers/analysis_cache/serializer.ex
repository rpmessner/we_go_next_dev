defmodule WeGoNext.Analyzers.AnalysisCache.Serializer do
  @moduledoc """
  Serializes analysis data to JSON-friendly maps for database storage.

  Converts Elixir structs with atom keys and complex types (DateTime, etc.)
  to plain maps with string keys that can be stored as JSON in PostgreSQL.
  """

  alias WeGoNext.Encounter
  alias WeGoNext.Analyzers.{
    DeathAnalyzer,
    DamageTakenAnalyzer,
    DamageDoneAnalyzer,
    InterruptAnalyzer,
    DebuffAnalyzer,
    FailureAnalyzer,
    PullSummary,
    PlayerInfoAnalyzer
  }

  @doc """
  Generates complete analysis for an encounter, returning a JSON-serializable map.
  """
  def compute(%Encounter{} = encounter) do
    deaths = DeathAnalyzer.analyze(encounter)
    damage_stats = DamageTakenAnalyzer.analyze(encounter)
    interrupt_stats = InterruptAnalyzer.analyze(encounter)
    debuff_stats = DebuffAnalyzer.analyze(encounter)
    failure_stats = FailureAnalyzer.analyze(encounter)

    player_classes = PlayerInfoAnalyzer.player_classes_by_name(encounter)

    tank_guids =
      damage_stats.tanks
      |> Enum.map(& &1.player_guid)
      |> MapSet.new()

    damage_done_raw = DamageDoneAnalyzer.analyze(encounter, tank_guids: tank_guids)
    damage_done_annotated = DamageDoneAnalyzer.annotate_with_deaths(damage_done_raw, deaths)
    underperformers = DamageDoneAnalyzer.identify_underperformers(damage_done_raw, deaths)
    damage_done = Map.put(damage_done_annotated, :underperformers, underperformers)

    summary =
      PullSummary.summarize(encounter,
        deaths: deaths,
        damage_stats: damage_stats,
        damage_done: damage_done,
        interrupt_stats: interrupt_stats,
        debuff_stats: debuff_stats,
        failure_stats: failure_stats
      )

    %{
      "version" => 1,
      "computed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "deaths" => serialize_deaths(deaths),
      "damage_stats" => serialize_damage_stats(damage_stats),
      "damage_done" => serialize_damage_done(damage_done),
      "interrupt_stats" => serialize_interrupt_stats(interrupt_stats),
      "debuff_stats" => serialize_debuff_stats(debuff_stats),
      "failure_stats" => serialize_failure_stats(failure_stats),
      "summary" => serialize_summary(summary),
      "player_classes" => player_classes
    }
  end

  @doc """
  Serializes pre-computed analysis data to a JSON-friendly map.
  """
  def serialize(%{
        deaths: deaths,
        damage_stats: damage_stats,
        damage_done: damage_done,
        interrupt_stats: interrupt_stats,
        debuff_stats: debuff_stats,
        failure_stats: failure_stats,
        summary: summary
      } = data) do
    %{
      "version" => 1,
      "computed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "deaths" => serialize_deaths(deaths),
      "damage_stats" => serialize_damage_stats(damage_stats),
      "damage_done" => serialize_damage_done(damage_done),
      "interrupt_stats" => serialize_interrupt_stats(interrupt_stats),
      "debuff_stats" => serialize_debuff_stats(debuff_stats),
      "failure_stats" => serialize_failure_stats(failure_stats),
      "summary" => serialize_summary(summary),
      "player_classes" => Map.get(data, :player_classes, %{})
    }
  end

  # ===========================================================================
  # Deaths
  # ===========================================================================

  defp serialize_deaths(deaths) do
    Enum.map(deaths, fn death ->
      %{
        "player_name" => death.player_name,
        "player_guid" => death.player_guid,
        "time_into_fight" => death.time_into_fight,
        "timestamp" => serialize_datetime(death.timestamp),
        "killing_blow" => serialize_killing_blow(death.killing_blow),
        "recap" => Enum.map(death.recap || [], &serialize_recap_event/1)
      }
    end)
  end

  defp serialize_killing_blow(nil), do: nil

  defp serialize_killing_blow(kb) do
    %{
      "ability" => kb[:ability] || kb["ability"],
      "ability_id" => kb[:ability_id] || kb["ability_id"],
      "source" => kb[:source] || kb["source"],
      "damage" => kb[:damage] || kb[:amount] || kb["damage"] || kb["amount"],
      "overkill" => kb[:overkill] || kb["overkill"]
    }
  end

  defp serialize_recap_event(event) do
    %{
      "timestamp" => serialize_datetime(event.timestamp),
      "ability_name" => event.ability_name,
      "ability_id" => event.ability_id,
      "source_name" => event.source_name,
      "amount" => event.amount,
      "overkill" => event.overkill,
      "school" => event.school
    }
  end

  # ===========================================================================
  # Damage Stats (Taken)
  # ===========================================================================

  defp serialize_damage_stats(stats) do
    tanks = stats.tanks || []
    non_tanks = stats[:dps_healers] || stats[:non_tanks] || []
    all_players = stats[:all] || tanks ++ non_tanks

    total_damage = all_players |> Enum.map(& &1.total) |> Enum.sum()

    %{
      "tanks" => serialize_player_damage_list(tanks),
      "non_tanks" => serialize_player_damage_list(non_tanks),
      "all" => serialize_player_damage_list(all_players),
      "total_damage" => total_damage,
      "avoidable_damage" => 0
    }
  end

  defp serialize_player_damage_list(players) when is_list(players) do
    Map.new(players, fn player ->
      {player.player_name,
       %{
         "total" => player.total,
         "role" => to_string(player.role),
         "abilities" => serialize_ability_map(player.by_ability)
       }}
    end)
  end

  defp serialize_ability_map(abilities) when is_map(abilities) do
    Map.new(abilities, fn {name, data} ->
      {name,
       %{
         "total" => data.total,
         "hits" => data.hits,
         "ability_id" => data.ability_id,
         "players" => Map.get(data, :players, 1)
       }}
    end)
  end

  # ===========================================================================
  # Damage Done
  # ===========================================================================

  defp serialize_damage_done(stats) do
    %{
      "tanks" => serialize_player_dps_list(stats.tanks || []),
      "dps_healers" => serialize_player_dps_list(stats.dps_healers || []),
      "all" => serialize_player_dps_list(stats.all || []),
      "fight_duration" => stats.fight_duration || 0,
      "underperformers" => serialize_underperformers(stats[:underperformers] || [])
    }
  end

  defp serialize_player_dps_list(players) when is_list(players) do
    Enum.map(players, fn player ->
      %{
        "player_name" => player.player_name,
        "player_guid" => player.player_guid,
        "role" => to_string(player.role),
        "total" => player.total,
        "dps" => player.dps,
        "active_time" => player.active_time,
        "death_time" => Map.get(player, :death_time)
      }
    end)
  end

  defp serialize_underperformers(underperformers) do
    Enum.map(underperformers, fn u ->
      %{
        "player_name" => u.player_name,
        "player_guid" => u.player_guid,
        "dps" => u.dps,
        "median_dps" => u.median_dps,
        "percent_of_median" => u.percent_of_median,
        "reason" => to_string(u.reason)
      }
    end)
  end

  # ===========================================================================
  # Interrupt Stats
  # ===========================================================================

  defp serialize_interrupt_stats(stats) do
    interrupts = stats[:interrupts] || stats[:successful] || []
    by_player = stats[:by_player] || stats[:by_interrupter] || %{}

    %{
      "successful" => Enum.map(interrupts, &serialize_interrupt/1),
      "missed_casts" => Enum.map(stats.missed_casts || [], &serialize_missed_cast/1),
      "by_interrupter" => serialize_by_interrupter(by_player),
      "by_spell" => serialize_by_spell(stats.by_spell || %{})
    }
  end

  defp serialize_interrupt(int) do
    %{
      "timestamp" => serialize_datetime(int.timestamp),
      "time_into_fight" => int.time_into_fight,
      "interrupter_name" => int.interrupter_name,
      "interrupter_guid" => int.interrupter_guid,
      "target_name" => int.target_name,
      "target_guid" => int.target_guid,
      "interrupted_spell_id" => int.interrupted_spell_id,
      "interrupted_spell_name" => int.interrupted_spell_name,
      "interrupt_spell_id" => int.interrupt_spell_id,
      "interrupt_spell_name" => int.interrupt_spell_name
    }
  end

  defp serialize_missed_cast(cast) do
    %{
      "timestamp" => serialize_datetime(cast.timestamp),
      "time_into_fight" => cast.time_into_fight,
      "caster_name" => cast.caster_name,
      "caster_guid" => cast.caster_guid,
      "spell_id" => cast.spell_id,
      "spell_name" => cast.spell_name
    }
  end

  defp serialize_by_interrupter(by_player) do
    Map.new(by_player, fn {_guid, player_stats} ->
      {player_stats.player_name,
       %{
         "count" => player_stats.total_interrupts,
         "spells" => player_stats.by_spell
       }}
    end)
  end

  defp serialize_by_spell(by_spell) do
    Map.new(by_spell, fn {name, spell_stats} ->
      {name,
       %{
         "spell_id" => spell_stats.spell_id,
         "total_casts" => spell_stats.total_casts,
         "interrupted" => spell_stats.interrupted_count,
         "missed" => spell_stats.completed_count
       }}
    end)
  end

  # ===========================================================================
  # Debuff Stats
  # ===========================================================================

  defp serialize_debuff_stats(stats) do
    applications = stats[:applications] || stats[:debuffs] || []

    %{
      "debuffs" => Enum.map(applications, &serialize_debuff/1),
      "by_player" => serialize_debuff_by_player(stats.by_player || %{}),
      "by_spell" => serialize_debuff_by_spell(stats.by_spell || %{})
    }
  end

  defp serialize_debuff(debuff) do
    %{
      "timestamp" => serialize_datetime(debuff.timestamp),
      "time_into_fight" => debuff.time_into_fight,
      "target_name" => debuff.player_name,
      "target_guid" => debuff.player_guid,
      "spell_id" => debuff.spell_id,
      "spell_name" => debuff.spell_name,
      "source_name" => debuff.source_name,
      "source_guid" => debuff.source_guid,
      "stacks" => 1
    }
  end

  defp serialize_debuff_by_player(by_player) do
    Map.new(by_player, fn {_guid, player_stats} ->
      {player_stats.player_name,
       %{
         "count" => player_stats.total_debuffs,
         "spells" => Map.keys(player_stats.by_spell)
       }}
    end)
  end

  defp serialize_debuff_by_spell(by_spell) do
    Map.new(by_spell, fn {name, spell_stats} ->
      {name,
       %{
         "spell_id" => spell_stats.spell_id,
         "applications" => spell_stats.total_applications,
         "players" => spell_stats.by_player,
         "source_guid" => spell_stats.source_guid,
         "source_name" => spell_stats.source_name
       }}
    end)
  end

  # ===========================================================================
  # Failure Stats
  # ===========================================================================

  defp serialize_failure_stats(stats) do
    %{
      "failures" => Enum.map(stats.failures, &serialize_failure/1),
      "by_player" => serialize_failures_by_player(stats.by_player),
      "by_mechanic" => serialize_failures_by_mechanic(stats.by_mechanic)
    }
  end

  defp serialize_failure(failure) do
    %{
      "player_name" => failure.player_name,
      "spell_id" => failure.spell_id,
      "spell_name" => failure.spell_name,
      "mechanic_type" => failure.mechanic_type,
      "hit_count" => failure.hit_count,
      "total_damage" => failure.total_damage,
      "first_hit_time" => failure.first_hit_time,
      "last_hit_time" => failure.last_hit_time
    }
  end

  defp serialize_failures_by_player(by_player) do
    Map.new(by_player, fn {name, failures} ->
      {name, Enum.map(failures, &serialize_failure/1)}
    end)
  end

  defp serialize_failures_by_mechanic(by_mechanic) do
    Map.new(by_mechanic, fn {name, failures} ->
      {name, Enum.map(failures, &serialize_failure/1)}
    end)
  end

  # ===========================================================================
  # Summary
  # ===========================================================================

  defp serialize_summary(summary) do
    %{
      "duration_str" => summary.duration_str,
      "result" => to_string(summary.result),
      "wipe_cause" => summary.wipe_cause,
      "critical_failures" => Enum.map(summary.critical_failures, &serialize_critical_failure/1),
      "problem_players" => Enum.map(summary.problem_players, &serialize_problem_player/1),
      "deaths_summary" => serialize_deaths_summary(summary.deaths_summary),
      "missed_interrupts" => Enum.map(summary.missed_interrupts, &serialize_missed_interrupt_summary/1),
      "top_damage_sources" => Enum.map(summary.top_damage_sources, &serialize_top_damage/1),
      "recommendations" => summary.recommendations
    }
  end

  defp serialize_critical_failure(cf) do
    %{
      "spell_name" => cf.spell_name,
      "spell_id" => cf.spell_id,
      "mechanic_type" => cf.mechanic_type,
      "failure_count" => cf.failure_count,
      "total_damage" => cf.total_damage,
      "players_involved" => cf.players_involved,
      "severity" => to_string(cf.severity)
    }
  end

  defp serialize_problem_player(pp) do
    %{
      "name" => pp.name,
      "failure_count" => pp.failure_count,
      "failed_mechanics" => pp.failed_mechanics,
      "died" => pp.died
    }
  end

  defp serialize_deaths_summary(%{total: 0} = ds) do
    %{
      "total" => ds.total,
      "first_death_time" => nil,
      "first_death_player" => nil,
      "deaths_by_cause" => %{},
      "fight_duration" => nil,
      "timeline" => []
    }
  end

  defp serialize_deaths_summary(ds) do
    %{
      "total" => ds.total,
      "first_death_time" => ds.first_death_time,
      "first_death_player" => ds[:first_death_player],
      "deaths_by_cause" => ds.deaths_by_cause,
      "fight_duration" => ds[:fight_duration],
      "timeline" => Enum.map(ds.timeline, fn {time, name} -> [time, name] end)
    }
  end

  defp serialize_missed_interrupt_summary(mi) do
    %{
      "spell_name" => mi.spell_name,
      "spell_id" => mi.spell_id,
      "missed_count" => mi.missed_count,
      "caster" => mi.caster,
      "first_miss_at" => mi.first_miss_at
    }
  end

  defp serialize_top_damage(td) do
    %{
      "ability_name" => td.ability_name,
      "ability_id" => td.ability_id,
      "total_damage" => td.total_damage,
      "hits" => td.hits,
      "players_hit" => td.players_hit
    }
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp serialize_datetime(nil), do: nil
  defp serialize_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp serialize_datetime(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
end

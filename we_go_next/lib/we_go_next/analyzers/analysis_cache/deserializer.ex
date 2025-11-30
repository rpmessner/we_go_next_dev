defmodule WeGoNext.Analyzers.AnalysisCache.Deserializer do
  @moduledoc """
  Deserializes cached analysis from JSON maps back to Elixir structures.

  Converts string keys to atoms and handles:
  - Missing keys with sensible defaults
  - DateTime parsing from ISO8601 strings
  - Building derived structures expected by the UI
  """

  @doc """
  Converts cached analysis map back to the format expected by the UI.
  Returns nil if cache is empty or nil.
  """
  def from_cache(nil), do: nil
  def from_cache(cache) when cache == %{}, do: nil

  def from_cache(cache) when is_map(cache) do
    %{
      deaths: deserialize_deaths(cache["deaths"] || []),
      damage_stats: deserialize_damage_stats(cache["damage_stats"] || %{}),
      damage_done: deserialize_damage_done(cache["damage_done"] || %{}),
      interrupt_stats: deserialize_interrupt_stats(cache["interrupt_stats"] || %{}),
      debuff_stats: deserialize_debuff_stats(cache["debuff_stats"] || %{}),
      failure_stats: deserialize_failure_stats(cache["failure_stats"] || %{}),
      summary: deserialize_summary(cache["summary"] || %{}),
      player_classes: deserialize_player_classes(cache["player_classes"] || %{})
    }
  end

  # ===========================================================================
  # Deaths
  # ===========================================================================

  defp deserialize_deaths(deaths) do
    Enum.map(deaths, fn d ->
      recap = Enum.map(d["recap"] || [], &deserialize_recap_event/1)

      %{
        player_name: d["player_name"],
        player_guid: d["player_guid"],
        time_into_fight: d["time_into_fight"],
        timestamp: parse_datetime(d["timestamp"]),
        killing_blow: deserialize_killing_blow(d["killing_blow"]),
        recap: recap
      }
    end)
  end

  defp deserialize_killing_blow(nil), do: nil

  defp deserialize_killing_blow(kb) do
    %{
      ability: kb["ability"],
      ability_id: kb["ability_id"],
      source: kb["source"],
      damage: kb["damage"],
      amount: kb["damage"],
      overkill: kb["overkill"]
    }
  end

  defp deserialize_recap_event(e) do
    %{
      timestamp: parse_datetime(e["timestamp"]),
      ability_name: e["ability_name"],
      ability_id: e["ability_id"],
      source_name: e["source_name"],
      amount: e["amount"],
      overkill: e["overkill"],
      school: e["school"]
    }
  end

  # ===========================================================================
  # Damage Stats (Taken)
  # ===========================================================================

  defp deserialize_damage_stats(stats) do
    %{
      tanks: deserialize_player_damage(stats["tanks"] || %{}),
      non_tanks: deserialize_player_damage(stats["non_tanks"] || %{}),
      by_ability: deserialize_ability_damage(stats["by_ability"] || %{}),
      total_damage: stats["total_damage"] || 0,
      avoidable_damage: stats["avoidable_damage"] || 0,
      all: build_all_players(stats)
    }
  end

  defp deserialize_player_damage(players) do
    Map.new(players, fn {name, data} ->
      {name,
       %{
         total: data["total"],
         abilities: deserialize_ability_damage(data["abilities"] || %{})
       }}
    end)
  end

  defp deserialize_ability_damage(abilities) do
    Map.new(abilities, fn {name, data} ->
      {name,
       %{
         total: data["total"],
         hits: data["hits"],
         ability_id: data["ability_id"],
         players: data["players"]
       }}
    end)
  end

  defp build_all_players(stats) do
    tanks = stats["tanks"] || %{}
    non_tanks = stats["non_tanks"] || %{}

    tank_players =
      Enum.map(tanks, fn {name, data} ->
        %{player_name: name, total: data["total"], role: :tank}
      end)

    non_tank_players =
      Enum.map(non_tanks, fn {name, data} ->
        %{player_name: name, total: data["total"], role: :dps}
      end)

    tank_players ++ non_tank_players
  end

  # ===========================================================================
  # Damage Done
  # ===========================================================================

  defp deserialize_damage_done(stats) when stats == %{} do
    %{tanks: [], dps_healers: [], all: [], fight_duration: 0, underperformers: []}
  end

  defp deserialize_damage_done(stats) do
    %{
      tanks: deserialize_player_dps_list(stats["tanks"] || []),
      dps_healers: deserialize_player_dps_list(stats["dps_healers"] || []),
      all: deserialize_player_dps_list(stats["all"] || []),
      fight_duration: stats["fight_duration"] || 0,
      underperformers: deserialize_underperformers(stats["underperformers"] || [])
    }
  end

  defp deserialize_player_dps_list(players) do
    Enum.map(players, fn p ->
      %{
        player_name: p["player_name"],
        player_guid: p["player_guid"],
        role: String.to_atom(p["role"] || "dps_healer"),
        total: p["total"] || 0,
        dps: p["dps"] || 0.0,
        active_time: p["active_time"] || 0.0,
        death_time: p["death_time"]
      }
    end)
  end

  defp deserialize_underperformers(underperformers) do
    Enum.map(underperformers, fn u ->
      %{
        player_name: u["player_name"],
        player_guid: u["player_guid"],
        dps: u["dps"] || 0.0,
        median_dps: u["median_dps"] || 0.0,
        percent_of_median: u["percent_of_median"] || 0.0,
        reason: String.to_atom(u["reason"] || "low_dps")
      }
    end)
  end

  # ===========================================================================
  # Interrupt Stats
  # ===========================================================================

  defp deserialize_interrupt_stats(stats) do
    %{
      successful: Enum.map(stats["successful"] || [], &deserialize_interrupt/1),
      missed_casts: Enum.map(stats["missed_casts"] || [], &deserialize_missed_cast/1),
      by_interrupter: deserialize_by_interrupter(stats["by_interrupter"] || %{}),
      by_spell: deserialize_by_spell_int(stats["by_spell"] || %{}),
      by_player: deserialize_by_player_int(stats["by_interrupter"] || %{})
    }
  end

  defp deserialize_interrupt(int) do
    %{
      timestamp: parse_datetime(int["timestamp"]),
      time_into_fight: int["time_into_fight"],
      interrupter_name: int["interrupter_name"],
      interrupter_guid: int["interrupter_guid"],
      target_name: int["target_name"],
      target_guid: int["target_guid"],
      interrupted_spell_id: int["interrupted_spell_id"],
      interrupted_spell_name: int["interrupted_spell_name"],
      interrupt_spell_id: int["interrupt_spell_id"],
      interrupt_spell_name: int["interrupt_spell_name"]
    }
  end

  defp deserialize_missed_cast(cast) do
    %{
      timestamp: parse_datetime(cast["timestamp"]),
      time_into_fight: cast["time_into_fight"],
      caster_name: cast["caster_name"],
      caster_guid: cast["caster_guid"],
      spell_id: cast["spell_id"],
      spell_name: cast["spell_name"]
    }
  end

  defp deserialize_by_interrupter(by_int) do
    Map.new(by_int, fn {name, data} ->
      {name,
       %{
         count: data["count"],
         spells: data["spells"]
       }}
    end)
  end

  defp deserialize_by_player_int(by_int) do
    Map.new(by_int, fn {name, data} ->
      {name,
       %{
         player_name: name,
         total_interrupts: data["count"],
         by_spell: data["spells"] || %{}
       }}
    end)
  end

  defp deserialize_by_spell_int(by_spell) do
    Map.new(by_spell, fn {name, data} ->
      {name,
       %{
         spell_id: data["spell_id"],
         interrupted: data["interrupted"],
         missed: data["missed"]
       }}
    end)
  end

  # ===========================================================================
  # Debuff Stats
  # ===========================================================================

  defp deserialize_debuff_stats(stats) do
    %{
      debuffs: Enum.map(stats["debuffs"] || [], &deserialize_debuff/1),
      by_player: deserialize_debuff_by_player(stats["by_player"] || %{}),
      by_spell: deserialize_debuff_by_spell(stats["by_spell"] || %{})
    }
  end

  defp deserialize_debuff(d) do
    %{
      timestamp: parse_datetime(d["timestamp"]),
      time_into_fight: d["time_into_fight"],
      target_name: d["target_name"],
      target_guid: d["target_guid"],
      spell_id: d["spell_id"],
      spell_name: d["spell_name"],
      source_name: d["source_name"],
      source_guid: d["source_guid"],
      stacks: d["stacks"]
    }
  end

  defp deserialize_debuff_by_player(by_player) do
    Map.new(by_player, fn {name, data} ->
      {name,
       %{
         count: data["count"],
         spells: data["spells"],
         debuffs:
           Enum.map(data["spells"] || [], fn spell_name ->
             %{spell_name: spell_name}
           end)
       }}
    end)
  end

  defp deserialize_debuff_by_spell(by_spell) do
    Map.new(by_spell, fn {name, data} ->
      players_map = data["players"] || %{}

      {name,
       %{
         spell_id: data["spell_id"],
         total_applications: data["applications"],
         players_affected: map_size(players_map),
         by_player: players_map,
         source_guid: data["source_guid"],
         source_name: data["source_name"]
       }}
    end)
  end

  # ===========================================================================
  # Failure Stats
  # ===========================================================================

  defp deserialize_failure_stats(stats) do
    failures = Enum.map(stats["failures"] || [], &deserialize_failure/1)

    %{
      failures: failures,
      by_player: deserialize_failures_by_player(stats["by_player"] || %{}),
      by_mechanic: deserialize_failures_by_mechanic(stats["by_mechanic"] || %{}),
      summary: %{
        total_failures: length(failures),
        players_with_failures: stats["by_player"] |> Map.keys() |> length(),
        mechanics_failed: stats["by_mechanic"] |> Map.keys() |> length()
      }
    }
  end

  defp deserialize_failure(f) do
    %{
      player_name: f["player_name"],
      spell_id: f["spell_id"],
      spell_name: f["spell_name"],
      mechanic_type: f["mechanic_type"],
      hit_count: f["hit_count"],
      total_damage: f["total_damage"],
      first_hit_time: f["first_hit_time"],
      last_hit_time: f["last_hit_time"]
    }
  end

  defp deserialize_failures_by_player(by_player) do
    Map.new(by_player, fn {name, failures} ->
      {name, Enum.map(failures, &deserialize_failure/1)}
    end)
  end

  defp deserialize_failures_by_mechanic(by_mechanic) do
    Map.new(by_mechanic, fn {name, failures} ->
      {name, Enum.map(failures, &deserialize_failure/1)}
    end)
  end

  # ===========================================================================
  # Summary
  # ===========================================================================

  defp deserialize_summary(s) do
    %{
      duration_str: s["duration_str"],
      result: String.to_atom(s["result"] || "wipe"),
      wipe_cause: s["wipe_cause"],
      critical_failures: Enum.map(s["critical_failures"] || [], &deserialize_critical_failure/1),
      problem_players: Enum.map(s["problem_players"] || [], &deserialize_problem_player/1),
      deaths_summary: deserialize_deaths_summary(s["deaths_summary"] || %{}),
      missed_interrupts: Enum.map(s["missed_interrupts"] || [], &deserialize_missed_interrupt_summary/1),
      top_damage_sources: Enum.map(s["top_damage_sources"] || [], &deserialize_top_damage/1),
      recommendations: s["recommendations"] || []
    }
  end

  defp deserialize_critical_failure(cf) do
    %{
      spell_name: cf["spell_name"],
      spell_id: cf["spell_id"],
      mechanic_type: cf["mechanic_type"],
      failure_count: cf["failure_count"],
      total_damage: cf["total_damage"],
      players_involved: cf["players_involved"],
      severity: String.to_atom(cf["severity"] || "low")
    }
  end

  defp deserialize_problem_player(pp) do
    %{
      name: pp["name"],
      failure_count: pp["failure_count"],
      failed_mechanics: pp["failed_mechanics"],
      died: pp["died"]
    }
  end

  defp deserialize_deaths_summary(ds) do
    %{
      total: ds["total"] || 0,
      first_death_time: ds["first_death_time"],
      first_death_player: ds["first_death_player"],
      deaths_by_cause: ds["deaths_by_cause"] || %{},
      fight_duration: ds["fight_duration"],
      timeline: Enum.map(ds["timeline"] || [], fn [time, name] -> {time, name} end)
    }
  end

  defp deserialize_missed_interrupt_summary(mi) do
    %{
      spell_name: mi["spell_name"],
      spell_id: mi["spell_id"],
      missed_count: mi["missed_count"],
      caster: mi["caster"],
      first_miss_at: mi["first_miss_at"]
    }
  end

  defp deserialize_top_damage(td) do
    %{
      ability_name: td["ability_name"],
      ability_id: td["ability_id"],
      total_damage: td["total_damage"],
      hits: td["hits"],
      players_hit: td["players_hit"]
    }
  end

  # ===========================================================================
  # Player Classes
  # ===========================================================================

  defp deserialize_player_classes(classes) when is_map(classes) do
    Map.new(classes, fn {name, class_id} ->
      {name, if(is_integer(class_id), do: class_id, else: String.to_integer(class_id))}
    end)
  end

  defp deserialize_player_classes(_), do: %{}

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} ->
        dt

      _ ->
        case NaiveDateTime.from_iso8601(str) do
          {:ok, ndt} -> ndt
          _ -> nil
        end
    end
  end

  defp parse_datetime(other), do: other
end

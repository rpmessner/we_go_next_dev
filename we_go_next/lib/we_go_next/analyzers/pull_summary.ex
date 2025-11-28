defmodule WeGoNext.Analyzers.PullSummary do
  @moduledoc """
  Aggregates all analyzer outputs into a cohesive between-pull report.

  Designed for raid leaders to understand what went wrong after a pull:
  - What killed us? (wipe cause analysis)
  - Who failed mechanics? (targeted coaching)
  - What needs improvement? (priority fixes)
  """

  alias WeGoNext.Encounter
  alias WeGoNext.Analyzers.{DeathAnalyzer, DamageTakenAnalyzer, InterruptAnalyzer, DebuffAnalyzer, FailureAnalyzer}

  defmodule Summary do
    @moduledoc "Complete pull summary with all diagnostic data"
    defstruct [
      :encounter,
      :duration_str,
      :result,                  # :kill or :wipe
      :wipe_cause,              # "killed by X" or nil
      :critical_failures,       # Top mechanic failures by impact
      :problem_players,         # Players needing coaching
      :deaths_summary,          # Condensed death info
      :missed_interrupts,       # Which casts got through
      :top_damage_sources,      # What's hitting the raid hard
      :recommendations,         # Actionable next steps
      :raw_stats                # All analyzer outputs for detail views
    ]
  end

  @doc """
  Generates a complete pull summary from all analyzers.

  Takes an encounter and optional pre-computed analyzer results.
  If analyzer results are not provided, runs all analyzers fresh.
  """
  def summarize(%Encounter{} = encounter, opts \\ []) do
    # Use provided stats or run analyzers
    deaths = opts[:deaths] || DeathAnalyzer.analyze(encounter)
    damage_stats = opts[:damage_stats] || DamageTakenAnalyzer.analyze(encounter)
    interrupt_stats = opts[:interrupt_stats] || InterruptAnalyzer.analyze(encounter)
    debuff_stats = opts[:debuff_stats] || DebuffAnalyzer.analyze(encounter)
    failure_stats = opts[:failure_stats] || FailureAnalyzer.analyze(encounter)

    %Summary{
      encounter: encounter,
      duration_str: format_duration(encounter.fight_time_ms),
      result: if(encounter.success, do: :kill, else: :wipe),
      wipe_cause: identify_wipe_cause(encounter, deaths),
      critical_failures: extract_critical_failures(failure_stats),
      problem_players: identify_problem_players(failure_stats, deaths),
      deaths_summary: summarize_deaths(deaths, encounter),
      missed_interrupts: summarize_missed_interrupts(interrupt_stats),
      top_damage_sources: extract_top_damage(damage_stats),
      recommendations: generate_recommendations(failure_stats, interrupt_stats, deaths),
      raw_stats: %{
        deaths: deaths,
        damage_stats: damage_stats,
        interrupt_stats: interrupt_stats,
        debuff_stats: debuff_stats,
        failure_stats: failure_stats
      }
    }
  end

  # What killed us?
  defp identify_wipe_cause(encounter, deaths) do
    cond do
      encounter.success ->
        nil

      Enum.empty?(deaths) ->
        "Unknown (no deaths recorded)"

      true ->
        # Find the last death - often indicates what ended the pull
        last_death = List.last(deaths)

        if last_death.killing_blow do
          "#{last_death.player_name} killed by #{last_death.killing_blow.ability}"
        else
          "#{last_death.player_name} died (unknown cause)"
        end
    end
  end

  # Top failures ranked by number of occurrences
  defp extract_critical_failures(%{by_mechanic: by_mechanic, failures: failures}) do
    if Enum.empty?(failures) do
      []
    else
      by_mechanic
      |> Enum.sort_by(fn {_, fails} -> -length(fails) end)
      |> Enum.take(3)
      |> Enum.map(fn {spell_name, fails} ->
        first_fail = List.first(fails)

        %{
          spell_name: spell_name,
          mechanic_type: first_fail.mechanic_type,
          failure_count: length(fails),
          total_damage: fails |> Enum.map(& &1.total_damage) |> Enum.sum(),
          players_involved: fails |> Enum.map(& &1.player_name) |> Enum.uniq() |> Enum.reject(&(&1 == "Raid")),
          severity: determine_severity(length(fails))
        }
      end)
    end
  end

  # Which players need coaching?
  defp identify_problem_players(%{by_player: by_player}, deaths) do
    death_set = deaths |> Enum.map(& &1.player_name) |> MapSet.new()

    # Get players with failures
    players_with_issues =
      by_player
      |> Enum.reject(fn {name, _} -> name == "Raid" end)
      |> Enum.map(fn {name, failures} ->
        %{
          name: name,
          failure_count: length(failures),
          failed_mechanics: failures |> Enum.map(& &1.spell_name) |> Enum.uniq(),
          died: MapSet.member?(death_set, name)
        }
      end)

    # Add players who died but didn't fail mechanics
    players_who_died =
      deaths
      |> Enum.map(& &1.player_name)
      |> Enum.reject(fn name -> Enum.any?(players_with_issues, &(&1.name == name)) end)
      |> Enum.map(fn name ->
        %{
          name: name,
          failure_count: 0,
          failed_mechanics: [],
          died: true
        }
      end)

    (players_with_issues ++ players_who_died)
    |> Enum.sort_by(fn p -> {-p.failure_count, if(p.died, do: 0, else: 1)} end)
    |> Enum.take(5)
  end

  # Condensed death info
  defp summarize_deaths(deaths, encounter) do
    if Enum.empty?(deaths) do
      %{
        total: 0,
        first_death_time: nil,
        deaths_by_cause: %{},
        timeline: []
      }
    else
      deaths_by_cause =
        deaths
        |> Enum.group_by(fn death ->
          if death.killing_blow, do: death.killing_blow.ability, else: "Unknown"
        end)
        |> Enum.map(fn {cause, death_list} -> {cause, length(death_list)} end)
        |> Enum.sort_by(fn {_, count} -> -count end)
        |> Map.new()

      first_death = List.first(deaths)

      %{
        total: length(deaths),
        first_death_time: first_death.time_into_fight,
        first_death_player: first_death.player_name,
        deaths_by_cause: deaths_by_cause,
        fight_duration: encounter.fight_time_ms / 1000,
        timeline: deaths |> Enum.map(fn d -> {d.time_into_fight, d.player_name} end)
      }
    end
  end

  # Condensed interrupt summary
  defp summarize_missed_interrupts(%{missed_casts: missed}) do
    if Enum.empty?(missed) do
      []
    else
      missed
      |> Enum.group_by(& &1.spell_name)
      |> Enum.map(fn {spell_name, casts} ->
        first_cast = List.first(casts)

        %{
          spell_name: spell_name,
          spell_id: first_cast.spell_id,
          missed_count: length(casts),
          caster: first_cast.caster_name,
          first_miss_at: first_cast.time_into_fight
        }
      end)
      |> Enum.sort_by(& &1.missed_count, :desc)
      |> Enum.take(5)
    end
  end

  # Top damage sources hitting non-tanks
  defp extract_top_damage(damage_stats) do
    DamageTakenAnalyzer.top_avoidable_abilities(damage_stats, 5)
    |> Enum.map(fn {name, %{total: total, hits: hits, ability_id: ability_id, players: players}} ->
      %{
        ability_name: name,
        ability_id: ability_id,
        total_damage: total,
        hits: hits,
        players_hit: players
      }
    end)
  end

  # Generate actionable recommendations based on the data
  defp generate_recommendations(failure_stats, interrupt_stats, deaths) do
    recommendations = []

    # Check for avoidable damage issues
    avoidable_failures =
      failure_stats.failures
      |> Enum.filter(&(&1.mechanic_type == "avoidable"))

    recommendations =
      if length(avoidable_failures) >= 3 do
        abilities = avoidable_failures |> Enum.map(& &1.spell_name) |> Enum.uniq() |> Enum.take(2) |> Enum.join(", ")
        ["Improve positioning to avoid #{abilities}" | recommendations]
      else
        recommendations
      end

    # Check for interrupt issues
    recommendations =
      if length(interrupt_stats.missed_casts) >= 2 do
        spells = interrupt_stats.missed_casts |> Enum.map(& &1.spell_name) |> Enum.uniq() |> Enum.take(2) |> Enum.join(", ")
        ["Tighten interrupt rotation on #{spells}" | recommendations]
      else
        recommendations
      end

    # Check for early deaths
    first_death = List.first(deaths)

    recommendations =
      if first_death && first_death.time_into_fight < 30 do
        ["Investigate early death: #{first_death.player_name} died at #{format_time(first_death.time_into_fight)}" | recommendations]
      else
        recommendations
      end

    # Check for tank deaths
    tank_deaths = Enum.filter(deaths, fn d ->
      d.killing_blow && d.killing_blow.ability == "Melee"
    end)

    recommendations =
      if length(tank_deaths) > 0 do
        ["Review tank healing/cooldowns - tank death from melee damage" | recommendations]
      else
        recommendations
      end

    Enum.reverse(recommendations) |> Enum.take(4)
  end

  defp determine_severity(failure_count) do
    cond do
      failure_count >= 5 -> :critical
      failure_count >= 3 -> :high
      failure_count >= 2 -> :medium
      true -> :low
    end
  end

  defp format_duration(nil), do: "0:00"

  defp format_duration(ms) when is_integer(ms) do
    seconds = div(ms, 1000)
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp format_time(seconds) do
    minutes = trunc(seconds / 60)
    secs = trunc(rem(trunc(seconds), 60))
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  @doc """
  Formats the summary for CLI display.
  """
  def format_summary(%Summary{} = summary) do
    lines = [
      "",
      String.duplicate("=", 70),
      "PULL SUMMARY: #{summary.encounter.name} (#{summary.encounter.difficulty_name})",
      String.duplicate("=", 70),
      "",
      "Duration: #{summary.duration_str}  |  Result: #{format_result(summary.result)}",
      if(summary.wipe_cause, do: "Wipe Cause: #{summary.wipe_cause}", else: nil),
      "",
      format_deaths_section(summary.deaths_summary),
      "",
      format_failures_section(summary.critical_failures),
      "",
      format_players_section(summary.problem_players),
      "",
      format_interrupts_section(summary.missed_interrupts),
      "",
      format_recommendations_section(summary.recommendations),
      String.duplicate("=", 70)
    ]

    lines
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp format_result(:kill), do: "KILL"
  defp format_result(:wipe), do: "WIPE"

  defp format_deaths_section(%{total: 0}), do: "DEATHS: None"

  defp format_deaths_section(deaths) do
    causes =
      deaths.deaths_by_cause
      |> Enum.take(3)
      |> Enum.map(fn {cause, count} -> "#{cause} (#{count})" end)
      |> Enum.join(", ")

    [
      "DEATHS: #{deaths.total} total",
      "  First death: #{deaths.first_death_player} at #{format_time(deaths.first_death_time)}",
      "  Causes: #{causes}"
    ]
    |> Enum.join("\n")
  end

  defp format_failures_section([]), do: "MECHANIC FAILURES: None - great execution!"

  defp format_failures_section(failures) do
    header = "MECHANIC FAILURES (#{length(failures)} tracked):"

    lines =
      failures
      |> Enum.map(fn f ->
        players = f.players_involved |> Enum.take(3) |> Enum.join(", ")
        severity_str = "[#{String.upcase(to_string(f.severity))}]"
        "  #{severity_str} #{f.spell_name}: #{f.failure_count} failures (#{players})"
      end)

    [header | lines] |> Enum.join("\n")
  end

  defp format_players_section([]), do: "PLAYERS NEEDING COACHING: None"

  defp format_players_section(players) do
    header = "PLAYERS NEEDING COACHING:"

    lines =
      players
      |> Enum.map(fn p ->
        death_str = if p.died, do: " [DIED]", else: ""
        mechanics_str =
          if p.failure_count > 0 do
            " - failed: #{Enum.join(p.failed_mechanics, ", ")}"
          else
            ""
          end

        "  #{p.name}#{death_str}#{mechanics_str}"
      end)

    [header | lines] |> Enum.join("\n")
  end

  defp format_interrupts_section([]), do: "MISSED INTERRUPTS: None"

  defp format_interrupts_section(missed) do
    header = "MISSED INTERRUPTS:"

    lines =
      missed
      |> Enum.map(fn m ->
        "  #{m.spell_name}: #{m.missed_count} missed (first at #{format_time(m.first_miss_at)})"
      end)

    [header | lines] |> Enum.join("\n")
  end

  defp format_recommendations_section([]), do: "NEXT PULL FOCUS: Keep up the good work!"

  defp format_recommendations_section(recs) do
    header = "NEXT PULL FOCUS:"

    lines =
      recs
      |> Enum.with_index(1)
      |> Enum.map(fn {rec, idx} -> "  #{idx}. #{rec}" end)

    [header | lines] |> Enum.join("\n")
  end
end

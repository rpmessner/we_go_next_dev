defmodule CombatLogParser do
  @moduledoc """
  Main module for parsing and analyzing WoW combat logs.
  """

  alias CombatLogParser.{LogReader, DamageAnalyzer, Encounter}

  @doc """
  Parses a combat log file and returns all encounters.
  """
  def parse(log_path) do
    LogReader.parse_file(log_path)
  end

  @doc """
  Analyzes damage for a specific player across all encounters.
  """
  def analyze_damage(encounters, player_name) when is_list(encounters) do
    Enum.map(encounters, fn encounter ->
      {encounter, DamageAnalyzer.analyze(encounter, player_name)}
    end)
  end

  @doc """
  Prints a formatted summary of encounters and player performance.
  """
  def print_summary(encounters, player_name) do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("ENCOUNTER SUMMARY")
    IO.puts(String.duplicate("=", 80))

    encounters
    |> analyze_damage(player_name)
    |> Enum.with_index(1)
    |> Enum.each(fn {{encounter, stats}, index} ->
      print_encounter(index, encounter, player_name, stats)
    end)
  end

  defp print_encounter(index, encounter, player_name, stats) do
    status = if encounter.success, do: "KILL", else: "WIPE"
    duration = Encounter.fight_time_sec(encounter)
    start_time = NaiveDateTime.to_time(encounter.start_time)

    IO.puts("\n#{index}. #{encounter.name} (#{encounter.difficulty_name})")
    IO.puts("   Status: #{status}")
    IO.puts("   Duration: #{Float.round(duration, 1)}s")
    IO.puts("   Start: #{Time.to_string(start_time)}")

    IO.puts("\n   #{player_name}'s Performance:")
    IO.puts("   - Total Damage: #{format_number(stats.total_damage)}")
    IO.puts("   - DPS: #{format_number(round(stats.dps))}")
    IO.puts("   - Damage Events: #{format_number(stats.damage_events)}")

    if length(stats.top_abilities) > 0 do
      IO.puts("\n   Top Abilities:")
      stats.top_abilities
      |> Enum.take(5)
      |> Enum.each(fn {ability, dmg} ->
        pct = if stats.total_damage > 0, do: dmg / stats.total_damage * 100, else: 0.0
        IO.puts("     - #{ability}: #{format_number(dmg)} (#{Float.round(pct, 1)}%)")
      end)
    end
  end

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end
  defp format_number(num), do: to_string(num)
end

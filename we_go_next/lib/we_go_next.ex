defmodule WeGoNext do
  @moduledoc """
  Legacy diagnostic helpers for parsing and analyzing WoW combat logs.

  These analyzer-backed functions are retained for command-line inspection and
  silver projection parity checks. New UI and read-model work should use the
  bronze/silver/gold/rules pipeline instead of adding dependencies here.
  """

  alias WeGoNext.{CombatLogParser, Encounter}
  alias WeGoNext.Analyzers.{DeathAnalyzer, DamageTakenAnalyzer, InterruptAnalyzer, DebuffAnalyzer}

  @doc """
  Scans a combat log file and returns encounter boundaries.
  """
  def parse(log_path) do
    case CombatLogParser.scan_boundaries(log_path, 0) do
      {:ok, boundaries, _end_byte} ->
        encounters =
          Enum.map(boundaries, fn b ->
            %Encounter{
              id: b.wow_encounter_id,
              name: b.name,
              difficulty_id: b.difficulty_id,
              difficulty_name: Encounter.difficulty_name_for(b.difficulty_id),
              group_size: b.group_size,
              instance_id: b.instance_id,
              success: b.success,
              fight_time_ms: b.fight_time_ms,
              events: []
            }
          end)
        {:ok, encounters}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Analyzes deaths across all encounters or a single encounter.

  When given a list of encounters, returns a list of {encounter, deaths} tuples.
  When given a single encounter, returns a list of deaths.
  """
  def analyze_deaths(encounters) when is_list(encounters) do
    Enum.map(encounters, fn encounter ->
      {encounter, DeathAnalyzer.analyze(encounter)}
    end)
  end

  def analyze_deaths(%Encounter{} = encounter) do
    DeathAnalyzer.analyze(encounter)
  end

  @doc """
  Prints a death summary for all encounters.
  """
  def print_death_summary(encounters) do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("DEATH SUMMARY")
    IO.puts(String.duplicate("=", 80))

    encounters
    |> analyze_deaths()
    |> Enum.with_index(1)
    |> Enum.each(fn {{encounter, deaths}, index} ->
      print_encounter_deaths(index, encounter, deaths)
    end)
  end

  defp print_encounter_deaths(index, encounter, deaths) do
    status = if encounter.success, do: "KILL", else: "WIPE"
    death_count = length(deaths)

    IO.puts("\n#{index}. #{encounter.name} (#{encounter.difficulty_name}) - #{status}")
    IO.puts("   Deaths: #{death_count}")

    if death_count > 0 do
      IO.puts("")
      IO.puts(DeathAnalyzer.format_deaths(deaths))
    end
  end

  @doc """
  Analyzes damage taken across all encounters or a single encounter.

  When given a list of encounters, returns a list of {encounter, damage_stats} tuples.
  When given a single encounter, returns a list of player damage stats.
  """
  def analyze_damage_taken(encounters) when is_list(encounters) do
    Enum.map(encounters, fn encounter ->
      {encounter, DamageTakenAnalyzer.analyze(encounter)}
    end)
  end

  def analyze_damage_taken(%Encounter{} = encounter) do
    DamageTakenAnalyzer.analyze(encounter)
  end

  @doc """
  Prints a damage taken summary for all encounters.
  """
  def print_damage_taken_summary(encounters, opts \\ []) do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("DAMAGE TAKEN SUMMARY")
    IO.puts(String.duplicate("=", 80))

    encounters
    |> analyze_damage_taken()
    |> Enum.with_index(1)
    |> Enum.each(fn {{encounter, damage_stats}, index} ->
      print_encounter_damage(index, encounter, damage_stats, opts)
    end)
  end

  defp print_encounter_damage(index, encounter, damage_stats, opts) do
    status = if encounter.success, do: "KILL", else: "WIPE"
    duration = Encounter.fight_time_sec(encounter)
    duration_str = format_duration(duration)

    IO.puts("\n#{index}. #{encounter.name} (#{encounter.difficulty_name}) - #{status} (#{duration_str})")

    if Enum.empty?(damage_stats.all) do
      IO.puts("   No damage taken data")
    else
      IO.puts("")
      IO.puts(DamageTakenAnalyzer.format_damage_taken(damage_stats, opts))

      # Show top damaging abilities for DPS/healers (avoidable damage)
      IO.puts("\n   Top Avoidable Abilities (DPS/Healers only):")
      top_avoidable = DamageTakenAnalyzer.top_avoidable_abilities(damage_stats, 5)
      IO.puts(DamageTakenAnalyzer.format_top_abilities_summary(top_avoidable))
    end
  end

  defp format_duration(seconds) do
    minutes = trunc(seconds / 60)
    secs = trunc(rem(trunc(seconds), 60))
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  @doc """
  Analyzes interrupts across all encounters or a single encounter.

  When given a list of encounters, returns a list of {encounter, interrupt_stats} tuples.
  When given a single encounter, returns interrupt stats.
  """
  def analyze_interrupts(encounters) when is_list(encounters) do
    Enum.map(encounters, fn encounter ->
      {encounter, InterruptAnalyzer.analyze(encounter)}
    end)
  end

  def analyze_interrupts(%Encounter{} = encounter) do
    InterruptAnalyzer.analyze(encounter)
  end

  @doc """
  Prints an interrupt summary for all encounters.
  """
  def print_interrupt_summary(encounters) do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("INTERRUPT SUMMARY")
    IO.puts(String.duplicate("=", 80))

    encounters
    |> analyze_interrupts()
    |> Enum.with_index(1)
    |> Enum.each(fn {{encounter, interrupt_stats}, index} ->
      print_encounter_interrupts(index, encounter, interrupt_stats)
    end)
  end

  defp print_encounter_interrupts(index, encounter, interrupt_stats) do
    status = if encounter.success, do: "KILL", else: "WIPE"
    duration = Encounter.fight_time_sec(encounter)
    duration_str = format_duration(duration)

    total_interrupts =
      interrupt_stats.by_player
      |> Map.values()
      |> Enum.map(& &1.total_interrupts)
      |> Enum.sum()

    missed_count = length(interrupt_stats.missed_casts)

    IO.puts("\n#{index}. #{encounter.name} (#{encounter.difficulty_name}) - #{status} (#{duration_str})")
    IO.puts("   Total Interrupts: #{total_interrupts}, Missed Kicks: #{missed_count}")

    if total_interrupts > 0 or missed_count > 0 do
      IO.puts("")
      IO.puts(InterruptAnalyzer.format_interrupt_summary(interrupt_stats))
    end
  end

  @doc """
  Analyzes debuffs across all encounters or a single encounter.

  When given a list of encounters, returns a list of {encounter, debuff_stats} tuples.
  When given a single encounter, returns debuff stats.
  """
  def analyze_debuffs(encounters) when is_list(encounters) do
    Enum.map(encounters, fn encounter ->
      {encounter, DebuffAnalyzer.analyze(encounter)}
    end)
  end

  def analyze_debuffs(%Encounter{} = encounter) do
    DebuffAnalyzer.analyze(encounter)
  end

  @doc """
  Prints a debuff summary for all encounters.
  """
  def print_debuff_summary(encounters, opts \\ []) do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("DEBUFF SUMMARY")
    IO.puts(String.duplicate("=", 80))

    encounters
    |> analyze_debuffs()
    |> Enum.with_index(1)
    |> Enum.each(fn {{encounter, debuff_stats}, index} ->
      print_encounter_debuffs(index, encounter, debuff_stats, opts)
    end)
  end

  defp print_encounter_debuffs(index, encounter, debuff_stats, opts) do
    status = if encounter.success, do: "KILL", else: "WIPE"
    duration = Encounter.fight_time_sec(encounter)
    duration_str = format_duration(duration)

    total_debuffs = length(debuff_stats.applications)
    unique_debuffs = map_size(debuff_stats.by_spell)

    IO.puts("\n#{index}. #{encounter.name} (#{encounter.difficulty_name}) - #{status} (#{duration_str})")
    IO.puts("   Total Debuff Applications: #{total_debuffs}, Unique Debuffs: #{unique_debuffs}")

    if total_debuffs > 0 do
      IO.puts("")
      IO.puts(DebuffAnalyzer.format_debuff_summary(debuff_stats, opts))
    end
  end
end

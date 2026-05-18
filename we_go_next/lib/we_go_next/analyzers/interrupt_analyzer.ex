defmodule WeGoNext.Analyzers.InterruptAnalyzer do
  @moduledoc """
  Analyzes interrupts in combat encounters.

  Tracks successful interrupts by player and identifies enemy casts that
  went off uninterrupted (missed kicks). Critical for both raid and M+
  where missed interrupts often lead to wipes.
  """

  alias WeGoNext.Encounter

  defmodule Interrupt do
    @moduledoc "Represents a successful interrupt"
    defstruct [
      :timestamp,
      :time_into_fight,
      :interrupter_name,
      :interrupter_guid,
      :target_name,
      :target_guid,
      # The interrupt ability used (Kick, Pummel, etc.)
      :interrupt_spell_name,
      :interrupt_spell_id,
      # The enemy ability that was interrupted
      :interrupted_spell_name,
      :interrupted_spell_id
    ]
  end

  defmodule EnemyCast do
    @moduledoc "Represents an enemy cast (for tracking missed interrupts)"
    defstruct [
      :timestamp,
      :time_into_fight,
      :caster_name,
      :caster_guid,
      :spell_name,
      :spell_id,
      # true if this cast was later interrupted
      :was_interrupted
    ]
  end

  defmodule PlayerStats do
    @moduledoc "Interrupt statistics for a single player"
    defstruct [
      :player_name,
      :player_guid,
      total_interrupts: 0,
      # %{spell_name => count}
      by_spell: %{}
    ]
  end

  defmodule SpellStats do
    @moduledoc "Statistics for a single enemy ability"
    defstruct [
      :spell_name,
      :spell_id,
      total_casts: 0,
      interrupted_count: 0,
      # Casts that went off (missed interrupts)
      completed_count: 0
    ]
  end

  @doc """
  Analyzes an encounter and returns interrupt statistics.

  Returns a map with:
    - :interrupts - list of %Interrupt{} in chronological order
    - :by_player - map of player_guid => %PlayerStats{}
    - :by_spell - map of spell_name => %SpellStats{} (enemy abilities)
    - :missed_casts - list of enemy casts that completed (no interrupt)
  """
  def analyze(%Encounter{} = encounter) do
    # Events are now loaded from DB in chronological order
    events = encounter.events

    # First pass: collect all SPELL_CAST_START events (potential interrupt targets)
    # and SPELL_INTERRUPT events
    {interrupts, cast_starts, cast_successes} =
      Enum.reduce(events, {[], %{}, []}, fn event, acc ->
        process_event(event, acc)
      end)

    # Match cast starts with interrupts or successes to find missed kicks
    {spell_stats, missed_casts} = analyze_casts(cast_starts, cast_successes, interrupts)

    # Build player stats from interrupts
    player_stats = build_player_stats(interrupts)

    %{
      interrupts: Enum.reverse(interrupts),
      by_player: player_stats,
      by_spell: spell_stats,
      missed_casts: missed_casts
    }
  end

  # Process SPELL_INTERRUPT events - now using normalized event fields
  defp process_event(
         %{type: "SPELL_INTERRUPT"} = event,
         {interrupts, cast_starts, cast_successes}
       ) do
    interrupter_guid = event.source_guid
    interrupter_name = event.source_name
    target_guid = event.target_guid
    target_name = event.target_name
    interrupt_spell_id = event.spell_id
    interrupt_spell_name = event.spell_name
    interrupted_spell_id = event.extra_spell_id
    interrupted_spell_name = event.extra_spell_name

    # Only track player interrupts
    if player_guid?(interrupter_guid) do
      interrupt = %Interrupt{
        timestamp: event.timestamp,
        time_into_fight: event.time_into_fight,
        interrupter_name: interrupter_name,
        interrupter_guid: interrupter_guid,
        target_name: target_name,
        target_guid: target_guid,
        interrupt_spell_name: interrupt_spell_name,
        interrupt_spell_id: interrupt_spell_id,
        interrupted_spell_name: interrupted_spell_name,
        interrupted_spell_id: interrupted_spell_id
      }

      {[interrupt | interrupts], cast_starts, cast_successes}
    else
      {interrupts, cast_starts, cast_successes}
    end
  end

  # Process SPELL_CAST_START - enemy begins casting (interruptible)
  defp process_event(
         %{type: "SPELL_CAST_START"} = event,
         {interrupts, cast_starts, cast_successes}
       ) do
    caster_guid = event.source_guid
    caster_name = event.source_name
    spell_id = event.spell_id
    spell_name = event.spell_name

    # Only track NPC casts (enemies we might want to interrupt)
    if npc_guid?(caster_guid) do
      cast_info = %{
        timestamp: event.timestamp,
        time_into_fight: event.time_into_fight,
        caster_name: caster_name,
        caster_guid: caster_guid,
        spell_name: spell_name,
        spell_id: spell_id
      }

      key = {caster_guid, spell_id}
      updated_starts = Map.put(cast_starts, key, cast_info)
      {interrupts, updated_starts, cast_successes}
    else
      {interrupts, cast_starts, cast_successes}
    end
  end

  # Process SPELL_CAST_SUCCESS - cast completed (missed interrupt if was interruptible)
  defp process_event(
         %{type: "SPELL_CAST_SUCCESS"} = event,
         {interrupts, cast_starts, cast_successes}
       ) do
    caster_guid = event.source_guid
    caster_name = event.source_name
    spell_id = event.spell_id
    spell_name = event.spell_name

    if npc_guid?(caster_guid) do
      cast_info = %{
        timestamp: event.timestamp,
        time_into_fight: event.time_into_fight,
        caster_name: caster_name,
        caster_guid: caster_guid,
        spell_name: spell_name,
        spell_id: spell_id
      }

      {interrupts, cast_starts, [cast_info | cast_successes]}
    else
      {interrupts, cast_starts, cast_successes}
    end
  end

  defp process_event(_event, acc), do: acc

  # Analyze casts to determine which were interrupted vs completed
  defp analyze_casts(_cast_starts, cast_successes, interrupts) do
    # Build set of interrupted spells (by spell_id)
    interrupted_spell_ids =
      interrupts
      |> Enum.map(& &1.interrupted_spell_id)
      |> MapSet.new()

    # Group cast successes by spell to build stats
    spell_stats =
      cast_successes
      |> Enum.group_by(& &1.spell_name)
      |> Enum.map(fn {spell_name, casts} ->
        spell_id = List.first(casts).spell_id
        _was_ever_interrupted = MapSet.member?(interrupted_spell_ids, spell_id)

        # Count interrupts for this specific spell
        interrupt_count =
          interrupts
          |> Enum.count(&(&1.interrupted_spell_id == spell_id))

        {spell_name,
         %SpellStats{
           spell_name: spell_name,
           spell_id: spell_id,
           total_casts: length(casts) + interrupt_count,
           interrupted_count: interrupt_count,
           completed_count: length(casts)
         }}
      end)
      |> Enum.into(%{})

    # Also add spells that were ONLY interrupted (never completed)
    spell_stats =
      interrupts
      |> Enum.group_by(& &1.interrupted_spell_name)
      |> Enum.reduce(spell_stats, fn {spell_name, spell_interrupts}, acc ->
        if Map.has_key?(acc, spell_name) do
          acc
        else
          spell_id = List.first(spell_interrupts).interrupted_spell_id

          Map.put(acc, spell_name, %SpellStats{
            spell_name: spell_name,
            spell_id: spell_id,
            total_casts: length(spell_interrupts),
            interrupted_count: length(spell_interrupts),
            completed_count: 0
          })
        end
      end)

    # Build list of missed casts (casts that completed for spells we interrupted at least once)
    missed_casts =
      cast_successes
      |> Enum.filter(fn cast ->
        MapSet.member?(interrupted_spell_ids, cast.spell_id)
      end)
      |> Enum.map(fn cast ->
        %EnemyCast{
          timestamp: cast.timestamp,
          time_into_fight: cast.time_into_fight,
          caster_name: cast.caster_name,
          caster_guid: cast.caster_guid,
          spell_name: cast.spell_name,
          spell_id: cast.spell_id,
          was_interrupted: false
        }
      end)
      |> Enum.sort_by(& &1.time_into_fight)

    {spell_stats, missed_casts}
  end

  # Build player interrupt statistics
  defp build_player_stats(interrupts) do
    interrupts
    |> Enum.reduce(%{}, fn interrupt, acc ->
      guid = interrupt.interrupter_guid

      Map.update(acc, guid, new_player_stats(interrupt), fn stats ->
        %{
          stats
          | total_interrupts: stats.total_interrupts + 1,
            by_spell: Map.update(stats.by_spell, interrupt.interrupted_spell_name, 1, &(&1 + 1))
        }
      end)
    end)
  end

  defp new_player_stats(%Interrupt{} = interrupt) do
    %PlayerStats{
      player_name: interrupt.interrupter_name,
      player_guid: interrupt.interrupter_guid,
      total_interrupts: 1,
      by_spell: %{interrupt.interrupted_spell_name => 1}
    }
  end

  # Helper functions
  defp player_guid?(guid) when is_binary(guid), do: String.starts_with?(guid, "Player-")
  defp player_guid?(_), do: false

  defp npc_guid?(guid) when is_binary(guid), do: String.starts_with?(guid, "Creature-")
  defp npc_guid?(_), do: false

  @doc """
  Formats interrupt summary for display.
  """
  def format_interrupt_summary(%{
        by_player: by_player,
        by_spell: by_spell,
        missed_casts: missed_casts
      }) do
    player_section = format_player_interrupts(by_player)
    spell_section = format_spell_stats(by_spell)
    missed_section = format_missed_casts(missed_casts)

    [player_section, spell_section, missed_section]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp format_player_interrupts(by_player) do
    if map_size(by_player) == 0 do
      "   No interrupts recorded"
    else
      players =
        by_player
        |> Map.values()
        |> Enum.sort_by(& &1.total_interrupts, :desc)

      header = "   Successful Interrupts by Player:"

      player_lines =
        players
        |> Enum.map(fn stats ->
          spells_str =
            stats.by_spell
            |> Enum.sort_by(fn {_name, count} -> count end, :desc)
            |> Enum.map(fn {name, count} -> "#{name} (#{count})" end)
            |> Enum.join(", ")

          "      #{stats.player_name}: #{stats.total_interrupts} - #{spells_str}"
        end)
        |> Enum.join("\n")

      header <> "\n" <> player_lines
    end
  end

  defp format_spell_stats(by_spell) do
    # Only show spells that had some interrupts (we care about interruptible abilities)
    interruptible =
      by_spell
      |> Map.values()
      |> Enum.filter(&(&1.interrupted_count > 0 or &1.completed_count > 0))
      |> Enum.sort_by(& &1.completed_count, :desc)

    if Enum.empty?(interruptible) do
      ""
    else
      header = "\n   Enemy Casts (Interruptible):"

      spell_lines =
        interruptible
        |> Enum.map(fn stats ->
          rate =
            if stats.total_casts > 0 do
              Float.round(stats.interrupted_count / stats.total_casts * 100, 0) |> trunc()
            else
              0
            end

          status =
            cond do
              stats.completed_count == 0 -> "[ALL KICKED]"
              stats.interrupted_count == 0 -> "[NONE KICKED]"
              true -> "[#{stats.completed_count} MISSED]"
            end

          "      #{stats.spell_name}: #{stats.interrupted_count}/#{stats.total_casts} interrupted (#{rate}%) #{status}"
        end)
        |> Enum.join("\n")

      header <> "\n" <> spell_lines
    end
  end

  defp format_missed_casts(missed_casts) do
    if Enum.empty?(missed_casts) do
      ""
    else
      header = "\n   Missed Interrupts (casts that went off):"

      # Group by spell for cleaner output
      by_spell =
        missed_casts
        |> Enum.group_by(& &1.spell_name)
        |> Enum.sort_by(fn {_name, casts} -> length(casts) end, :desc)
        |> Enum.take(5)

      lines =
        by_spell
        |> Enum.map(fn {spell_name, casts} ->
          times =
            casts
            |> Enum.take(3)
            |> Enum.map(&format_time(&1.time_into_fight))
            |> Enum.join(", ")

          more = if length(casts) > 3, do: " +#{length(casts) - 3} more", else: ""
          "      #{spell_name}: #{length(casts)} casts went off (at #{times}#{more})"
        end)
        |> Enum.join("\n")

      header <> "\n" <> lines
    end
  end

  defp format_time(seconds) do
    minutes = trunc(seconds / 60)
    secs = trunc(rem(trunc(seconds), 60))
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end
end

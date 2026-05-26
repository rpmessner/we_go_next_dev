defmodule WeGoNext.Analyzers.DebuffAnalyzer do
  @moduledoc """
  Legacy reference-only analyzer for debuff applications.

  Retained for command-line diagnostics, migration reference, and parity checks.
  New medallion UI, gold facts, and silver/gold read models must not depend on
  this module or its in-memory output shape.

  Analyzes debuff applications in combat encounters.

  Tracks which debuffs are applied to players, how often, and for how long.
  Useful for identifying players who are repeatedly getting hit by mechanics
  that apply debuffs (standing in bad, not spreading, etc.).
  """

  alias WeGoNext.Encounter

  defmodule DebuffApplication do
    @moduledoc "Represents a single debuff application"
    defstruct [
      :timestamp,
      :time_into_fight,
      :player_name,
      :player_guid,
      :spell_name,
      :spell_id,
      :source_name,
      :source_guid,
      # nil until removed, then seconds
      :duration,
      # timestamp when removed, nil if still active
      :removed_at
    ]
  end

  defmodule PlayerStats do
    @moduledoc "Debuff statistics for a single player"
    defstruct [
      :player_name,
      :player_guid,
      total_debuffs: 0,
      # %{spell_name => %{count: N, total_duration: N, applications: []}}
      by_spell: %{}
    ]
  end

  defmodule SpellStats do
    @moduledoc "Statistics for a single debuff spell"
    defstruct [
      :spell_name,
      :spell_id,
      :source_guid,
      :source_name,
      total_applications: 0,
      players_affected: 0,
      # %{player_guid => count}
      by_player: %{}
    ]
  end

  @doc """
  Analyzes an encounter and returns debuff statistics.

  Returns a map with:
    - :applications - list of %DebuffApplication{} in chronological order
    - :by_player - map of player_guid => %PlayerStats{}
    - :by_spell - map of spell_name => %SpellStats{}
  """
  def analyze(%Encounter{} = encounter) do
    # Events are now loaded from DB in chronological order
    events = encounter.events

    # First pass: collect all debuff applications
    {applications, pending} =
      Enum.reduce(events, {[], %{}}, fn event, acc ->
        process_event(event, acc)
      end)

    # Finalize any debuffs that were never removed (still active at end of fight)
    final_applications =
      pending
      |> Map.values()
      |> List.flatten()
      |> Enum.concat(applications)
      |> Enum.sort_by(& &1.time_into_fight)

    # Build player and spell stats
    player_stats = build_player_stats(final_applications)
    spell_stats = build_spell_stats(final_applications)

    %{
      applications: final_applications,
      by_player: player_stats,
      by_spell: spell_stats
    }
  end

  # Process SPELL_AURA_APPLIED - debuff applied (now using normalized event fields)
  defp process_event(%{type: "SPELL_AURA_APPLIED"} = event, {applications, pending}) do
    dest_guid = event.target_guid

    # Only track debuffs on players
    # Note: aura_type is stored in extra map for aura events
    aura_type = get_in(event, [:extra, "aura_type"])

    if player_guid?(dest_guid) and aura_type == "DEBUFF" do
      app = %DebuffApplication{
        timestamp: event.timestamp,
        time_into_fight: event.time_into_fight,
        player_name: event.target_name,
        player_guid: dest_guid,
        spell_name: event.spell_name,
        spell_id: event.spell_id,
        source_name: event.source_name,
        source_guid: event.source_guid,
        duration: nil,
        removed_at: nil
      }

      key = {dest_guid, event.spell_id}
      updated_pending = Map.update(pending, key, [app], &[app | &1])
      {applications, updated_pending}
    else
      {applications, pending}
    end
  end

  # Process SPELL_AURA_REMOVED - debuff removed (calculate duration)
  defp process_event(%{type: "SPELL_AURA_REMOVED"} = event, {applications, pending}) do
    player_guid = event.target_guid
    spell_id = event.spell_id
    aura_type = get_in(event, [:extra, "aura_type"])

    if player_guid?(player_guid) and aura_type == "DEBUFF" do
      key = {player_guid, spell_id}

      case Map.get(pending, key) do
        [app | rest] ->
          # Calculate duration
          duration = event.time_into_fight - app.time_into_fight
          completed_app = %{app | duration: duration, removed_at: event.timestamp}

          # Update pending map
          updated_pending =
            if Enum.empty?(rest) do
              Map.delete(pending, key)
            else
              Map.put(pending, key, rest)
            end

          {[completed_app | applications], updated_pending}

        _ ->
          # No matching application found (debuff was applied before encounter started)
          {applications, pending}
      end
    else
      {applications, pending}
    end
  end

  # Process SPELL_AURA_APPLIED_DOSE - stacking debuff
  defp process_event(%{type: "SPELL_AURA_APPLIED_DOSE"} = event, {applications, pending}) do
    dest_guid = event.target_guid
    aura_type = get_in(event, [:extra, "aura_type"])

    if player_guid?(dest_guid) and aura_type == "DEBUFF" do
      app = %DebuffApplication{
        timestamp: event.timestamp,
        time_into_fight: event.time_into_fight,
        player_name: event.target_name,
        player_guid: dest_guid,
        spell_name: event.spell_name,
        spell_id: event.spell_id,
        source_name: event.source_name,
        source_guid: event.source_guid,
        duration: nil,
        removed_at: nil
      }

      # Add directly to applications (stacks are instant, no duration tracking needed)
      {[app | applications], pending}
    else
      {applications, pending}
    end
  end

  defp process_event(_event, acc), do: acc

  # Build player statistics from applications
  defp build_player_stats(applications) do
    applications
    |> Enum.reduce(%{}, fn app, acc ->
      Map.update(acc, app.player_guid, new_player_stats(app), fn stats ->
        update_player_stats(stats, app)
      end)
    end)
  end

  defp new_player_stats(%DebuffApplication{} = app) do
    %PlayerStats{
      player_name: app.player_name,
      player_guid: app.player_guid,
      total_debuffs: 1,
      by_spell: %{
        app.spell_name => %{
          count: 1,
          total_duration: app.duration || 0,
          spell_id: app.spell_id
        }
      }
    }
  end

  defp update_player_stats(stats, app) do
    %{
      stats
      | total_debuffs: stats.total_debuffs + 1,
        by_spell:
          Map.update(
            stats.by_spell,
            app.spell_name,
            %{count: 1, total_duration: app.duration || 0, spell_id: app.spell_id},
            fn existing ->
              %{
                existing
                | count: existing.count + 1,
                  total_duration: existing.total_duration + (app.duration || 0)
              }
            end
          )
    }
  end

  # Build spell statistics from applications
  defp build_spell_stats(applications) do
    applications
    |> Enum.reduce(%{}, fn app, acc ->
      Map.update(acc, app.spell_name, new_spell_stats(app), fn stats ->
        update_spell_stats(stats, app)
      end)
    end)
  end

  defp new_spell_stats(%DebuffApplication{} = app) do
    %SpellStats{
      spell_name: app.spell_name,
      spell_id: app.spell_id,
      source_guid: app.source_guid,
      source_name: app.source_name,
      total_applications: 1,
      players_affected: 1,
      by_player: %{app.player_guid => 1}
    }
  end

  defp update_spell_stats(stats, app) do
    updated_by_player = Map.update(stats.by_player, app.player_guid, 1, &(&1 + 1))

    %{
      stats
      | total_applications: stats.total_applications + 1,
        players_affected: map_size(updated_by_player),
        by_player: updated_by_player
    }
  end

  # Helper functions
  defp player_guid?(guid) when is_binary(guid), do: String.starts_with?(guid, "Player-")
  defp player_guid?(_), do: false

  @doc """
  Formats debuff summary for display.
  """
  def format_debuff_summary(%{by_player: by_player, by_spell: by_spell}, opts \\ []) do
    top_spells = Keyword.get(opts, :top_spells, 10)
    top_players = Keyword.get(opts, :top_players, 5)

    spell_section = format_top_spells(by_spell, top_spells)
    player_section = format_player_debuffs(by_player, top_players)

    [spell_section, player_section]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp format_top_spells(by_spell, n) do
    if map_size(by_spell) == 0 do
      "   No debuffs recorded"
    else
      spells =
        by_spell
        |> Map.values()
        |> Enum.sort_by(& &1.total_applications, :desc)
        |> Enum.take(n)

      header = "   Top Debuffs (raid-wide):"

      lines =
        spells
        |> Enum.with_index(1)
        |> Enum.map(fn {stats, idx} ->
          "      #{idx}. #{stats.spell_name}: #{stats.total_applications} applications (#{stats.players_affected} players)"
        end)
        |> Enum.join("\n")

      header <> "\n" <> lines
    end
  end

  defp format_player_debuffs(by_player, n) do
    if map_size(by_player) == 0 do
      ""
    else
      # Show players with most debuffs (potential problem players)
      players =
        by_player
        |> Map.values()
        |> Enum.sort_by(& &1.total_debuffs, :desc)
        |> Enum.take(n)

      header = "\n   Players with Most Debuffs:"

      lines =
        players
        |> Enum.map(fn stats ->
          top_debuffs =
            stats.by_spell
            |> Enum.sort_by(fn {_name, %{count: count}} -> count end, :desc)
            |> Enum.take(3)
            |> Enum.map(fn {name, %{count: count}} -> "#{name} (#{count})" end)
            |> Enum.join(", ")

          "      #{stats.player_name}: #{stats.total_debuffs} total - #{top_debuffs}"
        end)
        |> Enum.join("\n")

      header <> "\n" <> lines
    end
  end

  @doc """
  Returns players who received a specific debuff more than the threshold.

  Useful for identifying players who are repeatedly failing a mechanic.
  """
  def players_with_debuff(%{by_spell: by_spell}, spell_name, min_count \\ 2) do
    case Map.get(by_spell, spell_name) do
      nil ->
        []

      %SpellStats{by_player: by_player} ->
        by_player
        |> Enum.filter(fn {_guid, count} -> count >= min_count end)
        |> Enum.sort_by(fn {_guid, count} -> count end, :desc)
    end
  end

  @doc """
  Returns debuffs that were applied to many players (raid-wide mechanics).
  """
  def raid_wide_debuffs(%{by_spell: by_spell}, min_players \\ 5) do
    by_spell
    |> Map.values()
    |> Enum.filter(&(&1.players_affected >= min_players))
    |> Enum.sort_by(& &1.total_applications, :desc)
  end

  @doc """
  Checks if a source GUID is from a player (vs NPC/boss).
  """
  def player_source?(source_guid) when is_binary(source_guid) do
    String.starts_with?(source_guid, "Player-")
  end

  def player_source?(_), do: false

  @doc """
  Checks if a source GUID is from an NPC (boss, add, creature).
  """
  def npc_source?(source_guid) when is_binary(source_guid) do
    String.starts_with?(source_guid, "Creature-")
  end

  def npc_source?(_), do: false
end

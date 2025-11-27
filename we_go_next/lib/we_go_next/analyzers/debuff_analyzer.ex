defmodule WeGoNext.Analyzers.DebuffAnalyzer do
  @moduledoc """
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
      :duration,           # nil until removed, then seconds
      :removed_at          # timestamp when removed, nil if still active
    ]
  end

  defmodule PlayerStats do
    @moduledoc "Debuff statistics for a single player"
    defstruct [
      :player_name,
      :player_guid,
      total_debuffs: 0,
      by_spell: %{}        # %{spell_name => %{count: N, total_duration: N, applications: []}}
    ]
  end

  defmodule SpellStats do
    @moduledoc "Statistics for a single debuff spell"
    defstruct [
      :spell_name,
      :spell_id,
      total_applications: 0,
      players_affected: 0,
      by_player: %{}       # %{player_guid => count}
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
    events = Enum.reverse(encounter.events)

    # First pass: collect all debuff applications
    {applications, pending} =
      Enum.reduce(events, {[], %{}}, fn event, acc ->
        process_event(event, encounter, acc)
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

  # Process SPELL_AURA_APPLIED - debuff applied
  defp process_event(%{type: "SPELL_AURA_APPLIED"} = event, encounter, {applications, pending}) do
    case parse_aura_applied(event, encounter) do
      {:ok, :debuff, app} ->
        # Track this application, keyed by player+spell for matching with removal
        key = {app.player_guid, app.spell_id}
        updated_pending = Map.update(pending, key, [app], &[app | &1])
        {applications, updated_pending}

      _ ->
        {applications, pending}
    end
  end

  # Process SPELL_AURA_REMOVED - debuff removed (calculate duration)
  defp process_event(%{type: "SPELL_AURA_REMOVED"} = event, encounter, {applications, pending}) do
    case parse_aura_removed(event, encounter) do
      {:ok, player_guid, spell_id, removed_at, time_into_fight} ->
        key = {player_guid, spell_id}

        case Map.get(pending, key) do
          [app | rest] ->
            # Calculate duration
            duration = time_into_fight - app.time_into_fight
            completed_app = %{app | duration: duration, removed_at: removed_at}

            # Update pending map
            updated_pending = if Enum.empty?(rest) do
              Map.delete(pending, key)
            else
              Map.put(pending, key, rest)
            end

            {[completed_app | applications], updated_pending}

          _ ->
            # No matching application found (debuff was applied before encounter started)
            {applications, pending}
        end

      _ ->
        {applications, pending}
    end
  end

  # Process SPELL_AURA_APPLIED_DOSE - stacking debuff
  defp process_event(%{type: "SPELL_AURA_APPLIED_DOSE"} = event, encounter, {applications, pending}) do
    # Treat dose applications as separate debuff hits (shows they're taking repeated damage)
    case parse_aura_applied(event, encounter) do
      {:ok, :debuff, app} ->
        # Add directly to applications (stacks are instant, no duration tracking needed)
        {[app | applications], pending}

      _ ->
        {applications, pending}
    end
  end

  defp process_event(_event, _encounter, acc), do: acc

  # Parse SPELL_AURA_APPLIED event
  defp parse_aura_applied(%{timestamp: timestamp, data: data}, encounter) do
    source_guid = Enum.at(data, 1)
    source_name = Enum.at(data, 2)
    dest_guid = Enum.at(data, 5)
    dest_name = Enum.at(data, 6)
    spell_id = Enum.at(data, 9) |> parse_int()
    spell_name = Enum.at(data, 10)
    aura_type = Enum.at(data, 12)  # "BUFF" or "DEBUFF"

    # Only track debuffs on players
    if is_player_guid?(dest_guid) and aura_type == "DEBUFF" do
      app = %DebuffApplication{
        timestamp: timestamp,
        time_into_fight: time_into_fight(encounter.start_time, timestamp),
        player_name: dest_name,
        player_guid: dest_guid,
        spell_name: spell_name,
        spell_id: spell_id,
        source_name: source_name,
        source_guid: source_guid,
        duration: nil,
        removed_at: nil
      }
      {:ok, :debuff, app}
    else
      :skip
    end
  end

  # Parse SPELL_AURA_REMOVED event
  defp parse_aura_removed(%{timestamp: timestamp, data: data}, encounter) do
    dest_guid = Enum.at(data, 5)
    spell_id = Enum.at(data, 9) |> parse_int()
    aura_type = Enum.at(data, 12)

    if is_player_guid?(dest_guid) and aura_type == "DEBUFF" do
      {:ok, dest_guid, spell_id, timestamp, time_into_fight(encounter.start_time, timestamp)}
    else
      :skip
    end
  end

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
    %{stats |
      total_debuffs: stats.total_debuffs + 1,
      by_spell: Map.update(stats.by_spell, app.spell_name,
        %{count: 1, total_duration: app.duration || 0, spell_id: app.spell_id},
        fn existing ->
          %{existing |
            count: existing.count + 1,
            total_duration: existing.total_duration + (app.duration || 0)
          }
        end)
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
      total_applications: 1,
      players_affected: 1,
      by_player: %{app.player_guid => 1}
    }
  end

  defp update_spell_stats(stats, app) do
    updated_by_player = Map.update(stats.by_player, app.player_guid, 1, &(&1 + 1))
    %{stats |
      total_applications: stats.total_applications + 1,
      players_affected: map_size(updated_by_player),
      by_player: updated_by_player
    }
  end

  # Helper functions
  defp is_player_guid?(guid) when is_binary(guid), do: String.starts_with?(guid, "Player-")
  defp is_player_guid?(_), do: false

  defp time_into_fight(start_time, event_time) do
    NaiveDateTime.diff(event_time, start_time, :millisecond) / 1000
  end

  defp parse_int(nil), do: 0
  defp parse_int(value) when is_integer(value), do: value
  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> num
      :error -> 0
    end
  end

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
end

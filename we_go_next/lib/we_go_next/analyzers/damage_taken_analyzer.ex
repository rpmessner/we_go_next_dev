defmodule WeGoNext.Analyzers.DamageTakenAnalyzer do
  @moduledoc """
  Legacy reference-only analyzer for damage taken.

  Retained for command-line diagnostics, migration reference, and parity checks.
  New medallion UI, gold facts, and silver/gold read models must not depend on
  this module or its in-memory output shape.

  Analyzes damage taken by players during combat encounters.

  Tracks total damage, damage by ability, and damage by source.
  Separates tanks from DPS/healers since tanks are EXPECTED to take boss damage.

  Tank detection uses a heuristic: players receiving significant boss melee damage
  are identified as tanks (top 2 players by NPC melee damage received).
  """

  alias WeGoNext.Encounter

  defmodule PlayerDamage do
    @moduledoc "Damage taken statistics for a single player"
    defstruct [
      :player_name,
      :player_guid,
      # :tank or :dps_healer
      :role,
      total: 0,
      # Used for tank detection
      melee_from_npcs: 0,
      # %{ability_name => %{total: N, hits: N, ability_id: id}}
      by_ability: %{},
      # %{source_name => total_damage}
      by_source: %{}
    ]
  end

  @doc """
  Analyzes an encounter and returns damage taken statistics for all players.

  Returns a map with:
    - :tanks - list of %PlayerDamage{} for tanks
    - :dps_healers - list of %PlayerDamage{} for DPS/healers
    - :all - combined list sorted by total damage

  Tank detection heuristic: top 2 players receiving NPC melee damage are tanks.
  """
  def analyze(%Encounter{} = encounter) do
    # Events are now loaded from DB in chronological order
    players =
      encounter.events
      |> Enum.reduce(%{}, &process_event/2)

    # Detect tanks based on melee damage from NPCs
    tank_guids = detect_tanks(players)

    # Assign roles and sort
    players_with_roles =
      players
      |> Map.values()
      |> Enum.map(fn player ->
        role = if MapSet.member?(tank_guids, player.player_guid), do: :tank, else: :dps_healer
        %{player | role: role}
      end)
      |> Enum.sort_by(& &1.total, :desc)

    {tanks, dps_healers} = Enum.split_with(players_with_roles, &(&1.role == :tank))

    %{
      tanks: Enum.sort_by(tanks, & &1.total, :desc),
      dps_healers: Enum.sort_by(dps_healers, & &1.total, :desc),
      all: players_with_roles
    }
  end

  @doc """
  Legacy function - returns flat list for backwards compatibility.
  """
  def analyze_flat(%Encounter{} = encounter) do
    analyze(encounter).all
  end

  # Detect tanks: top 2 players receiving NPC melee damage
  defp detect_tanks(players) do
    players
    |> Map.values()
    |> Enum.filter(&(&1.melee_from_npcs > 0))
    |> Enum.sort_by(& &1.melee_from_npcs, :desc)
    |> Enum.take(2)
    |> Enum.map(& &1.player_guid)
    |> MapSet.new()
  end

  # Process damage events - now using normalized event fields
  defp process_event(%{type: type} = event, players)
       when type in [
              "SPELL_DAMAGE",
              "SPELL_PERIODIC_DAMAGE",
              "SWING_DAMAGE",
              "RANGE_DAMAGE",
              "ENVIRONMENTAL_DAMAGE"
            ] do
    target_guid = event.target_guid
    target_name = event.target_name
    source_guid = event.source_guid
    source_name = event.source_name || "Unknown"
    ability_name = event.spell_name || "Melee"
    ability_id = event.spell_id
    amount = event.amount || 0

    if player_guid?(target_guid) do
      is_npc_melee = type == "SWING_DAMAGE" and npc_guid?(source_guid)

      update_player_damage(
        players,
        target_guid,
        target_name,
        source_name,
        ability_name,
        ability_id,
        amount,
        is_npc_melee
      )
    else
      players
    end
  end

  defp process_event(_event, players), do: players

  defp update_player_damage(
         players,
         guid,
         name,
         source,
         ability,
         ability_id,
         amount,
         is_npc_melee
       ) do
    Map.update(
      players,
      guid,
      new_player_damage(guid, name, source, ability, ability_id, amount, is_npc_melee),
      fn player ->
        %{
          player
          | total: player.total + amount,
            melee_from_npcs: player.melee_from_npcs + if(is_npc_melee, do: amount, else: 0),
            by_ability: update_ability_damage(player.by_ability, ability, ability_id, amount),
            by_source: Map.update(player.by_source, source, amount, &(&1 + amount))
        }
      end
    )
  end

  defp new_player_damage(guid, name, source, ability, ability_id, amount, is_npc_melee) do
    %PlayerDamage{
      player_guid: guid,
      player_name: name,
      # Set later after tank detection
      role: nil,
      total: amount,
      melee_from_npcs: if(is_npc_melee, do: amount, else: 0),
      by_ability: %{ability => %{total: amount, hits: 1, ability_id: ability_id}},
      by_source: %{source => amount}
    }
  end

  defp update_ability_damage(by_ability, ability, ability_id, amount) do
    Map.update(
      by_ability,
      ability,
      %{total: amount, hits: 1, ability_id: ability_id},
      fn existing ->
        %{existing | total: existing.total + amount, hits: existing.hits + 1}
      end
    )
  end

  defp player_guid?(guid) when is_binary(guid), do: String.starts_with?(guid, "Player-")
  defp player_guid?(_), do: false

  defp npc_guid?(guid) when is_binary(guid), do: String.starts_with?(guid, "Creature-")
  defp npc_guid?(_), do: false

  @doc """
  Formats damage taken for display, separating tanks and DPS/healers.
  """
  def format_damage_taken(data, opts \\ [])

  def format_damage_taken(%{tanks: tanks, dps_healers: dps_healers}, opts) do
    top_n = Keyword.get(opts, :top, 10)
    show_abilities = Keyword.get(opts, :show_abilities, 5)

    tank_section =
      if Enum.empty?(tanks) do
        ""
      else
        tank_str =
          tanks
          |> Enum.map(&format_player(&1, show_abilities))
          |> Enum.join("\n")

        "   TANKS (expected damage):\n#{tank_str}\n"
      end

    dps_section =
      if Enum.empty?(dps_healers) do
        ""
      else
        dps_str =
          dps_healers
          |> Enum.take(top_n)
          |> Enum.map(&format_player(&1, show_abilities))
          |> Enum.join("\n")

        "   DPS/HEALERS (avoidable?):\n#{dps_str}"
      end

    tank_section <> dps_section
  end

  # Backwards compatibility for flat list
  def format_damage_taken(players, opts) when is_list(players) do
    top_n = Keyword.get(opts, :top, 10)
    show_abilities = Keyword.get(opts, :show_abilities, 5)

    players
    |> Enum.take(top_n)
    |> Enum.map(&format_player(&1, show_abilities))
    |> Enum.join("\n")
  end

  defp format_player(%PlayerDamage{} = player, show_abilities) do
    abilities_str = format_top_abilities(player.by_ability, show_abilities)
    role_indicator = if player.role == :tank, do: " [TANK]", else: ""

    """
      #{player.player_name}#{role_indicator}: #{format_number(player.total)} total
    #{abilities_str}
    """
    |> String.trim_trailing()
  end

  defp format_top_abilities(by_ability, n) do
    by_ability
    |> Enum.sort_by(fn {_name, %{total: total}} -> total end, :desc)
    |> Enum.take(n)
    |> Enum.map(fn {name, %{total: total, hits: hits}} ->
      avg = div(total, max(hits, 1))
      "         #{name}: #{format_number(total)} (#{hits} hits, #{format_number(avg)} avg)"
    end)
    |> Enum.join("\n")
  end

  defp format_number(num) when is_integer(num) and num >= 1_000_000 do
    "#{Float.round(num / 1_000_000, 1)}M"
  end

  defp format_number(num) when is_integer(num) and num >= 1000 do
    "#{Float.round(num / 1000, 0) |> trunc()}k"
  end

  defp format_number(num), do: to_string(num)

  @doc """
  Returns the top N abilities by total damage across all players.

  Useful for identifying raid-wide problematic mechanics.
  Returns list of {name, %{total: N, hits: N, ability_id: id, players: N}}
  """
  def top_abilities(%{all: players}, n), do: top_abilities(players, n)

  # Handle cached/deserialized format: map of player_name => %{abilities: %{...}}
  def top_abilities(players, n) when is_map(players) do
    players
    |> Enum.flat_map(fn {player_name, %{abilities: abilities}} ->
      Enum.map(abilities, fn {name, stats} -> {name, stats, player_name} end)
    end)
    |> Enum.reduce(%{}, fn {name, stats, player_name}, acc ->
      total = Map.get(stats, :total, 0)
      hits = Map.get(stats, :hits, 0)
      id = Map.get(stats, :ability_id)

      Map.update(
        acc,
        name,
        %{total: total, hits: hits, ability_id: id, players: MapSet.new([player_name])},
        fn existing ->
          %{
            existing
            | total: existing.total + total,
              hits: existing.hits + hits,
              players: MapSet.put(existing.players, player_name)
          }
        end
      )
    end)
    |> Enum.map(fn {name, stats} -> {name, %{stats | players: MapSet.size(stats.players)}} end)
    |> Enum.sort_by(fn {_name, %{total: total}} -> total end, :desc)
    |> Enum.take(n)
  end

  # Handle analyzer output format: list of PlayerDamage structs.
  def top_abilities(players, n) when is_list(players) do
    players
    |> Enum.flat_map(fn %PlayerDamage{player_name: player_name, by_ability: by_ability} ->
      Enum.map(by_ability, fn {name, stats} -> {name, stats, player_name} end)
    end)
    |> Enum.reduce(%{}, fn {name, %{total: total, hits: hits, ability_id: id}, player_name},
                           acc ->
      Map.update(
        acc,
        name,
        %{total: total, hits: hits, ability_id: id, players: MapSet.new([player_name])},
        fn existing ->
          %{
            existing
            | total: existing.total + total,
              hits: existing.hits + hits,
              players: MapSet.put(existing.players, player_name)
          }
        end
      )
    end)
    |> Enum.map(fn {name, stats} -> {name, %{stats | players: MapSet.size(stats.players)}} end)
    |> Enum.sort_by(fn {_name, %{total: total}} -> total end, :desc)
    |> Enum.take(n)
  end

  @doc """
  Returns top abilities for non-tanks only (avoidable damage).
  Handles current analyzer output (:dps_healers) and historical map-shaped data
  used by older command-line diagnostics (:non_tanks).
  """
  def top_avoidable_abilities(stats, n \\ 10)

  def top_avoidable_abilities(%{dps_healers: dps_healers}, n) do
    top_abilities(dps_healers, n)
  end

  def top_avoidable_abilities(%{non_tanks: non_tanks}, n) do
    top_abilities(non_tanks, n)
  end

  @doc """
  Formats the top abilities for display.
  """
  def format_top_abilities_summary(abilities) do
    abilities
    |> Enum.with_index(1)
    |> Enum.map(fn {{name, %{total: total, hits: hits}}, idx} ->
      avg = div(total, max(hits, 1))
      "  #{idx}. #{name}: #{format_number(total)} (#{hits} hits, #{format_number(avg)} avg)"
    end)
    |> Enum.join("\n")
  end
end

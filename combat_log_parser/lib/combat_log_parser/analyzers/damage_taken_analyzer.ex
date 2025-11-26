defmodule CombatLogParser.Analyzers.DamageTakenAnalyzer do
  @moduledoc """
  Analyzes damage taken by players during combat encounters.

  Tracks total damage, damage by ability, and damage by source.
  Separates tanks from DPS/healers since tanks are EXPECTED to take boss damage.

  Tank detection uses a heuristic: players receiving significant boss melee damage
  are identified as tanks (top 2 players by NPC melee damage received).
  """

  alias CombatLogParser.Encounter

  defmodule PlayerDamage do
    @moduledoc "Damage taken statistics for a single player"
    defstruct [
      :player_name,
      :player_guid,
      :role,              # :tank or :dps_healer
      total: 0,
      melee_from_npcs: 0, # Used for tank detection
      by_ability: %{},    # %{ability_name => %{total: N, hits: N, ability_id: id}}
      by_source: %{}      # %{source_name => total_damage}
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
    # First pass: collect all damage data
    players =
      encounter.events
      |> Enum.reverse()
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

  # Process damage events
  defp process_event(%{type: type} = event, players)
       when type in ["SPELL_DAMAGE", "SPELL_PERIODIC_DAMAGE", "SWING_DAMAGE", "RANGE_DAMAGE", "ENVIRONMENTAL_DAMAGE"] do
    case parse_damage_event(event) do
      {:ok, target_guid, target_name, source_guid, source_name, ability_name, ability_id, amount} ->
        if is_player_guid?(target_guid) do
          is_npc_melee = type == "SWING_DAMAGE" and is_npc_guid?(source_guid)
          update_player_damage(players, target_guid, target_name, source_name, ability_name, ability_id, amount, is_npc_melee)
        else
          players
        end

      _ ->
        players
    end
  end

  defp process_event(_event, players), do: players

  defp update_player_damage(players, guid, name, source, ability, ability_id, amount, is_npc_melee) do
    Map.update(players, guid, new_player_damage(guid, name, source, ability, ability_id, amount, is_npc_melee), fn player ->
      %{player |
        total: player.total + amount,
        melee_from_npcs: player.melee_from_npcs + if(is_npc_melee, do: amount, else: 0),
        by_ability: update_ability_damage(player.by_ability, ability, ability_id, amount),
        by_source: Map.update(player.by_source, source, amount, &(&1 + amount))
      }
    end)
  end

  defp new_player_damage(guid, name, source, ability, ability_id, amount, is_npc_melee) do
    %PlayerDamage{
      player_guid: guid,
      player_name: name,
      role: nil,  # Set later after tank detection
      total: amount,
      melee_from_npcs: if(is_npc_melee, do: amount, else: 0),
      by_ability: %{ability => %{total: amount, hits: 1, ability_id: ability_id}},
      by_source: %{source => amount}
    }
  end

  defp update_ability_damage(by_ability, ability, ability_id, amount) do
    Map.update(by_ability, ability, %{total: amount, hits: 1, ability_id: ability_id}, fn existing ->
      %{existing | total: existing.total + amount, hits: existing.hits + 1}
    end)
  end

  # Parse different damage event types
  defp parse_damage_event(%{type: "SWING_DAMAGE", data: data}) do
    source_guid = Enum.at(data, 1)
    source_name = Enum.at(data, 2)
    target_guid = Enum.at(data, 5)
    target_name = Enum.at(data, 6)
    amount = Enum.at(data, 28) |> parse_int()

    {:ok, target_guid, target_name, source_guid, source_name, "Melee", nil, amount}
  end

  defp parse_damage_event(%{type: type, data: data})
       when type in ["SPELL_DAMAGE", "SPELL_PERIODIC_DAMAGE", "RANGE_DAMAGE"] do
    source_guid = Enum.at(data, 1)
    source_name = Enum.at(data, 2)
    target_guid = Enum.at(data, 5)
    target_name = Enum.at(data, 6)
    ability_id = Enum.at(data, 9) |> parse_int()
    ability_name = Enum.at(data, 10, "Unknown")
    amount = Enum.at(data, 31) |> parse_int()

    {:ok, target_guid, target_name, source_guid, source_name, ability_name, ability_id, amount}
  end

  defp parse_damage_event(%{type: "ENVIRONMENTAL_DAMAGE", data: data}) do
    target_guid = Enum.at(data, 5)
    target_name = Enum.at(data, 6)
    env_type = Enum.at(data, 9, "Environment")
    amount = Enum.at(data, 29) |> parse_int()

    {:ok, target_guid, target_name, nil, "Environment", "Environmental: #{env_type}", nil, amount}
  end

  defp parse_damage_event(_), do: :error

  defp is_player_guid?(guid) when is_binary(guid), do: String.starts_with?(guid, "Player-")
  defp is_player_guid?(_), do: false

  defp is_npc_guid?(guid) when is_binary(guid), do: String.starts_with?(guid, "Creature-")
  defp is_npc_guid?(_), do: false

  defp parse_int(nil), do: 0
  defp parse_int(value) when is_integer(value), do: value
  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> num
      :error -> 0
    end
  end

  @doc """
  Formats damage taken for display, separating tanks and DPS/healers.
  """
  def format_damage_taken(%{tanks: tanks, dps_healers: dps_healers}, opts \\ []) do
    top_n = Keyword.get(opts, :top, 10)
    show_abilities = Keyword.get(opts, :show_abilities, 5)

    tank_section = if Enum.empty?(tanks) do
      ""
    else
      tank_str = tanks
        |> Enum.map(&format_player(&1, show_abilities))
        |> Enum.join("\n")
      "   TANKS (expected damage):\n#{tank_str}\n"
    end

    dps_section = if Enum.empty?(dps_healers) do
      ""
    else
      dps_str = dps_healers
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
  """
  def top_abilities(%{all: players}, n), do: top_abilities(players, n)

  def top_abilities(players, n \\ 10) when is_list(players) do
    players
    |> Enum.flat_map(fn %PlayerDamage{by_ability: by_ability} ->
      Enum.map(by_ability, fn {name, stats} -> {name, stats} end)
    end)
    |> Enum.reduce(%{}, fn {name, %{total: total, hits: hits, ability_id: id}}, acc ->
      Map.update(acc, name, %{total: total, hits: hits, ability_id: id}, fn existing ->
        %{existing | total: existing.total + total, hits: existing.hits + hits}
      end)
    end)
    |> Enum.sort_by(fn {_name, %{total: total}} -> total end, :desc)
    |> Enum.take(n)
  end

  @doc """
  Returns top abilities for non-tanks only (avoidable damage).
  """
  def top_avoidable_abilities(%{dps_healers: dps_healers}, n \\ 10) do
    top_abilities(dps_healers, n)
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

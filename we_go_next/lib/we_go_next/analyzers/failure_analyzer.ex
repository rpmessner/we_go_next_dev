defmodule WeGoNext.Analyzers.FailureAnalyzer do
  @moduledoc """
  Analyzes encounters against tracked mechanic criteria to identify player failures.

  Takes the output from other analyzers (damage, interrupts) and applies
  criteria rules to flag specific failures for coaching.
  """

  alias WeGoNext.{Encounter, Criteria}
  alias WeGoNext.Analyzers.{DamageTakenAnalyzer, InterruptAnalyzer}

  defmodule Failure do
    @moduledoc "Represents a single mechanic failure by a player"
    defstruct [
      :player_name,
      :player_guid,
      :spell_id,
      :spell_name,
      :mechanic_type,
      :hit_count,
      :total_damage,
      :reason,
      :criteria_id
    ]
  end

  @doc """
  Analyzes an encounter and returns all mechanic failures based on tracked criteria.

  Returns:
    %{
      failures: [%Failure{}, ...],
      by_player: %{player_name => [%Failure{}, ...]},
      by_mechanic: %{spell_name => [%Failure{}, ...]},
      summary: %{total_failures: N, players_with_failures: N, ...}
    }
  """
  def analyze(%Encounter{} = encounter) do
    # Load criteria for this boss
    criteria_by_spell = Criteria.criteria_by_spell_id(encounter.id)

    if map_size(criteria_by_spell) == 0 do
      # No criteria defined, return empty results
      %{
        failures: [],
        by_player: %{},
        by_mechanic: %{},
        summary: %{total_failures: 0, players_with_failures: 0, mechanics_failed: 0}
      }
    else
      # Analyze based on criteria types
      avoidable_failures = analyze_avoidable_damage(encounter, criteria_by_spell)
      interrupt_failures = analyze_missed_interrupts(encounter, criteria_by_spell)

      all_failures = avoidable_failures ++ interrupt_failures

      by_player =
        all_failures
        |> Enum.group_by(& &1.player_name)

      by_mechanic =
        all_failures
        |> Enum.group_by(& &1.spell_name)

      %{
        failures: all_failures,
        by_player: by_player,
        by_mechanic: by_mechanic,
        summary: %{
          total_failures: length(all_failures),
          players_with_failures: map_size(by_player),
          mechanics_failed: map_size(by_mechanic)
        }
      }
    end
  end

  @doc """
  Analyzes avoidable damage failures.

  For each "avoidable" criteria, checks if any non-tank player took damage
  from that ability beyond the threshold.
  """
  def analyze_avoidable_damage(%Encounter{} = encounter, criteria_by_spell) do
    damage_stats = DamageTakenAnalyzer.analyze(encounter)

    # Get avoidable criteria
    avoidable_criteria =
      criteria_by_spell
      |> Map.values()
      |> List.flatten()
      |> Enum.filter(&(&1.mechanic_type == "avoidable"))

    if Enum.empty?(avoidable_criteria) do
      []
    else
      # Check each non-tank player's damage
      damage_stats.dps_healers
      |> Enum.flat_map(fn player ->
        check_player_avoidable(player, avoidable_criteria)
      end)
    end
  end

  defp check_player_avoidable(player, criteria_list) do
    criteria_list
    |> Enum.flat_map(fn criteria ->
      # Check if player took damage from this spell
      case find_ability_damage(player.by_ability, criteria.spell_id) do
        nil ->
          []

        {_ability_name, %{total: total, hits: hits}} ->
          max_hits = Map.get(criteria.threshold, "max_hits", 0)

          if hits > max_hits do
            [
              %Failure{
                player_name: player.player_name,
                player_guid: player.player_guid,
                spell_id: criteria.spell_id,
                spell_name: criteria.spell_name,
                mechanic_type: "avoidable",
                hit_count: hits,
                total_damage: total,
                reason: "took #{hits} hit(s) (max: #{max_hits})",
                criteria_id: criteria.id
              }
            ]
          else
            []
          end
      end
    end)
  end

  defp find_ability_damage(by_ability, target_spell_id) do
    Enum.find(by_ability, fn {_name, %{ability_id: ability_id}} ->
      ability_id == target_spell_id
    end)
  end

  @doc """
  Analyzes missed interrupt failures.

  For each "interrupt" criteria, checks if any casts of that spell completed
  without being interrupted.
  """
  def analyze_missed_interrupts(%Encounter{} = encounter, criteria_by_spell) do
    interrupt_stats = InterruptAnalyzer.analyze(encounter)

    # Get interrupt criteria
    interrupt_criteria =
      criteria_by_spell
      |> Map.values()
      |> List.flatten()
      |> Enum.filter(&(&1.mechanic_type == "interrupt"))

    if Enum.empty?(interrupt_criteria) do
      []
    else
      # Check missed casts against criteria
      interrupt_stats.missed_casts
      |> Enum.flat_map(fn cast ->
        matching_criteria =
          Enum.find(interrupt_criteria, fn c ->
            c.spell_id == cast.spell_id
          end)

        if matching_criteria do
          # This is a tracked interrupt that was missed - but we don't know who was assigned
          # For now, mark it as a "raid failure" without a specific player
          [
            %Failure{
              player_name: "Raid",
              player_guid: nil,
              spell_id: matching_criteria.spell_id,
              spell_name: matching_criteria.spell_name,
              mechanic_type: "interrupt",
              hit_count: 1,
              total_damage: 0,
              reason: "#{cast.caster_name} finished casting",
              criteria_id: matching_criteria.id
            }
          ]
        else
          []
        end
      end)
    end
  end

  @doc """
  Formats failures into a human-readable summary for the pull report.
  """
  def format_summary(%{failures: [], summary: _}) do
    "No mechanic failures detected."
  end

  def format_summary(%{failures: failures, by_player: by_player, by_mechanic: by_mechanic}) do
    lines = [
      "MECHANIC FAILURES (#{length(failures)} total)",
      ""
    ]

    # By mechanic
    mechanic_lines =
      by_mechanic
      |> Enum.sort_by(fn {_, f} -> -length(f) end)
      |> Enum.map(fn {spell_name, fails} ->
        player_counts =
          fails
          |> Enum.group_by(& &1.player_name)
          |> Enum.map(fn {name, pf} -> "#{name}: #{length(pf)}" end)
          |> Enum.join(", ")

        "  #{spell_name}: #{length(fails)} failures (#{player_counts})"
      end)

    # By player
    player_lines =
      by_player
      |> Enum.sort_by(fn {_, f} -> -length(f) end)
      |> Enum.take(5)
      |> Enum.map(fn {name, fails} ->
        "  #{name}: #{length(fails)} failure(s)"
      end)

    (lines ++ ["By Mechanic:"] ++ mechanic_lines ++ ["", "By Player:"] ++ player_lines)
    |> Enum.join("\n")
  end
end

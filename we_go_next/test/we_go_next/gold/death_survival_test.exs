defmodule WeGoNext.Gold.DeathSurvivalTest do
  use ExUnit.Case, async: true

  alias WeGoNext.Gold.DeathSurvival

  @died_at 300_000
  @window 10_000

  test "duration effect active at death reads as died-through" do
    analysis =
      DeathSurvival.analyze(
        death(),
        warlock_info(),
        [
          usage(
            spell_id: 104_773,
            spell_name: "Unending Resolve",
            used_at_ms_into_fight: @died_at - 3_000
          )
        ],
        [buff_window(spell_id: 104_773, started_at_ms_into_fight: @died_at - 3_000)]
      )

    assert %{state: :died_through, basis: :observed, used_at_ms_into_fight: used_at} =
             kit_entry(analysis, :unending_resolve)

    assert used_at == @died_at - 3_000
  end

  test "an aura that ended before death is used-in-window, not died-through" do
    analysis =
      DeathSurvival.analyze(
        death(),
        warlock_info(),
        [
          usage(
            spell_id: 104_773,
            spell_name: "Unending Resolve",
            used_at_ms_into_fight: @died_at - 8_000
          )
        ],
        [
          buff_window(
            spell_id: 104_773,
            started_at_ms_into_fight: @died_at - 8_000,
            ended_at_ms_into_fight: @died_at - 1_000
          )
        ]
      )

    assert %{state: :used_in_window, basis: :observed} = kit_entry(analysis, :unending_resolve)
  end

  test "instant consumable use in the window is used-in-window" do
    analysis =
      DeathSurvival.analyze(
        death(),
        warlock_info(),
        [
          usage(used_at_ms_into_fight: @died_at - 4_000, heal_amount: 118_000, overheal_amount: 0)
        ],
        []
      )

    assert %{state: :used_in_window, used_at_ms_into_fight: used_at} =
             kit_entry(analysis, :healthstone)

    assert used_at == @died_at - 4_000
  end

  test "a use before the window puts the action on cooldown by inference" do
    analysis =
      DeathSurvival.analyze(
        death(),
        warlock_info(),
        [
          usage(
            spell_id: 104_773,
            spell_name: "Unending Resolve",
            used_at_ms_into_fight: @died_at - 70_000
          )
        ],
        []
      )

    assert %{
             state: :on_cooldown,
             basis: :inferred,
             used_at_ms_into_fight: nil,
             last_used_at_ms_into_fight: last_used
           } = kit_entry(analysis, :unending_resolve)

    assert last_used == @died_at - 70_000
  end

  test "an old use beyond the base cooldown leaves the action likely available" do
    analysis =
      DeathSurvival.analyze(
        death(),
        warlock_info(),
        [
          usage(
            spell_id: 104_773,
            spell_name: "Unending Resolve",
            used_at_ms_into_fight: @died_at - 200_000
          )
        ],
        []
      )

    assert %{state: :available_unused, basis: :inferred} = kit_entry(analysis, :unending_resolve)
  end

  test "the shared potion cooldown spends every potion in the group" do
    analysis =
      DeathSurvival.analyze(
        death(),
        warlock_info(),
        [
          usage(
            spell_id: 1_234_768,
            spell_name: "Silvermoon Health Potion",
            kind: "health_potion",
            used_at_ms_into_fight: @died_at - 100_000
          )
        ],
        []
      )

    assert %{state: :on_cooldown, basis: :inferred} =
             kit_entry(analysis, :silvermoon_health_potion)

    assert %{state: :on_cooldown, basis: :inferred} = kit_entry(analysis, :potent_healing_potion)
  end

  test "the per-combat allowance spends the sibling potion beyond the cooldown window" do
    analysis =
      DeathSurvival.analyze(
        death(died_at_ms_into_fight: 500_000),
        warlock_info(),
        [
          usage(
            spell_id: 1_234_768,
            spell_name: "Silvermoon Health Potion",
            kind: "health_potion",
            used_at_ms_into_fight: 100_000
          )
        ],
        []
      )

    assert %{state: :on_cooldown, basis: :inferred} = kit_entry(analysis, :potent_healing_potion)
  end

  test "the per-combat allowance keeps an expended healthstone on cooldown" do
    analysis =
      DeathSurvival.analyze(
        death(died_at_ms_into_fight: 500_000),
        warlock_info(),
        [usage(used_at_ms_into_fight: 100_000)],
        []
      )

    assert %{state: :on_cooldown, basis: :inferred} = kit_entry(analysis, :healthstone)
  end

  test "talented-but-unused defensives read as available-but-unused inference" do
    analysis = DeathSurvival.analyze(death(), warlock_info(), [], [])

    assert %{state: :available_unused, basis: :inferred, availability: :talented} =
             kit_entry(analysis, :dark_pact)

    assert %{state: :available_unused, availability: :baseline} =
             kit_entry(analysis, :unending_resolve)
  end

  test "untalented and unknown loadouts stay explicit, never fake-unavailable" do
    untalented = DeathSurvival.analyze(death(), %{spec_id: 266, talents: []}, [], [])
    assert %{state: :not_talented, basis: :observed} = kit_entry(untalented, :dark_pact)

    unknown = DeathSurvival.analyze(death(), %{spec_id: 266, talents: nil}, [], [])
    assert %{state: :unknown} = kit_entry(unknown, :dark_pact)
    assert %{state: :available_unused} = kit_entry(unknown, :healthstone)
  end

  test "an observed use outranks unknown talent data" do
    analysis =
      DeathSurvival.analyze(
        death(),
        %{spec_id: 266, talents: nil},
        [
          usage(
            spell_id: 108_416,
            spell_name: "Dark Pact",
            used_at_ms_into_fight: @died_at - 30_000
          )
        ],
        []
      )

    assert %{state: :on_cooldown, basis: :inferred} = kit_entry(analysis, :dark_pact)
  end

  test "externals received in the window are display-only and window-bounded" do
    external_in =
      usage(
        spell_id: 33_206,
        spell_name: "Pain Suppression",
        kind: "defensive",
        category: "external",
        caster_guid: "Player-Priest",
        used_at_ms_into_fight: @died_at - 2_000
      )

    external_out = %{external_in | used_at_ms_into_fight: @died_at - 50_000}

    analysis = DeathSurvival.analyze(death(), warlock_info(), [external_in, external_out], [])

    assert [
             %{
               spell_id: 33_206,
               spell_name: "Pain Suppression",
               caster_guid: "Player-Priest",
               used_at_ms_into_fight: used_at
             }
           ] = analysis.externals_received

    assert used_at == @died_at - 2_000
    refute Enum.any?(analysis.kit, &(&1.key == :pain_suppression))
  end

  test "missing player info resolves only consumables" do
    analysis = DeathSurvival.analyze(death(), nil, [], [])

    assert Enum.all?(analysis.kit, &(&1.category == :consumable))
    assert Enum.any?(analysis.kit, &(&1.key == :healthstone))
  end

  defp death(attrs \\ []) do
    Map.merge(
      %{target_guid: "Player-Victim", died_at_ms_into_fight: @died_at, window_ms: @window},
      Map.new(attrs)
    )
  end

  defp warlock_info do
    %{spec_id: 266, talents: [%{"node_id" => 71_936, "entry_id" => 91_444, "rank" => 1}]}
  end

  defp usage(attrs) do
    Map.merge(
      %{
        caster_guid: "Player-Victim",
        target_guid: "Player-Victim",
        spell_id: 6262,
        spell_name: "Healthstone",
        kind: "healthstone",
        category: "consumable",
        used_at_ms_into_fight: 0,
        heal_amount: nil,
        overheal_amount: nil
      },
      Map.new(attrs)
    )
  end

  defp buff_window(attrs) do
    Map.merge(
      %{
        target_guid: "Player-Victim",
        source_guid: "Player-Victim",
        spell_id: 104_773,
        started_at_ms_into_fight: 0,
        ended_at_ms_into_fight: nil
      },
      Map.new(attrs)
    )
  end

  defp kit_entry(analysis, key), do: Enum.find(analysis.kit, &(&1.key == key))
end

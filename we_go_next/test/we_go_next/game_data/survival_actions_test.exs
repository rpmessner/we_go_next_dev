defmodule WeGoNext.GameData.SurvivalActionsTest do
  use ExUnit.Case, async: true

  alias WeGoNext.GameData.SurvivalActions

  test "resolves observed cast and aura IDs to one defensive action" do
    assert %{key: :fortifying_brew, cast_spell_ids: [115_203], aura_spell_ids: [120_954]} =
             SurvivalActions.get_by_cast_id(115_203)

    assert SurvivalActions.get_by_aura_id(120_954) ==
             SurvivalActions.get_by_cast_id(115_203)

    refute SurvivalActions.get_by_aura_id(243_435)
  end

  test "provides a personal defensive for every retail specialization" do
    retail_spec_ids = [
      62,
      63,
      64,
      65,
      66,
      70,
      71,
      72,
      73,
      102,
      103,
      104,
      105,
      250,
      251,
      252,
      253,
      254,
      255,
      256,
      257,
      258,
      259,
      260,
      261,
      262,
      263,
      264,
      265,
      266,
      267,
      268,
      269,
      270,
      577,
      581,
      1467,
      1468,
      1473
    ]

    missing_spec_ids =
      Enum.reject(retail_spec_ids, fn spec_id ->
        Enum.any?(SurvivalActions.for_spec(spec_id), &(&1.category in [:personal, :immunity]))
      end)

    assert missing_spec_ids == []
  end

  test "models current healing consumables and their per-combat cooldown groups" do
    assert MapSet.member?(SurvivalActions.cast_ids(), 1_262_857)
    assert MapSet.member?(SurvivalActions.cast_ids(), 6262)

    potent_potion = SurvivalActions.get_by_cast_id(1_262_857)
    healthstone = SurvivalActions.get_by_cast_id(6262)

    assert %{kind: :health_potion, base_cooldown_ms: 300_000, max_uses_per_combat: 1} =
             potent_potion

    assert potent_potion.shared_cooldown_group == :combat_potion

    assert %{
             kind: :healthstone,
             base_cooldown_ms: 60_000,
             shared_cooldown_group: :healthstone,
             max_uses_per_combat: 1
           } = healthstone
  end

  test "keeps retail verification and talent association explicit in plain data" do
    assert Enum.all?(SurvivalActions.all(), fn action ->
             action.verified_retail == %{project_id: 1, build_major: 12} and
               is_integer(action.base_cooldown_ms) and action.base_cooldown_ms > 0 and
               is_integer(action.charges) and action.charges > 0
           end)

    assert %{availability: :talent, talent_spell_id: 108_416} =
             SurvivalActions.get_by_cast_id(108_416)

    assert %{availability: :baseline, talent_spell_id: nil} =
             SurvivalActions.get_by_cast_id(104_773)

    refute SurvivalActions.get_by_aura_id(55_342)
  end

  test "marks the actions identified as talents by current retail tooltips" do
    talent_keys =
      SurvivalActions.all()
      |> Enum.filter(&(&1.availability == :talent))
      |> Enum.map(& &1.key)
      |> Enum.sort()

    assert talent_keys ==
             Enum.sort([
               :anti_magic_zone,
               :ardent_defender,
               :astral_shift,
               :blessing_of_protection,
               :blessing_of_sacrifice,
               :blessing_of_spellwarding,
               :cloak_of_shadows,
               :dark_pact,
               :darkness,
               :dancing_rune_weapon,
               :death_pact,
               :desperate_prayer,
               :die_by_the_sword,
               :earth_elemental,
               :enraged_regeneration,
               :evasion,
               :fortifying_brew,
               :frenzied_regeneration,
               :greater_invisibility,
               :guardian_of_ancient_kings,
               :guardian_spirit,
               :ice_barrier,
               :ice_block,
               :icebound_fortitude,
               :ignore_pain,
               :impending_victory,
               :ironbark,
               :obsidian_scales,
               :pain_suppression,
               :prismatic_barrier,
               :rallying_cry,
               :shield_wall,
               :spell_reflection,
               :survival_instincts,
               :survival_of_the_fittest,
               :time_dilation,
               :vampiric_blood,
               :zephyr,
               :alter_time
             ])
  end

  test "stores base charges without talent-modified extra charges" do
    for key <- [
          :demon_spikes,
          :survival_instincts,
          :frenzied_regeneration,
          :obsidian_scales
        ] do
      assert %{charges: 1} = Enum.find(SurvivalActions.all(), &(&1.key == key))
    end
  end

  test "every talent-gated action carries verified trait entry ids" do
    for action <- SurvivalActions.all() do
      case action.availability do
        :talent ->
          assert is_list(action.talent_entry_ids) and action.talent_entry_ids != [],
                 "#{action.key} is talent-gated but has no talent_entry_ids"

          assert Enum.all?(action.talent_entry_ids, &is_integer/1)

        :baseline ->
          assert action.talent_entry_ids == nil
      end
    end
  end

  describe "availability_for/2" do
    # Entry ids below come from real 2026-07-19 COMBATANT_INFO payloads.
    test "resolves baseline, talented, and not-talented states for a warlock" do
      talents = [%{"node_id" => 71_936, "entry_id" => 91_444, "rank" => 1}]

      kit = SurvivalActions.availability_for(266, talents)

      assert %{state: :baseline, category: :personal} = kit_entry(kit, :unending_resolve)
      assert %{state: :talented} = kit_entry(kit, :dark_pact)
      assert %{state: :baseline, kind: :healthstone} = kit_entry(kit, :healthstone)
      assert %{state: :baseline, kind: :health_potion} = kit_entry(kit, :silvermoon_health_potion)

      assert %{state: :not_talented} =
               kit_entry(SurvivalActions.availability_for(266, []), :dark_pact)
    end

    test "any granting entry of a choice node counts as talented" do
      for entry_id <- [103_180, 103_193] do
        kit =
          SurvivalActions.availability_for(104, [
            %{"node_id" => 82_129, "entry_id" => entry_id, "rank" => 1}
          ])

        assert %{state: :talented} = kit_entry(kit, :survival_instincts)
      end
    end

    test "missing talent data degrades to unknown, never to not-talented" do
      kit = SurvivalActions.availability_for(266, nil)

      assert %{state: :unknown} = kit_entry(kit, :dark_pact)
      assert %{state: :baseline} = kit_entry(kit, :unending_resolve)
      refute Enum.any?(kit, &(&1.state == :not_talented))
    end

    test "unknown spec resolves only the universal consumables" do
      kit = SurvivalActions.availability_for(nil, nil)

      assert Enum.all?(kit, &(&1.category == :consumable and &1.state == :baseline))
      assert Enum.any?(kit, &(&1.key == :healthstone))
    end
  end

  defp kit_entry(kit, key), do: Enum.find(kit, &(&1.key == key))
end

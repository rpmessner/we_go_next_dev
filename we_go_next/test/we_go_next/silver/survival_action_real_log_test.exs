defmodule WeGoNext.Silver.SurvivalActionRealLogTest do
  use ExUnit.Case, async: true

  alias WeGoNext.CombatLogParser
  alias WeGoNext.GameData.SurvivalActions
  alias WeGoNext.Silver.Projector

  @moduledoc """
  Real-log acceptance coverage for the silver survival-action usage grain.

  The fixture is a verbatim slice of a local 12.0.7 raid log
  (WoWCombatLog-071926_110643.txt, Lightblinded Vanguard mythic pull at
  11:38:36). Spell IDs asserted here — Healthstone 6262 and Silvermoon Health
  Potion 1234768 — were resolved from these observed events, not from memory.
  The slice preserves a real quirk: Manaken's healthstone SPELL_HEAL is
  stamped 1ms before its own SPELL_CAST_SUCCESS line.
  """

  @fixture_path Path.expand("../../fixtures/survival_actions_real_pull.txt", __DIR__)
  @encounter_start_timestamp "7/19/2026 11:38:36.049-4"
  @encounter_dim_id 1

  test "projects defensives, an external, and joined rock/pot heals from real log lines" do
    projection = projected_fixture()

    assert [barkskin, guardian_spirit, potion, healthstone, second_healthstone] =
             projection.survival_action

    assert %{
             encounter_dim_id: @encounter_dim_id,
             caster_guid: "Player-1171-0A8A2DA9",
             target_guid: "Player-1171-0A8A2DA9",
             spell_id: 22_812,
             spell_name: "Barkskin",
             kind: "defensive",
             category: "personal",
             used_at_ms_into_fight: 11_569,
             heal_amount: nil,
             overheal_amount: nil
           } = barkskin

    # External cast on another player: the caster and receiver differ.
    assert %{
             caster_guid: "Player-76-0BE7FABE",
             target_guid: "Player-1171-0B076010",
             spell_id: 47_788,
             spell_name: "Guardian Spirit",
             kind: "defensive",
             category: "external",
             used_at_ms_into_fight: 19_885,
             heal_amount: nil
           } = guardian_spirit

    assert %{
             caster_guid: "Player-1175-0FF05A1A",
             target_guid: "Player-1175-0FF05A1A",
             spell_id: 1_234_768,
             spell_name: "Silvermoon Health Potion",
             kind: "health_potion",
             category: "consumable",
             used_at_ms_into_fight: 79_369,
             heal_amount: 358_468,
             overheal_amount: 183_395
           } = potion

    # The joined SPELL_HEAL for this row is stamped 1ms before the cast.
    assert %{
             caster_guid: "Player-1171-09045C8D",
             target_guid: "Player-1171-09045C8D",
             spell_id: 6262,
             spell_name: "Healthstone",
             kind: "healthstone",
             category: "consumable",
             used_at_ms_into_fight: 93_035,
             heal_amount: 118_155,
             overheal_amount: 0
           } = healthstone

    assert %{
             caster_guid: "Player-1171-0AC764AB",
             spell_id: 6262,
             kind: "healthstone",
             used_at_ms_into_fight: 122_901,
             heal_amount: 301_472,
             overheal_amount: 218_799
           } = second_healthstone
  end

  test "captures real talent payloads and resolves survival kit availability" do
    projection = projected_fixture()
    players = Map.new(projection.player_info, &{&1.player_guid, &1})

    # Demonology warlock with 76 talent triples in the real payload.
    pixen = players["Player-1175-0FF05A1A"]
    assert pixen.spec_id == 266
    assert length(pixen.talents) == 76
    assert %{"node_id" => 71_918, "entry_id" => 91_425, "rank" => 1} = hd(pixen.talents)

    pixen_kit = SurvivalActions.availability_for(pixen.spec_id, pixen.talents)
    assert %{state: :talented} = kit_entry(pixen_kit, :dark_pact)
    assert %{state: :baseline} = kit_entry(pixen_kit, :unending_resolve)
    assert %{state: :baseline} = kit_entry(pixen_kit, :healthstone)

    # Guardian druid whose Survival Instincts comes from choice entry 103193.
    grdengnome = players["Player-1171-0A8A2DA9"]
    assert grdengnome.spec_id == 104

    guardian_kit = SurvivalActions.availability_for(grdengnome.spec_id, grdengnome.talents)
    assert %{state: :talented} = kit_entry(guardian_kit, :survival_instincts)
    assert %{state: :talented} = kit_entry(guardian_kit, :frenzied_regeneration)
    assert %{state: :baseline} = kit_entry(guardian_kit, :barkskin)

    # No COMBATANT_INFO in the slice for this caster: unknown, not untalented.
    sparfox = players["Player-76-0BE7FABE"]
    assert sparfox.talents == nil
    assert sparfox.spec_id == nil
  end

  defp projected_fixture do
    assert {:ok, events} =
             CombatLogParser.parse_events(
               @fixture_path,
               0,
               File.stat!(@fixture_path).size,
               @encounter_start_timestamp
             )

    Projector.project(@encounter_dim_id, events)
  end

  defp kit_entry(kit, key), do: Enum.find(kit, &(&1.key == key))
end

Code.require_file("../../../../scripts/wipe_cause_reference.exs", __DIR__)

defmodule WeGoNext.Gold.FactWipeCauseTest do
  use WeGoNext.DataCase, async: false
  alias WeGoNext.Gold.{DimEncounter, FactWipeCause, RebuildEncounter}
  alias WeGoNext.Repo
  alias WeGoNext.Silver.{Death, DeathDerivation, PlayerInfo}

  test "approved cutoff, rank, ties, player-only, kills and resets" do
    encounter = %{success: false, fight_time_ms: 100_000}

    deaths =
      for {guid, ms} <- [
            {"Player-B", 1000},
            {"Player-A", 1000},
            {"Player-C", 2000},
            {"Player-D", 3000},
            {"Player-E", 70_000},
            {"Player-F", 71_000},
            {"Pet-X", 1}
          ],
          do: %{target_guid: guid, died_at_ms_into_fight: ms}

    assert Enum.map(FactWipeCause.deciding_deaths(encounter, deaths), & &1.target_guid) ==
             ["Player-A", "Player-B", "Player-C"]

    assert FactWipeCause.deciding_deaths(%{encounter | success: true}, deaths) == []
    assert FactWipeCause.deciding_deaths(%{encounter | success: nil}, deaths) == []
    assert FactWipeCause.deciding_deaths(%{encounter | fight_time_ms: 9999}, deaths) == []
    assert FactWipeCause.deciding_deaths(encounter, Enum.take(deaths, -3)) == []
  end

  test "reference set: every wiped Sept 6 pull agrees with revision 2" do
    pulls = WipeCauseReference.output().pulls

    expected = %{
      435 => [],
      436 => [],
      437 => [],
      438 => [99_507],
      439 => [],
      440 => [155_271, 171_398, 196_359],
      441 => [],
      442 => [163_278, 163_279, 163_280],
      443 => [490, 8629, 8631],
      444 => [],
      445 => [156_118, 156_543, 157_034],
      446 => [69_626, 221_971, 223_772],
      447 => [71_138, 291_772, 306_042],
      448 => [1406, 154_957, 166_190],
      449 => [176_767, 223_952, 306_865],
      450 => [123_265, 155_507, 163_854],
      451 => [209_663, 215_214, 215_236],
      452 => []
    }

    assert Map.new(
             pulls,
             &{&1.id, Enum.map(&1.deciding_deaths, fn d -> d.died_at_ms_into_fight end)}
           ) == expected

    assert length(pulls) == 18
  end

  test "AI agreement: Q1/Q4 operator overrides and must-not-repeat Feign Death" do
    pull = Enum.find(WipeCauseReference.output().pulls, &(&1.id == 440))
    [first | _] = pull.deciding_deaths
    assert first.player_name == "Kahnu"
    assert first.died_at_ms_into_fight == 155_271
    assert first.killing_blow_spell_id == 1_285_999

    references = Path.expand("../../../../docs/ai-analysis/reference-set", __DIR__)

    accepted =
      Jason.decode!(File.read!(Path.join(references, "evidence/q04.json")))["first_deaths"]
      |> hd()

    assert {first.player_name, first.died_at_ms_into_fight, first.killing_blow_spell_id} ==
             {accepted["name"], accepted["ms"], accepted["spell"]}

    for question <- ["q01", "q04"] do
      answer =
        File.read!(Path.join(references, "baselines/2026-10-29-opus55/#{question}.answer.md"))

      assert answer =~ first.player_name
      assert answer =~ "Mutilate"
      assert answer =~ "2:35"
    end

    # Feed the real raw death slice through silver before the production selector.
    path = Path.expand("../../fixtures/feign_death_real_pull.txt", __DIR__)

    assert {:ok, events} =
             WeGoNext.CombatLogParser.parse_events(
               path,
               0,
               File.stat!(path).size,
               "9/6/2026 11:33:20.939-4"
             )

    silver = WeGoNext.Silver.Projector.project(440, events).death

    assert [%{target_guid: guid, died_at_ms_into_fight: 155_271} | _] =
             FactWipeCause.deciding_deaths(pull, silver)

    assert guid == first.target_guid

    refute Enum.any?(
             pull.deciding_deaths,
             &(&1.player_name == "Mädz" and &1.died_at_ms_into_fight < 155_271)
           )
  end

  test "stamped, idempotent rebuild preserves blow and catalog intent without inventing avoidability" do
    dim = encounter()
    insert_death(dim.id, "Player-A", 155_271, 1_285_999, "Mutilate")
    insert_death(dim.id, "Player-B", 171_398, 1_287_083, "Tempest")
    insert_death(dim.id, "Player-C", 196_359, 387_846, "Fel Armor")
    insert_death(dim.id, "Player-D", 400_000, 1_285_999, "Mutilate")
    assert {:ok, %{inserted: 3, deleted: 0}} = FactWipeCause.rebuild_for_encounter(dim.id)
    assert {:ok, %{inserted: 3, deleted: 3}} = FactWipeCause.rebuild_for_encounter(dim.id)
    [first, second, third] = FactWipeCause.rows([dim.id])
    assert first.rank == 1
    assert first.mechanic_name == "Mutilate"
    assert first.mechanic_type == "unknown"
    assert first.avoidable == nil
    assert first.player_name == "Player-A"
    assert first.killing_blow_source_name == "Sszorak"
    assert first.killing_blow_source_guid == "Creature-boss"
    assert first.killing_blow_spell_name == "Mutilate"
    assert second.avoidable == true
    assert third.mechanic_name == nil
    assert third.avoidable == nil
    assert first.derivation_version == FactWipeCause.current_version()

    assert Repo.get!(DimEncounter, dim.id).wipe_cause_derivation_version ==
             FactWipeCause.current_version()

    # Rebuild boundary includes the fact even without an active failure ruleset.
    Repo.delete_all(FactWipeCause)

    assert {:ok, %{fact_wipe_cause: %{inserted: 3}}} =
             RebuildEncounter.rebuild(dim.id,
               generate_document: false,
               enqueue_mirror_upload: false
             )

    Repo.update!(Ecto.Changeset.change(dim, success: true))
    assert {:ok, %{inserted: 0, deleted: 3}} = FactWipeCause.rebuild_for_encounter(dim.id)
    assert FactWipeCause.rows([dim.id]) == []
  end

  defp encounter do
    Repo.insert!(%DimEncounter{
      name: "Sszorak",
      wow_encounter_id: "3420",
      success: false,
      fight_time_ms: 411_678,
      silver_death_derivation_version: DeathDerivation.current_version()
    })
  end

  defp insert_death(id, guid, ms, spell, name) do
    Repo.insert!(%PlayerInfo{encounter_dim_id: id, player_guid: guid, player_name: guid})

    Repo.insert!(%Death{
      encounter_dim_id: id,
      target_guid: guid,
      died_at_ms_into_fight: ms,
      killing_blow_spell_id: spell,
      killing_blow_source_guid: "Creature-boss",
      damage_recap: [%{"spell_id" => spell, "spell_name" => name, "source_name" => "Sszorak"}]
    })
  end
end

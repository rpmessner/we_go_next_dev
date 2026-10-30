defmodule WeGoNext.Gold.BelorenDivesRealLogTest do
  use WeGoNext.DataCase, async: false

  import Ecto.Query

  alias WeGoNext.{CombatLogParser, Repo, Rules, Silver}
  alias WeGoNext.GameData.Raids.MarchOnQuelDanas
  alias WeGoNext.Gold.{DimEncounter, FactFailure}

  @fixtures Path.expand("../../fixtures", __DIR__)
  @dives [1_241_291, 1_241_292, 1_241_339, 1_241_340]

  # Verbatim filtered slices: encounter boundaries, roster, all Dive and Patch
  # events. Source offsets and independently counted cast/target evidence are in
  # docs/research/beloren-dives.md. No synthetic combat events.
  for {id, timestamp, targets_per_cast, hits, old_rows} <- [
        {123, "5/23/2026 11:52:16.536-4", [], 0, 0},
        {124, "5/23/2026 12:00:31.022-4", [8, 8, 8, 7, 7, 7], 45, 30},
        {140, "5/30/2026 11:55:14.910-4", [], 0, 0},
        {141, "5/30/2026 11:55:57.065-4", [2], 1, 1},
        {142, "5/30/2026 11:59:18.231-4", [7, 7, 7, 8, 7], 33, 20},
        {143, "5/30/2026 12:05:44.249-4", [8, 9, 7, 6, 8, 6], 40, 26}
      ] do
    test "real Belo'ren pull #{id} does not blame Dive soakers after catalog replacement" do
      path = Path.join(@fixtures, "beloren_dives_#{unquote(id)}.txt")

      assert {:ok, events} =
               CombatLogParser.parse_events(path, 0, File.stat!(path).size, unquote(timestamp))

      dive_events = Enum.filter(events, &(&1[:spell_id] in @dives))

      # The parser does not retain the ST/AOE suffix yet; pin the raw evidence.
      path
      |> File.stream!()
      |> Enum.filter(&Regex.match?(~r/  SPELL_(?:DAMAGE|MISSED),.*,(1241291|1241340),"/, &1))
      |> Enum.each(&assert(String.ends_with?(String.trim(&1), ",AOE")))

      casts = Enum.filter(dive_events, &(&1.type == "SPELL_CAST_SUCCESS"))
      assert Enum.count(dive_events, &(&1.type == "SPELL_DAMAGE")) == unquote(hits)

      targets_per_cast =
        Enum.map(casts, fn cast ->
          dive_events
          |> Enum.filter(fn event ->
            event.type in ["SPELL_DAMAGE", "SPELL_MISSED"] and
              event.source_guid == cast.source_guid and event.spell_id == cast.spell_id and
              String.starts_with?(event.target_guid, "Player-") and
              abs(event.time_into_fight - cast.time_into_fight) < 0.1
          end)
          |> Enum.map(& &1.target_guid)
          |> Enum.uniq()
          |> length()
        end)

      assert targets_per_cast == unquote(targets_per_cast)

      encounter =
        %DimEncounter{}
        |> DimEncounter.changeset(%{
          source_encounter_key: "beloren-dives-#{unquote(id)}",
          wow_encounter_id: "3182",
          name: "Belo'ren, Child of Al'ar",
          difficulty_id: 15,
          difficulty_name: "Heroic",
          group_size: 20,
          instance_id: "2913"
        })
        |> Repo.insert!()

      assert {:ok, _} = Silver.project_and_persist(encounter, events: events)
      legacy = seed_legacy_dive_rules!()

      assert {:ok, %{inserted: unquote(old_rows)}} =
               FactFailure.rebuild_for_encounter(encounter.id)

      # Sync is additive: use a fresh version to retire previously authored
      # avoidable Dive criteria rather than retaining their old snapshots.
      assert {:ok, %{ruleset: current}} =
               Rules.sync_current_tier_rules(version: 2, activate: true, promote: true)

      assert {:ok, %{inserted: 0}} = FactFailure.rebuild_for_encounter(encounter.id)

      assert Repo.aggregate(
               from(f in FactFailure, where: f.ruleset_id == ^current.id),
               :count
             ) == 0

      # Replacement archives history; it does not delete the old ruleset's facts.
      assert Repo.aggregate(FactFailure, :count) == unquote(old_rows)

      for criterion <- Rules.list_mechanic_criteria(legacy) do
        assert {:ok, _} = Rules.update_mechanic_criterion(criterion, %{active: false})
      end

      assert {:ok, _} = Rules.promote_ruleset_to_gold(legacy)

      assert {:ok, %{deleted: unquote(old_rows), inserted: 0}} =
               FactFailure.rebuild_for_encounter(encounter.id, ruleset_id: legacy.id)

      assert Repo.aggregate(FactFailure, :count) == 0
    end
  end

  defp seed_legacy_dive_rules! do
    criteria =
      Enum.map(@dives, fn spell_id ->
        %{
          "spell_id" => spell_id,
          "spell_name" => "Dives",
          "mechanic_type" => "avoidable",
          "boss_encounter_id" => "3182",
          "threshold" => %{"max_hits" => 0}
        }
      end)

    assert {:ok, %{ruleset: ruleset}} =
             Rules.seed_rules(%{
               "ruleset" => %{"name" => "Midnight Current Tier Mechanics", "version" => 1},
               "criteria" => criteria
             })

    assert {:ok, _} = Rules.activate_ruleset(ruleset)
    assert {:ok, _} = Rules.promote_ruleset_to_gold(ruleset)
    ruleset
  end

  test "both Dive damage and target markers are observation-only soaks" do
    dives = Enum.filter(MarchOnQuelDanas.mechanics(), &(&1.spell_id in @dives))
    assert length(dives) == 4

    assert Enum.all?(dives, fn mechanic ->
             mechanic.mechanic_type == :soak and
               mechanic.default_fact_eligibility == :observation_only
           end)

    refute Enum.any?(MarchOnQuelDanas.rule_criteria(), &(&1["spell_id"] in @dives))
  end
end

defmodule WeGoNext.CatalogTest do
  use WeGoNext.DataCase, async: false

  alias WeGoNext.{Repo, Rules}
  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, FactFailure}
  alias WeGoNext.Silver.{DamageTaken, PlayerInfo}

  defmodule DatedCatalog do
    alias WeGoNext.GameData.Raids.{CatalogHelpers, Mechanic}
    def info, do: %{name: "Dated raid"}

    def mechanics do
      boundary = ~U[2026-09-06 00:00:00.000000Z]

      for {threshold, dates} <- [{0, %{valid_until: boundary}}, {2, %{valid_from: boundary}}] do
        Map.merge(
          %{
            raid_name: "Dated raid",
            raid_slug: "dated",
            boss_name: "Boss",
            boss_encounter_id: "boss",
            spell_id: 101,
            name: "Dated swirl",
            mechanic_type: :avoidable,
            evidence_family: :damage_taken,
            source_annotations: [:combat_log],
            rule: %{max_hits: threshold}
          },
          dates
        )
        |> Mechanic.new!()
      end
    end

    def rule_criteria, do: CatalogHelpers.rule_criteria(mechanics())
  end

  test "sync alone makes current-tier mechanics failure ready and repeat sync preserves identity" do
    assert {:ok, first} = Rules.sync_current_tier_rules()
    assert Repo.aggregate(DimMechanicCriterion, :count) == length(first.criteria)
    assert length(first.criteria) > 0
    assert {:ok, second} = Rules.sync_current_tier_rules()
    assert Enum.map(first.criteria, & &1.id) == Enum.map(second.criteria, & &1.id)
    assert second.completed == [:sync]
  end

  test "pull start selects the dated definition, inclusive from and exclusive until" do
    boundary = ~U[2026-09-06 00:00:00.000000Z]

    assert {:ok, %{criteria: [before_change, after_change]}} =
             Rules.sync_raid_mechanics(DatedCatalog)

    assert before_change.valid_until == boundary
    assert after_change.valid_from == boundary

    for {start, count} <- [
          {DateTime.add(boundary, -1), 1},
          {boundary, 0},
          {DateTime.add(boundary, 1), 0}
        ] do
      encounter =
        %DimEncounter{}
        |> DimEncounter.changeset(%{
          wow_encounter_id: "boss",
          name: "Boss",
          difficulty_id: 16,
          difficulty_name: "Mythic",
          group_size: 20,
          instance_id: "test",
          start_time: start
        })
        |> Repo.insert!()

      %PlayerInfo{}
      |> PlayerInfo.changeset(%{
        encounter_dim_id: encounter.id,
        player_guid: "Player-One",
        player_name: "One",
        class_id: 1,
        spec_id: 71,
        detected_role: "dps"
      })
      |> Repo.insert!()

      %DamageTaken{}
      |> DamageTaken.changeset(%{
        encounter_dim_id: encounter.id,
        target_guid: "Player-One",
        source_guid: "Creature-Boss",
        spell_id: 101,
        hit_count: 1,
        total_amount: 100,
        max_hit: 100,
        overkill_total: 0,
        source_is_npc: true
      })
      |> Repo.insert!()

      assert {:ok, %{inserted: ^count}} = FactFailure.rebuild_for_encounter(encounter.id)
    end

    assert WeGoNext.Gold.FailureSummary.readiness().stale_fact_count == 0
  end

  test "adjacent windows with identical thresholds still have separate stable keys" do
    attrs = %{
      spell_id: 1,
      spell_name: "Pool",
      mechanic_type: "avoidable",
      threshold: %{"max_hits" => 0}
    }

    boundary = ~U[2026-09-06 00:00:00.000000Z]

    old =
      DimMechanicCriterion.changeset(
        %DimMechanicCriterion{},
        Map.put(attrs, :valid_until, boundary)
      )
      |> Repo.insert!()

    new =
      DimMechanicCriterion.changeset(
        %DimMechanicCriterion{},
        Map.put(attrs, :valid_from, boundary)
      )
      |> Repo.insert!()

    refute old.criterion_key == new.criterion_key

    refute DimMechanicCriterion.changeset(
             %DimMechanicCriterion{},
             Map.merge(
               attrs,
               %{valid_from: boundary, valid_until: boundary}
             )
           ).valid?
  end
end

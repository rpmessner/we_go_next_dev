defmodule WeGoNext.RulesTest do
  use WeGoNext.DataCase, async: false
  import Ecto.Query

  alias WeGoNext.{Repo, Rules}
  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, FactFailure}

  defmodule FirstCatalog do
    def info, do: %{name: "Test Raid"}
    def mechanics, do: [%{boss_encounter_id: "9001"}]

    def rule_criteria do
      for id <- [9_000_001, 9_000_002] do
        %{
          "spell_id" => id,
          "spell_name" => "Pool #{id}",
          "mechanic_type" => "avoidable",
          "boss_encounter_id" => "9001",
          "threshold" => %{"max_hits" => 0}
        }
      end
    end
  end

  defmodule SecondCatalog do
    def info, do: FirstCatalog.info()
    def mechanics, do: FirstCatalog.mechanics()
    def rule_criteria, do: Enum.take(FirstCatalog.rule_criteria(), 1)
  end

  defmodule InvalidCatalog do
    def info, do: FirstCatalog.info()
    def mechanics, do: FirstCatalog.mechanics()

    def rule_criteria do
      FirstCatalog.rule_criteria() ++ [%{"spell_id" => 9_000_003}]
    end
  end

  test "sync retires removed mechanics without deleting their dimension or facts" do
    {:ok, %{criteria: [kept, removed]}} = Rules.sync_raid_mechanics(FirstCatalog)
    player = Repo.insert!(%WeGoNext.Gold.DimPlayer{player_guid: "Player-One", player_name: "One"})
    encounter = encounter!()

    Repo.insert!(%FactFailure{
      encounter_dim_id: encounter.id,
      player_dim_id: player.id,
      criterion_dim_id: removed.id,
      failure_count: 1,
      total_damage: 100
    })

    {:ok, %{criteria: [resynced]}} = Rules.sync_raid_mechanics(SecondCatalog)
    assert resynced.id == kept.id
    assert resynced.criterion_key == kept.criterion_key
    assert Repo.get!(DimMechanicCriterion, removed.id).active == false
    assert Repo.aggregate(FactFailure, :count) == 1
    assert Repo.get!(DimEncounter, encounter.id).failure_derivation_version == nil
    assert {:ok, %{deleted: 1, inserted: 0}} = FactFailure.rebuild_for_encounter(encounter.id)
  end

  test "single raid sync leaves unrelated bosses alone" do
    {:ok, _} = Rules.sync_current_tier_rules()
    before = Repo.aggregate(DimMechanicCriterion, :count)
    {:ok, _} = Rules.sync_raid_mechanics(FirstCatalog)
    {:ok, _} = Rules.sync_raid_mechanics(SecondCatalog)
    assert Repo.aggregate(from(c in DimMechanicCriterion, where: c.active), :count) == before + 1
  end

  test "an invalid definition rolls back all catalog writes and reports the failed stage" do
    assert {:error, %{stage: :sync, completed: [], reason: %Ecto.Changeset{}}} =
             Rules.sync_raid_mechanics(InvalidCatalog, rebuild: true)

    assert Repo.aggregate(DimMechanicCriterion, :count) == 0
  end

  test "a failed rebuild reports its committed sync and leaves the catalog available" do
    encounter = encounter!()

    assert {:error, %{stage: :rebuild, completed: [:sync], reason: %{encounter_id: id}}} =
             Rules.sync_raid_mechanics(FirstCatalog, rebuild: true)

    assert id == encounter.id
    assert Repo.aggregate(DimMechanicCriterion, :count) == 2
    assert Repo.get!(DimEncounter, id).failure_derivation_version == -1
  end

  test "an unchanged sync does not invalidate a rebuilt pull" do
    {:ok, _} = Rules.sync_raid_mechanics(FirstCatalog)
    encounter = encounter!()
    {:ok, _} = FactFailure.rebuild_for_encounter(encounter.id)
    {:ok, _} = Rules.sync_raid_mechanics(FirstCatalog)

    assert Repo.get!(DimEncounter, encounter.id).failure_derivation_version ==
             WeGoNext.Gold.FactFailure.Derivation.current_version()
  end

  test "threshold validation moved with the catalog" do
    base = %{spell_id: 101, spell_name: "Test", mechanic_type: "avoidable"}

    for threshold <- [
          %{},
          %{"max_hits" => -1},
          %{"max_hits" => "0"},
          %{"max_hits" => 0, "extra" => true}
        ] do
      refute DimMechanicCriterion.changeset(
               %DimMechanicCriterion{},
               Map.put(base, :threshold, threshold)
             ).valid?
    end

    assert DimMechanicCriterion.changeset(
             %DimMechanicCriterion{},
             Map.put(base, :threshold, %{"max_hits" => 0})
           ).valid?

    interrupt =
      DimMechanicCriterion.changeset(%DimMechanicCriterion{}, %{base | mechanic_type: "interrupt"})

    assert interrupt.valid?
    assert Ecto.Changeset.get_field(interrupt, :threshold) == %{"must_interrupt" => true}

    refute DimMechanicCriterion.changeset(
             %DimMechanicCriterion{},
             Map.merge(
               base,
               %{mechanic_type: "interrupt", threshold: %{"must_interrupt" => "true"}}
             )
           ).valid?

    for type <- ~w(soak spread stack tank_mechanic healer_mechanic) do
      assert DimMechanicCriterion.changeset(%DimMechanicCriterion{}, %{base | mechanic_type: type}).valid?

      refute DimMechanicCriterion.changeset(
               %DimMechanicCriterion{},
               Map.merge(
                 base,
                 %{mechanic_type: type, threshold: %{"max_hits" => 0}}
               )
             ).valid?
    end
  end

  test "targeted cone thresholds require valid evidence and role policies" do
    threshold = %{
      "target_marker_spell_id" => 1,
      "impact_spell_ids" => [2],
      "max_safe_hit_count" => 2,
      "target_role_policy" => "any",
      "allowed_collateral_roles" => ["tank"],
      "position_evidence" => "optional"
    }

    attrs = %{
      spell_id: 3,
      spell_name: "Cone",
      mechanic_type: "targeted_cone",
      threshold: threshold
    }

    assert DimMechanicCriterion.changeset(%DimMechanicCriterion{}, attrs).valid?

    for bad <- [
          Map.delete(threshold, "target_marker_spell_id"),
          Map.put(threshold, "target_role_policy", "invented"),
          Map.put(threshold, "impact_spell_ids", [])
        ] do
      refute DimMechanicCriterion.changeset(%DimMechanicCriterion{}, %{attrs | threshold: bad}).valid?
    end
  end

  defp encounter! do
    %DimEncounter{}
    |> DimEncounter.changeset(%{
      wow_encounter_id: "9001",
      name: "Test",
      difficulty_id: 16,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "test"
    })
    |> Repo.insert!()
  end
end

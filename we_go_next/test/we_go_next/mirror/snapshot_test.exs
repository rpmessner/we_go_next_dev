defmodule WeGoNext.Mirror.SnapshotTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer, FactFailure}
  alias WeGoNext.Mirror.Snapshot
  alias WeGoNext.Repo
  alias WeGoNext.Rules.Ruleset

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "encodes a gold-only encounter snapshot with stable keys and stripped source fields" do
    encounter = insert_encounter!()
    player = insert_player!()
    criterion = insert_criterion!()
    insert_failure!(encounter, player, criterion)

    assert {:ok, snapshot} = Snapshot.encode_encounter_snapshot(encounter.id)

    assert snapshot.schema_version == 1
    assert snapshot.encounter.source_encounter_key == encounter.source_encounter_key
    refute Map.has_key?(snapshot.encounter, :source_file_path)
    refute Map.has_key?(snapshot.encounter, :source_head_sha256)
    refute Map.has_key?(snapshot.encounter, :start_byte)
    refute Map.has_key?(snapshot.encounter, :end_byte)

    assert [%{player_guid: "Player-One"}] = snapshot.players
    assert [%{criterion_key: criterion_key}] = snapshot.criteria
    assert criterion_key == criterion.criterion_key

    assert [
             %{
               player_guid: "Player-One",
               criterion_key: ^criterion_key,
               failure_count: 2,
               total_damage: 1234
             }
           ] = snapshot.facts
  end

  test "returns an error for an encounter missing source encounter key" do
    encounter =
      %DimEncounter{}
      |> DimEncounter.changeset(%{wow_encounter_id: "missing-key", name: "Missing Key"})
      |> Repo.insert!()

    assert {:error, {:missing_source_encounter_key, encounter.id}} ==
             Snapshot.encode_encounter_snapshot(encounter.id)
  end

  defp insert_encounter! do
    %DimEncounter{}
    |> DimEncounter.changeset(%{
      source_file_path: "/local/WoWCombatLog.txt",
      source_head_sha256: String.duplicate("a", 64),
      wow_encounter_id: "3306",
      name: "Chimaerus",
      difficulty_id: 16,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "2939",
      start_time: ~U[2026-06-27 20:00:00Z],
      end_time: ~U[2026-06-27 20:05:00Z],
      success: false,
      fight_time_ms: 300_000,
      start_byte: 100,
      end_byte: 200
    })
    |> Repo.insert!()
  end

  defp insert_player! do
    %DimPlayer{}
    |> DimPlayer.changeset(%{
      player_guid: "Player-One",
      player_name: "One",
      class_id: 1,
      spec_id: 71
    })
    |> Repo.insert!()
  end

  defp insert_criterion! do
    ruleset =
      %Ruleset{}
      |> Ruleset.changeset(%{name: "Mirror Rules"})
      |> Repo.insert!()

    %DimMechanicCriterion{}
    |> DimMechanicCriterion.changeset(%{
      source_rule_id: System.unique_integer([:positive]),
      ruleset_id: ruleset.id,
      ruleset_version: ruleset.version,
      product: "wow",
      channel: "retail",
      build_key: "11.2.0",
      spell_id: 1_249_017,
      spell_name: "Fearsome Cry",
      mechanic_type: "interrupt",
      boss_encounter_id: "3306",
      boss_name: "Chimaerus",
      difficulty_id: 16,
      threshold: %{"must_interrupt" => true},
      active: true
    })
    |> Repo.insert!()
  end

  defp insert_failure!(encounter, player, criterion) do
    %FactFailure{}
    |> FactFailure.changeset(%{
      encounter_dim_id: encounter.id,
      player_dim_id: player.id,
      criterion_dim_id: criterion.id,
      ruleset_id: criterion.ruleset_id,
      ruleset_version: criterion.ruleset_version,
      product: criterion.product,
      channel: criterion.channel,
      build_key: criterion.build_key,
      derivation_version: 1,
      rebuilt_at: ~U[2026-06-27 20:06:00Z],
      failure_count: 2,
      total_damage: 1234
    })
    |> Repo.insert!()
  end
end

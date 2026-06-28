defmodule WeGoNext.Mirror.IngestTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer, FactFailure}
  alias WeGoNext.Mirror.Ingest
  alias WeGoNext.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "upsert_snapshot inserts mirrored dims and facts by stable keys" do
    snapshot = snapshot()

    assert {:ok, %{deleted: 0, inserted: 2}} = Ingest.upsert_snapshot(snapshot)

    assert %DimEncounter{name: "Mirror Boss", success: false} =
             Repo.get_by!(DimEncounter, source_encounter_key: "encounter-key-1")

    assert Repo.get_by!(DimPlayer, player_guid: "Player-One").player_name == "One"

    assert Repo.get_by!(DimMechanicCriterion, criterion_key: "criterion-swirl").source_rule_id ==
             nil

    assert Repo.aggregate(FactFailure, :count) == 2
  end

  test "reposting an unchanged snapshot does not duplicate rows" do
    snapshot = snapshot()

    assert {:ok, %{inserted: 2}} = Ingest.upsert_snapshot(snapshot)
    assert {:ok, %{inserted: 2}} = Ingest.upsert_snapshot(snapshot)

    assert Repo.aggregate(DimEncounter, :count) == 1
    assert Repo.aggregate(DimPlayer |> where_player_one(), :count) == 1
    assert Repo.aggregate(DimMechanicCriterion, :count) == 2
    assert Repo.aggregate(FactFailure, :count) == 2
  end

  test "reposting a snapshot replaces the encounter fact set" do
    original = snapshot()
    reduced = %{original | facts: [hd(original.facts)]}

    assert {:ok, %{inserted: 2}} = Ingest.upsert_snapshot(original)
    assert {:ok, %{deleted: 2, inserted: 1}} = Ingest.upsert_snapshot(reduced)

    assert Repo.aggregate(FactFailure, :count) == 1
    assert Repo.get_by!(FactFailure, total_damage: 500).failure_count == 2
  end

  test "rejects unsupported schema versions" do
    assert {:error, {:unsupported_schema_version, 999}} =
             %{snapshot() | schema_version: 999}
             |> Ingest.upsert_snapshot()
  end

  defp snapshot do
    %{
      schema_version: 1,
      encounter: %{
        source_encounter_key: "encounter-key-1",
        wow_encounter_id: "boss-one",
        name: "Mirror Boss",
        difficulty_id: 16,
        difficulty_name: "Mythic",
        group_size: 20,
        instance_id: "test-instance",
        start_time: ~U[2026-06-28 20:00:00Z],
        end_time: ~U[2026-06-28 20:05:00Z],
        success: false,
        fight_time_ms: 300_000
      },
      players: [
        %{player_guid: "Player-One", player_name: "One", class_id: 1, spec_id: 71}
      ],
      criteria: [
        criterion("criterion-swirl", 101, "Swirl", "avoidable", %{"max_hits" => 0}),
        criterion("criterion-kick", 202, "Shadow Volley", "interrupt", %{
          "must_interrupt" => true
        })
      ],
      facts: [
        fact("Player-One", "criterion-swirl", 2, 500),
        fact("Player-One", "criterion-kick", 1, 0)
      ]
    }
  end

  defp where_player_one(queryable) do
    import Ecto.Query

    where(queryable, [player], player.player_guid == "Player-One")
  end

  defp criterion(key, spell_id, spell_name, mechanic_type, threshold) do
    %{
      criterion_key: key,
      ruleset_id: 10,
      ruleset_version: 1,
      product: "wow",
      channel: "retail",
      build_key: "11.2.0",
      spell_id: spell_id,
      spell_name: spell_name,
      mechanic_type: mechanic_type,
      boss_encounter_id: "boss-one",
      boss_name: "Mirror Boss",
      difficulty_id: 16,
      threshold: threshold,
      active: true
    }
  end

  defp fact(player_guid, criterion_key, failure_count, total_damage) do
    %{
      player_guid: player_guid,
      criterion_key: criterion_key,
      ruleset_id: 10,
      ruleset_version: 1,
      product: "wow",
      channel: "retail",
      build_key: "11.2.0",
      derivation_version: 1,
      rebuilt_at: ~U[2026-06-28 20:06:00Z],
      failure_count: failure_count,
      total_damage: total_damage
    }
  end
end

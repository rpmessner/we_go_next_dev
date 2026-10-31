defmodule WeGoNext.Gold.RebuildsTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer, FactFailure, Rebuilds}
  alias WeGoNext.Repo
  alias WeGoNext.Silver.{DamageTaken, PlayerInfo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    original_documents_root = Application.fetch_env!(:we_go_next, :documents_root)

    documents_root =
      Path.join(System.tmp_dir!(), "wgn-documents-#{System.unique_integer([:positive])}")

    Application.put_env(:we_go_next, :documents_root, documents_root)

    Repo.delete_all(FactFailure)
    Repo.delete_all(DimMechanicCriterion)
    Repo.delete_all(DamageTaken)
    Repo.delete_all(PlayerInfo)
    Repo.delete_all(DimPlayer)
    Repo.delete_all(DimEncounter)

    on_exit(fn ->
      Application.put_env(:we_go_next, :documents_root, original_documents_root)
      File.rm_rf(documents_root)
    end)

    :ok
  end

  test "status returns imported pull and tracked failure counts with compatibility aliases" do
    encounter = insert_dim_encounter!("boss-one")
    player = insert_player!("Player-One", "One")
    criterion = insert_criterion!(encounter, 101)

    insert_failure!(encounter, player, criterion)

    assert Rebuilds.status() == %{
             imported_pulls_count: 1,
             tracked_failure_rows_count: 1,
             gold_encounters_count: 1,
             failure_facts_count: 1
           }
  end

  test "rebuild_all recomputes facts for all gold encounters from silver rows" do
    first_encounter = insert_dim_encounter!("boss-one")
    second_encounter = insert_dim_encounter!("boss-two")

    first_criterion = insert_criterion!(first_encounter, 101)
    second_criterion = insert_criterion!(second_encounter, 202)

    insert_player_info!(first_encounter, "Player-One", "One")
    insert_player_info!(second_encounter, "Player-Two", "Two")
    insert_damage_taken!(first_encounter, "Player-One", 101, 100, 1)
    insert_damage_taken!(second_encounter, "Player-Two", 202, 200, 1)

    assert {:ok, %{encounters: 2, deleted: 0, inserted: 2, skipped: 0}} =
             Rebuilds.rebuild_all()

    assert fact_exists?(first_encounter, "Player-One", first_criterion)
    assert fact_exists?(second_encounter, "Player-Two", second_criterion)
  end

  test "a failed batch identifies completed, failed and unattempted encounters" do
    first = insert_dim_encounter!("boss-one")
    last = insert_dim_encounter!("boss-two")

    assert {:error,
            %{
              encounter_id: -1,
              completed_encounter_ids: [completed],
              remaining_encounter_ids: [remaining],
              totals: %{encounters: 3}
            }} =
             Rebuilds.rebuild_encounters([first.id, -1, last.id])

    assert completed == first.id
    assert remaining == last.id
  end

  defp fact_exists?(encounter, player_guid, criterion) do
    player = Repo.get_by(DimPlayer, player_guid: player_guid)

    player &&
      Repo.get_by(FactFailure,
        encounter_dim_id: encounter.id,
        player_dim_id: player.id,
        criterion_dim_id: criterion.id
      )
  end

  defp insert_dim_encounter!(wow_encounter_id) do
    source_start_byte = System.unique_integer([:positive])

    %DimEncounter{}
    |> DimEncounter.changeset(%{
      source_head_sha256: String.duplicate("e", 64),
      wow_encounter_id: wow_encounter_id,
      name: "Test Boss",
      difficulty_id: 16,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "test-instance",
      start_time: ~U[2026-06-28 20:00:00Z],
      end_time: ~U[2026-06-28 20:05:00Z],
      success: false,
      fight_time_ms: 300_000,
      start_byte: source_start_byte,
      end_byte: source_start_byte + 1000
    })
    |> Repo.insert!()
  end

  defp insert_player!(guid, name) do
    %DimPlayer{}
    |> DimPlayer.changeset(%{player_guid: guid, player_name: name})
    |> Repo.insert!()
  end

  defp insert_criterion!(%DimEncounter{} = encounter, spell_id) do
    %DimMechanicCriterion{}
    |> DimMechanicCriterion.changeset(%{
      spell_id: spell_id,
      spell_name: "Bad #{spell_id}",
      mechanic_type: "avoidable",
      boss_encounter_id: encounter.wow_encounter_id,
      difficulty_id: 16,
      threshold: %{"max_hits" => 0}
    })
    |> Repo.insert!()
  end

  defp insert_player_info!(encounter, player_guid, player_name) do
    %PlayerInfo{}
    |> PlayerInfo.changeset(%{
      encounter_dim_id: encounter.id,
      player_guid: player_guid,
      player_name: player_name,
      class_id: 1,
      spec_id: 71,
      detected_role: "unknown"
    })
    |> Repo.insert!()
  end

  defp insert_damage_taken!(encounter, player_guid, spell_id, total_amount, hit_count) do
    %DamageTaken{}
    |> DamageTaken.changeset(%{
      encounter_dim_id: encounter.id,
      target_guid: player_guid,
      source_guid: "Creature-A",
      spell_id: spell_id,
      total_amount: total_amount,
      hit_count: hit_count,
      max_hit: total_amount,
      overkill_total: 0,
      source_is_npc: true
    })
    |> Repo.insert!()
  end

  defp insert_failure!(encounter, player, criterion) do
    %FactFailure{}
    |> FactFailure.changeset(%{
      encounter_dim_id: encounter.id,
      player_dim_id: player.id,
      criterion_dim_id: criterion.id,
      product: criterion.product,
      channel: criterion.channel,
      build_version: criterion.build_version,
      build_key: criterion.build_key,
      failure_count: 1,
      total_damage: 100
    })
    |> Repo.insert!()
  end
end

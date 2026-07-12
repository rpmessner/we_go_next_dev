defmodule WeGoNext.Documents.EncounterDocumentTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Documents
  alias WeGoNext.Documents.EncounterDocument

  alias WeGoNext.Gold.{
    DimEncounter,
    DimMechanicCriterion,
    RebuildEncounter
  }

  alias WeGoNext.Gold.FactFailure.Derivation
  alias WeGoNext.Repo
  alias WeGoNext.Rules.Ruleset
  alias WeGoNext.Silver.{DamageTaken, DamageTakenEvent, PlayerInfo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    original_documents_root = Application.fetch_env!(:we_go_next, :documents_root)

    documents_root =
      Path.join(System.tmp_dir!(), "wgn-documents-#{System.unique_integer([:positive])}")

    Application.put_env(:we_go_next, :documents_root, documents_root)

    on_exit(fn ->
      Application.put_env(:we_go_next, :documents_root, original_documents_root)
      File.rm_rf(documents_root)
    end)

    {:ok, documents_root: documents_root}
  end

  test "encodes a versioned document from detail and observed mechanics read models" do
    encounter = insert_encounter!("fixture-boss")
    ruleset = insert_ruleset!("Active Ruleset", "active")
    insert_criterion!(ruleset, encounter, 101)
    insert_player_info!(encounter, "Player-One", "One")
    insert_damage_taken!(encounter, "Player-One", 101, 100, 1)
    insert_damage_taken_event!(encounter, "Player-One", 101, "Bad 101", 100)

    assert {:ok, %{fact_failure: %{inserted: 1}}} = RebuildEncounter.rebuild(encounter)

    assert {:ok, document} =
             EncounterDocument.encode(encounter.id, generated_at: ~U[2026-07-08 12:00:00Z])

    encoded = Jason.encode!(document)
    decoded = Jason.decode!(encoded)

    assert decoded["schema_version"] == EncounterDocument.schema_version()
    assert decoded["generated_at"] == "2026-07-08T12:00:00Z"
    assert decoded["derivation_version"] == Derivation.current_version()
    assert decoded["source_encounter_key"] == encounter.source_encounter_key
    assert decoded["encounter"]["source_encounter_key"] == encounter.source_encounter_key
    assert decoded["encounter"]["name"] == "Fixture Boss"
    refute Map.has_key?(decoded["encounter"], "source_file_path")
    refute Map.has_key?(decoded["encounter"], "source_head_sha256")
    refute Map.has_key?(decoded["encounter"], "start_byte")

    assert [player] = decoded["roster"]
    assert player["player_guid"] == "Player-One"
    assert player["operator"]["encounter_dim_id"] == encounter.id

    assert decoded["failure_preview"]["counts"]["failures"] == 1
    assert [mechanic] = decoded["failure_preview"]["mechanics"]
    assert mechanic["spell_id"] == 101
    assert mechanic["players"] |> List.first() |> get_in(["player_guid"]) == "Player-One"

    assert decoded["observed_mechanics"]["counts"]["observed_spells"] == 1
    assert [observed] = decoded["observed_mechanics"]["mechanics"]
    assert observed["spell_id"] == 101
    assert observed["observed"]["damage_hits"] == 1
    assert observed["facts"]["failure_count"] == 1

    assert observed["classification"] == %{
             "key" => "avoidable",
             "label" => "Avoidable",
             "actionability" => "actionable",
             "fact_eligibility" => "supported"
           }

    refute Map.has_key?(observed["classification"], "threshold")
  end

  test "document generation writes encounter document and index", %{
    documents_root: documents_root
  } do
    encounter = insert_encounter!("indexed-boss")
    insert_player_info!(encounter, "Player-One", "One")

    assert {:ok, %{encounter_path: encounter_path, index_path: index_path}} =
             Documents.generate_for_encounter(encounter.id,
               generated_at: ~U[2026-07-08 12:00:00Z]
             )

    assert encounter_path ==
             Path.join([documents_root, "encounters", "#{encounter.source_encounter_key}.json"])

    assert index_path == Path.join(documents_root, "index.json")

    encounter_json = encounter_path |> File.read!() |> Jason.decode!()
    index_json = index_path |> File.read!() |> Jason.decode!()

    assert encounter_json["source_encounter_key"] == encounter.source_encounter_key
    assert [index_entry] = index_json["encounters"]
    assert index_entry["source_encounter_key"] == encounter.source_encounter_key
    assert index_entry["boss"] == "Fixture Boss"
    assert index_entry["headline_counts"]["players"] == 1
  end

  defp insert_encounter!(wow_encounter_id) do
    source_start_byte = System.unique_integer([:positive])

    %DimEncounter{}
    |> DimEncounter.changeset(%{
      source_head_sha256: String.duplicate("c", 64),
      wow_encounter_id: wow_encounter_id,
      name: "Fixture Boss",
      difficulty_id: 16,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "fixture-instance",
      start_time: ~U[2026-07-08 12:00:00Z],
      end_time: ~U[2026-07-08 12:05:00Z],
      success: false,
      fight_time_ms: 300_000,
      start_byte: source_start_byte,
      end_byte: source_start_byte + 1000
    })
    |> Repo.insert!()
  end

  defp insert_ruleset!(name, status) do
    %Ruleset{}
    |> Ruleset.changeset(%{name: name, status: status})
    |> Repo.insert!()
  end

  defp insert_criterion!(%Ruleset{} = ruleset, %DimEncounter{} = encounter, spell_id) do
    %DimMechanicCriterion{}
    |> DimMechanicCriterion.changeset(%{
      source_rule_id: System.unique_integer([:positive]),
      ruleset_id: ruleset.id,
      ruleset_version: ruleset.version,
      product: ruleset.product,
      channel: ruleset.channel,
      build_version: ruleset.build_version,
      build_key: ruleset.build_key,
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
      detected_role: "dps"
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

  defp insert_damage_taken_event!(encounter, player_guid, spell_id, spell_name, amount) do
    %DamageTakenEvent{}
    |> DamageTakenEvent.changeset(%{
      encounter_dim_id: encounter.id,
      combat_log_event_index: System.unique_integer([:positive]),
      event_type: "SPELL_DAMAGE",
      occurred_at_ms_into_fight: 10_000,
      target_guid: player_guid,
      target_name: "One",
      source_guid: "Creature-A",
      source_name: "Fixture Boss",
      source_is_npc: true,
      spell_id: spell_id,
      spell_name: spell_name,
      spell_school: 1,
      amount: amount,
      overkill: 0
    })
    |> Repo.insert!()
  end
end

defmodule WeGoNext.Gold.RebuildEncounterTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Gold.{
    DimEncounter,
    DimMechanicCriterion,
    DimPlayer,
    FactFailure,
    RebuildEncounter
  }

  alias WeGoNext.Mirror.MirrorUpload
  alias WeGoNext.Repo
  alias WeGoNext.Rules.Ruleset
  alias WeGoNext.Silver.{DamageTaken, PlayerInfo}

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

    encounter = insert_dim_encounter!("boss-one")

    {:ok, encounter: encounter, documents_root: documents_root}
  end

  test "rebuild/2 runs the current fact_failure builder with the active ruleset", %{
    encounter: encounter,
    documents_root: documents_root
  } do
    ruleset = insert_ruleset!("Active Ruleset", "active")
    criterion = insert_criterion!(ruleset, encounter, 101)

    insert_player_info!(encounter, "Player-One", "One")
    insert_damage_taken!(encounter, "Player-One", 101, 100, 1)

    assert {:ok, %{fact_failure: %{deleted: 0, inserted: 1}}} =
             RebuildEncounter.rebuild(encounter)

    player = Repo.get_by!(DimPlayer, player_guid: "Player-One")

    assert %FactFailure{failure_count: 1, total_damage: 100} =
             Repo.get_by!(FactFailure,
               encounter_dim_id: encounter.id,
               player_dim_id: player.id,
               criterion_dim_id: criterion.id
             )

    assert File.exists?(
             Path.join([documents_root, "encounters", "#{encounter.source_encounter_key}.json"])
           )

    assert File.exists?(Path.join(documents_root, "index.json"))
  end

  test "rebuild/2 passes through an explicit ruleset id", %{encounter: encounter} do
    active_ruleset = insert_ruleset!("Active Ruleset", "active")
    explicit_ruleset = insert_ruleset!("Explicit Ruleset", "draft", build_key: "explicit")

    active_criterion = insert_criterion!(active_ruleset, encounter, 202)
    explicit_criterion = insert_criterion!(explicit_ruleset, encounter, 202)

    insert_player_info!(encounter, "Player-One", "One")
    insert_damage_taken!(encounter, "Player-One", 202, 100, 1)

    assert {:ok, %{fact_failure: %{inserted: 1}}} =
             RebuildEncounter.rebuild(encounter.id, ruleset_id: explicit_ruleset.id)

    assert Repo.get_by(FactFailure,
             encounter_dim_id: encounter.id,
             criterion_dim_id: explicit_criterion.id
           )

    refute Repo.get_by(FactFailure,
             encounter_dim_id: encounter.id,
             criterion_dim_id: active_criterion.id
           )
  end

  test "rebuild/2 treats a missing active ruleset as a skipped gold rebuild", %{
    encounter: encounter
  } do
    assert {:ok,
            %{
              fact_failure: %{
                deleted: 0,
                inserted: 0,
                skipped: :active_ruleset_not_found
              }
            }} = RebuildEncounter.rebuild(encounter)
  end

  test "rebuild/2 enqueues mirror upload intent after successful rebuild" do
    encounter = insert_dim_encounter_with_source_key!("boss-mirror")
    ruleset = insert_ruleset!("Mirror Ruleset", "active")
    insert_criterion!(ruleset, encounter, 303)

    insert_player_info!(encounter, "Player-One", "One")
    insert_damage_taken!(encounter, "Player-One", 303, 100, 1)

    assert {:ok, %{fact_failure: %{inserted: 1}}} = RebuildEncounter.rebuild(encounter)

    assert %MirrorUpload{state: "pending"} =
             Repo.get_by!(MirrorUpload, source_encounter_key: encounter.source_encounter_key)
  end

  defp insert_dim_encounter!(wow_encounter_id) do
    source_start_byte = System.unique_integer([:positive])

    %DimEncounter{}
    |> DimEncounter.changeset(%{
      source_head_sha256: String.duplicate("a", 64),
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

  defp insert_dim_encounter_with_source_key!(wow_encounter_id) do
    source_start_byte = System.unique_integer([:positive])

    %DimEncounter{}
    |> DimEncounter.changeset(%{
      source_head_sha256: String.duplicate("a", 64),
      wow_encounter_id: wow_encounter_id,
      name: "Test Boss",
      difficulty_id: 16,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "test-instance",
      start_time: ~U[2026-06-28 20:00:00Z],
      start_byte: source_start_byte,
      end_byte: source_start_byte + 1000
    })
    |> Repo.insert!()
  end

  defp insert_ruleset!(name, status, attrs \\ %{}) do
    %Ruleset{}
    |> Ruleset.changeset(Map.merge(%{name: name, status: status}, Map.new(attrs)))
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
end

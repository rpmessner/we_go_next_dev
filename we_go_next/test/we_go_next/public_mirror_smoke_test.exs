defmodule WeGoNext.PublicMirrorSmokeTest do
  use WeGoNextWeb.ConnCase, async: false

  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer, FactFailure}
  alias WeGoNext.Mirror.{MirrorUpload, PublicReport}
  alias WeGoNext.PublicMirrorSmoke
  alias WeGoNext.Repo
  alias WeGoNext.Rules.Ruleset
  alias WeGoNext.Silver.PlayerInfo
  alias WeGoNext.Support.{StubDestinationDocumentStore, StubSourceDocumentStore}

  setup do
    original_mode = WeGoNext.mode()
    original_documents_store = Application.get_env(:we_go_next, :documents_store)

    Application.put_env(:we_go_next, :mode, :public)
    Application.put_env(:we_go_next, :documents_store, StubDestinationDocumentStore)
    StubSourceDocumentStore.reset!()
    StubDestinationDocumentStore.reset!()

    on_exit(fn ->
      Application.put_env(:we_go_next, :mode, original_mode)
      restore_env(:documents_store, original_documents_store)
      StubSourceDocumentStore.reset!()
      StubDestinationDocumentStore.reset!()
    end)

    %{report: insert_report!("raid-night", "Raid Night")}
  end

  test "smoke rebuilds, uploads, and renders factful and zero-failure documents", %{conn: conn} do
    factful = insert_factful_encounter!()
    zero_failure = insert_zero_failure_encounter!()

    assert {:ok, result} =
             PublicMirrorSmoke.run(
               factful_encounter_id: factful.id,
               zero_failure_encounter_id: zero_failure.id,
               slug: "raid-night",
               source_store: StubSourceDocumentStore,
               destination_store: StubDestinationDocumentStore,
               max_concurrency: 1
             )

    assert result.factful.failures == 2
    assert result.factful.upload_state == "published"
    assert result.zero_failure.failures == 0
    assert result.zero_failure.players == 1
    assert result.zero_failure.upload_state == "published"
    assert %{published: 2, error: 0} = result.drain

    assert %MirrorUpload{state: "published"} =
             Repo.get_by!(MirrorUpload, source_encounter_key: factful.source_encounter_key)

    assert {:ok, _body} =
             StubDestinationDocumentStore.fetch("encounters/#{factful.source_encounter_key}.json")

    assert {:ok, _body} =
             StubDestinationDocumentStore.fetch(
               "encounters/#{zero_failure.source_encounter_key}.json"
             )

    list_html =
      conn
      |> get(~p"/r/raid-night")
      |> html_response(200)

    assert list_html =~ "Factful Fixture Boss"
    assert list_html =~ "Clean Fixture Boss"

    factful_html =
      conn
      |> get(~p"/r/raid-night/encounters/#{factful.source_encounter_key}?tab=failures")
      |> html_response(200)

    assert factful_html =~ "Factful Fixture Boss"
    assert factful_html =~ "Avoidable Blast"
    assert factful_html =~ "Failure One"
    assert factful_html =~ "2"

    zero_failure_html =
      conn
      |> get(~p"/r/raid-night/encounters/#{zero_failure.source_encounter_key}")
      |> html_response(200)

    assert zero_failure_html =~ "Clean Fixture Boss"
    assert zero_failure_html =~ "Clean Player"
    assert zero_failure_html =~ "Failures"
    refute zero_failure_html =~ "Empty Encounter Document"
    refute zero_failure_html =~ "Encounter Not Found"
  end

  defp insert_report!(slug, title) do
    %PublicReport{}
    |> PublicReport.changeset(%{slug: slug, title: title, enabled: true})
    |> Repo.insert!()
  end

  defp insert_factful_encounter! do
    encounter = insert_encounter!("Factful Fixture Boss")
    player = insert_dim_player!("Player-Failure-One", "Failure One")
    insert_player_info!(encounter, "Player-Failure-One", "Failure One")
    criterion = insert_criterion!(901, "Avoidable Blast")

    %FactFailure{}
    |> FactFailure.changeset(%{
      encounter_dim_id: encounter.id,
      player_dim_id: player.id,
      criterion_dim_id: criterion.id,
      ruleset_id: criterion.ruleset_id,
      ruleset_version: criterion.ruleset_version,
      product: criterion.product,
      channel: criterion.channel,
      build_version: criterion.build_version,
      build_key: criterion.build_key,
      derivation_version: WeGoNext.Documents.current_derivation_version(),
      rebuilt_at: ~U[2026-07-09 12:00:00Z],
      failure_count: 2,
      total_damage: 44_000
    })
    |> Repo.insert!()

    encounter
  end

  defp insert_zero_failure_encounter! do
    encounter = insert_encounter!("Clean Fixture Boss")
    insert_player_info!(encounter, "Player-Clean", "Clean Player")
    encounter
  end

  defp insert_encounter!(name) do
    source_start_byte = System.unique_integer([:positive])

    %DimEncounter{}
    |> DimEncounter.changeset(%{
      source_head_sha256: sha256(name),
      wow_encounter_id: "smoke-#{source_start_byte}",
      name: name,
      difficulty_id: 16,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "smoke-instance",
      start_time: ~U[2026-07-09 12:00:00Z],
      end_time: ~U[2026-07-09 12:05:00Z],
      success: false,
      fight_time_ms: 300_000,
      start_byte: source_start_byte,
      end_byte: source_start_byte + 1_000
    })
    |> Repo.insert!()
  end

  defp insert_player_info!(encounter, player_guid, player_name) do
    %PlayerInfo{}
    |> PlayerInfo.changeset(%{
      encounter_dim_id: encounter.id,
      player_guid: player_guid,
      player_name: player_name,
      class_id: 9,
      spec_id: 266,
      detected_role: "dps"
    })
    |> Repo.insert!()
  end

  defp insert_dim_player!(player_guid, player_name) do
    %DimPlayer{}
    |> DimPlayer.changeset(%{player_guid: player_guid, player_name: player_name})
    |> Repo.insert!()
  end

  defp insert_criterion!(spell_id, spell_name) do
    ruleset =
      %Ruleset{}
      |> Ruleset.changeset(%{name: "Smoke Rules #{System.unique_integer([:positive])}"})
      |> Repo.insert!()

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
      spell_name: spell_name,
      mechanic_type: "avoidable",
      threshold: %{"max_hits" => 0},
      active: true
    })
    |> Repo.insert!()
  end

  defp sha256(value) do
    value
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp restore_env(key, nil), do: Application.delete_env(:we_go_next, key)
  defp restore_env(key, value), do: Application.put_env(:we_go_next, key, value)
end

defmodule WeGoNext.SourceDataTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias WeGoNext.Repo
  alias WeGoNext.SourceData
  alias WeGoNext.Gold.DimEncounter

  alias WeGoNext.SourceData.{
    DbmMechanicCandidate,
    EncounterReference,
    EncounterSpellReference,
    SourceImport,
    SpellReference,
    WarcraftLogsApiFetch,
    WowAnalyzerTimelineCandidate
  }

  alias WeGoNext.Silver.{DamageDone, PlayerInfo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "source-data schemas live in the source_data prefix" do
    assert SourceImport.__schema__(:prefix) == "source_data"
    assert SourceImport.__schema__(:source) == "source_import"

    assert DbmMechanicCandidate.__schema__(:prefix) == "source_data"
    assert DbmMechanicCandidate.__schema__(:source) == "dbm_mechanic_candidate"
    assert DbmMechanicCandidate.__schema__(:association, :source_import).related == SourceImport

    assert SpellReference.__schema__(:prefix) == "source_data"
    assert SpellReference.__schema__(:source) == "spell_reference"
    assert SpellReference.__schema__(:association, :source_import).related == SourceImport

    assert EncounterReference.__schema__(:prefix) == "source_data"
    assert EncounterReference.__schema__(:source) == "encounter_reference"
    assert EncounterReference.__schema__(:association, :source_import).related == SourceImport

    assert EncounterSpellReference.__schema__(:prefix) == "source_data"
    assert EncounterSpellReference.__schema__(:source) == "encounter_spell_reference"

    assert EncounterSpellReference.__schema__(:association, :source_import).related ==
             SourceImport

    assert WowAnalyzerTimelineCandidate.__schema__(:prefix) == "source_data"
    assert WowAnalyzerTimelineCandidate.__schema__(:source) == "wowanalyzer_timeline_candidate"

    assert WowAnalyzerTimelineCandidate.__schema__(:association, :source_import).related ==
             SourceImport

    assert WarcraftLogsApiFetch.__schema__(:prefix) == "source_data"
    assert WarcraftLogsApiFetch.__schema__(:source) == "warcraft_logs_api_fetch"
    assert WarcraftLogsApiFetch.__schema__(:association, :source_import).related == SourceImport
  end

  test "imports a DBM file idempotently with source and line provenance" do
    path =
      write_dbm_fixture("""
      local mod = DBM:NewMod(2737, "DBM-Raids-Midnight", 3, 1307)
      mod:SetRevision("20260509052555")
      mod:SetCreatureID(250589)
      mod:SetEncounterID(3180)
      mod:SetZone(2912)

      local specWarnDivineToll = mod:NewSpecialWarningDodgeCount(1248652, nil, nil, DBM_COMMON_L.DODGES, 2, 2)
      local specWarnExecutionSentence = mod:NewSpecialWarningSoakCount(1276368, nil, nil, DBM_COMMON_L.GROUPSOAKS, 2, 2)

      local function setFallback(self)
        specWarnDivineToll:SetAlert(80, "watchstep", 2, 3)
        specWarnExecutionSentence:SetAlert(85, "soakincoming", 19, 2)
      end
      """)

    assert {:ok, first_import} =
             SourceData.import_dbm_file(path,
               product: "wow",
               channel: "ptr",
               build_version: "11.2.5.12345",
               build_key: "11.2.5"
             )

    assert length(first_import.candidates) == 2

    assert {:ok, second_import} =
             SourceData.import_dbm_file(path,
               product: "wow",
               channel: "ptr",
               build_version: "11.2.5.12345",
               build_key: "11.2.5"
             )

    assert second_import.source_import.id == first_import.source_import.id
    assert length(second_import.candidates) == 2

    assert Repo.aggregate(SourceImport, :count) == 1
    assert Repo.aggregate(DbmMechanicCandidate, :count) == 2

    dodge = Repo.get_by!(DbmMechanicCandidate, spell_id: 1_248_652)
    assert dodge.source_import_id == first_import.source_import.id
    assert dodge.module_addon == "DBM-Raids-Midnight"
    assert dodge.module_id == 2737
    assert dodge.module_map_id == 1307
    assert dodge.module_revision == "20260509052555"
    assert dodge.encounter_id == 3180
    assert dodge.zone_id == 2912
    assert dodge.creature_ids == [250_589]
    assert dodge.warning_constructor == "NewSpecialWarningDodgeCount"
    assert dodge.label_tokens == ["DODGES"]
    assert dodge.alert_tokens == ["watchstep"]
    assert dodge.inferred_mechanic_type == "avoidable"
    assert dodge.confidence == "high"
    assert dodge.review_status == "inferred"
    assert dodge.source_file == path
    assert dodge.source_line > 0
    assert dodge.product == "wow"
    assert dodge.channel == "ptr"
    assert dodge.build_version == "11.2.5.12345"
    assert dodge.build_key == "11.2.5"

    assert SourceData.list_dbm_candidates(inferred_mechanic_type: "soak")
           |> Enum.map(& &1.spell_id) == [1_276_368]
  end

  test "changed DBM file content creates a new versioned source import" do
    path =
      write_dbm_fixture("""
      local mod = DBM:NewMod(2737, "DBM-Raids-Midnight", 3, 1307)
      mod:SetRevision("1")
      mod:SetEncounterID(3180)
      local specWarnOne = mod:NewSpecialWarningInterrupt(111, "HasInterrupt", nil, nil, 1, 2)
      """)

    assert {:ok, _first_import} = SourceData.import_dbm_file(path)

    File.write!(path, """
    local mod = DBM:NewMod(2737, "DBM-Raids-Midnight", 3, 1307)
    mod:SetRevision("2")
    mod:SetEncounterID(3180)
    local specWarnTwo = mod:NewSpecialWarningInterrupt(222, "HasInterrupt", nil, nil, 1, 2)
    """)

    assert {:ok, _second_import} = SourceData.import_dbm_file(path)

    assert Repo.aggregate(SourceImport, :count) == 2

    imported_revisions =
      SourceImport
      |> order_by([source_import], asc: source_import.addon_revision)
      |> select([source_import], source_import.addon_revision)
      |> Repo.all()

    assert imported_revisions == ["1", "2"]

    assert SourceData.list_dbm_candidates()
           |> Enum.map(& &1.spell_id)
           |> Enum.sort() == [111, 222]
  end

  test "imports DBM roots with aggregate inserted and refreshed candidate counts" do
    first_root = make_dbm_root!("DBM-Raids-Midnight")
    second_root = make_dbm_root!("DBM-Party-Midnight")

    write_dbm_module!(
      first_root,
      "BossOne.lua",
      """
      local mod = DBM:NewMod(2737, "DBM-Raids-Midnight", 3, 1307)
      mod:SetRevision("1")
      mod:SetEncounterID(3180)
      local specWarnOne = mod:NewSpecialWarningInterrupt(111, "HasInterrupt", nil, nil, 1, 2)
      """
    )

    write_dbm_module!(
      first_root,
      "BossWithoutWarnings.lua",
      """
      local mod = DBM:NewMod(2738, "DBM-Raids-Midnight", 3, 1307)
      mod:SetRevision("1")
      mod:SetEncounterID(3181)
      """
    )

    write_dbm_module!(
      second_root,
      "BossTwo.lua",
      """
      local mod = DBM:NewMod(2740, "DBM-Party-Midnight", 3, 1308)
      mod:SetRevision("1")
      mod:SetEncounterID(3182)
      local specWarnTwo = mod:NewSpecialWarningDodge(222, nil, nil, DBM_COMMON_L.DODGES, 1, 2)
      """
    )

    assert {:ok, first_summary} =
             SourceData.import_dbm_midnight_sources(
               roots: [first_root, second_root],
               build_key: "11.2.5"
             )

    assert first_summary.files_imported == 2
    assert first_summary.source_imports_inserted == 2
    assert first_summary.source_imports_updated == 0
    assert first_summary.candidates_inserted == 2
    assert first_summary.candidates_updated == 0

    assert {:ok, second_summary} =
             SourceData.import_dbm_midnight_sources(
               roots: [first_root, second_root],
               build_key: "11.2.5"
             )

    assert second_summary.files_imported == 2
    assert second_summary.source_imports_inserted == 0
    assert second_summary.source_imports_updated == 2
    assert second_summary.candidates_inserted == 0
    assert second_summary.candidates_updated == 2

    assert Repo.aggregate(DbmMechanicCandidate, :count) == 2
  end

  test "DBM bulk import reports missing roots" do
    missing_root =
      Path.join(System.tmp_dir!(), "wgn-missing-#{System.unique_integer([:positive])}")

    assert {:error, {:missing_roots, [^missing_root]}} =
             SourceData.import_dbm_midnight_sources(roots: [missing_root])
  end

  test "imports a WowAnalyzer timeline file idempotently with AGPL provenance" do
    path =
      write_wowanalyzer_fixture("""
      export const Chimaerus = buildBoss({
        id: 3306,
        name: 'Chimaerus the Undreamt God',
        timeline: {
          abilities: [
            // Alndust Upheaval (group soak)
            { id: 1262289, type: 'cast' },
            // summon kick adds
            { id: 1258610, type: 'summon' },
          ],
          debuffs: [
            // Consuming Miasma (dispel debuff)
            { id: 1257087 },
          ],
        },
      });
      """)

    assert {:ok, first_import} =
             SourceData.import_wowanalyzer_file(path,
               build_key: "11.2.5",
               build_version: "11.2.5.12345",
               channel: "ptr",
               repository_revision: "fixture-revision"
             )

    assert first_import.source_import_action == :inserted
    assert length(first_import.candidates) == 3
    assert first_import.inserted_candidate_count == 3

    assert {:ok, second_import} =
             SourceData.import_wowanalyzer_file(path,
               build_key: "11.2.5",
               build_version: "11.2.5.12345",
               channel: "ptr",
               repository_revision: "fixture-revision"
             )

    assert second_import.source_import.id == first_import.source_import.id
    assert second_import.source_import_action == :updated
    assert second_import.updated_candidate_count == 3

    assert Repo.aggregate(SourceImport, :count) == 1
    assert Repo.aggregate(WowAnalyzerTimelineCandidate, :count) == 3

    source_import = Repo.get!(SourceImport, first_import.source_import.id)
    assert source_import.addon_revision == "fixture-revision"
    assert source_import.metadata["repository_license"] == "AGPL-3.0-or-later"
    assert source_import.metadata["agpl_handling"] =~ "runtime code is not copied"

    soak = Repo.get_by!(WowAnalyzerTimelineCandidate, spell_id: 1_262_289)
    assert soak.source_import_id == first_import.source_import.id
    assert soak.raid_slug == "vs_dr_mqd"
    assert soak.raid_name == "VS / DR / MQD"
    assert soak.encounter_id == 3306
    assert soak.encounter_name == "Chimaerus the Undreamt God"
    assert soak.timeline_type == "ability"
    assert soak.event_type == "cast"
    assert soak.comment == "Alndust Upheaval (group soak)"
    assert soak.inferred_mechanic_type == "soak"
    assert soak.confidence == "high"
    assert soak.review_status == "inferred"
    assert soak.repository_revision == "fixture-revision"
    assert soak.repository_license == "AGPL-3.0-or-later"
    assert soak.source_file == path
    assert soak.source_line > 0
    assert soak.raw_entry == %{"id" => 1_262_289, "type" => "cast"}
    assert soak.product == "wow"
    assert soak.channel == "ptr"
    assert soak.build_version == "11.2.5.12345"
    assert soak.build_key == "11.2.5"

    assert SourceData.list_wowanalyzer_timeline_candidates(inferred_mechanic_type: "interrupt")
           |> Enum.map(& &1.spell_id) == [1_258_610]
  end

  test "imports WowAnalyzer roots with aggregate inserted and refreshed candidate counts" do
    root = make_wowanalyzer_root!()

    write_wowanalyzer_module!(
      root,
      "Chimaerus.ts",
      """
      export const Chimaerus = buildBoss({
        id: 3306,
        name: 'Chimaerus the Undreamt God',
        timeline: {
          abilities: [
            // Alndust Upheaval (group soak)
            { id: 1262289, type: 'cast' },
          ],
        },
      });
      """
    )

    write_wowanalyzer_module!(
      root,
      "Indexless.ts",
      """
      export const Indexless = buildBoss({
        id: 3307,
        name: 'No Timeline Yet',
      });
      """
    )

    assert {:ok, first_summary} =
             SourceData.import_wowanalyzer_sources(
               roots: [root],
               repository_revision: "fixture-revision",
               build_key: "11.2.5"
             )

    assert first_summary.files_imported == 1
    assert first_summary.source_imports_inserted == 1
    assert first_summary.source_imports_updated == 0
    assert first_summary.candidates_inserted == 1
    assert first_summary.candidates_updated == 0
    assert first_summary.repository_license == "AGPL-3.0-or-later"

    assert {:ok, second_summary} =
             SourceData.import_wowanalyzer_sources(
               roots: [root],
               repository_revision: "fixture-revision",
               build_key: "11.2.5"
             )

    assert second_summary.files_imported == 1
    assert second_summary.source_imports_inserted == 0
    assert second_summary.source_imports_updated == 1
    assert second_summary.candidates_inserted == 0
    assert second_summary.candidates_updated == 1

    assert Repo.aggregate(WowAnalyzerTimelineCandidate, :count) == 1
  end

  test "WowAnalyzer bulk import reports missing roots" do
    missing_root =
      Path.join(System.tmp_dir!(), "wgn-missing-wa-#{System.unique_integer([:positive])}")

    assert {:error, {:missing_roots, [^missing_root]}} =
             SourceData.import_wowanalyzer_sources(roots: [missing_root])
  end

  test "imports Warcraft Logs API response payload idempotently as external evidence" do
    bronze_root = make_bronze_root!()

    payload =
      warcraft_logs_payload(%{"id" => 1, "type" => "damage", "abilityGameID" => 1_214_081})

    fetched_at = ~U[2026-05-31 12:00:00.000000Z]

    assert {:ok, first_import} =
             SourceData.import_warcraft_logs_api_response(%{
               report_code: "abc123",
               fight_id: 17,
               source_url: "https://www.warcraftlogs.com/reports/abc123#fight=17",
               query_name: "DamageTakenEvents",
               query_document:
                 "query DamageTakenEvents($fightIDs: [Int]) { reportData { report { events { data } } } }",
               query_variables: %{fightIDs: [17]},
               request_params: %{startTime: 0, endTime: 90_000},
               response_payload: payload,
               fetched_at: fetched_at,
               channel: "retail",
               build_key: "local",
               bronze_root: bronze_root,
               metadata: %{comparison_target: "local silver damage taken"}
             })

    assert first_import.source_import_action == :inserted
    assert first_import.fetch.report_code == "abc123"
    assert first_import.fetch.fight_id == 17
    assert first_import.fetch.query_name == "DamageTakenEvents"
    assert first_import.fetch.query_variables == %{"fightIDs" => [17]}
    assert first_import.fetch.request_params == %{"endTime" => 90_000, "startTime" => 0}
    assert first_import.fetch.response_payload == payload
    assert first_import.fetch.fetched_at == fetched_at
    assert first_import.fetch.response_hash == first_import.source_import.content_hash
    assert first_import.fetch.request_hash =~ ~r/^[0-9a-f]{64}$/
    assert first_import.fetch.response_hash =~ ~r/^[0-9a-f]{64}$/
    assert first_import.fetch.artifact_path =~ bronze_root
    assert first_import.fetch.artifact_hash =~ ~r/^[0-9a-f]{64}$/
    assert first_import.fetch.artifact_bytes > 0
    assert File.regular?(first_import.fetch.artifact_path)
    assert first_import.fetch.product == "wow"
    assert first_import.fetch.channel == "retail"
    assert first_import.fetch.build_key == "local"

    source_import = Repo.get!(SourceImport, first_import.source_import.id)
    assert source_import.source_system == "warcraft_logs_api"
    assert source_import.source_path == first_import.fetch.artifact_path
    assert source_import.metadata["source_format"] == "warcraft_logs_api_response"
    assert source_import.metadata["annotation_only"] =~ "does not create active rules"
    assert source_import.metadata["request_params"] == %{"endTime" => 90_000, "startTime" => 0}
    assert source_import.metadata["artifact_path"] == first_import.fetch.artifact_path

    assert source_import.metadata["canonical_source_uri"] =~
             "warcraftlogs://reports/abc123/fights/17"

    artifact = first_import.fetch.artifact_path |> File.read!() |> Jason.decode!()
    assert artifact["response_payload"] == payload
    assert artifact["response_hash"] == first_import.fetch.response_hash

    assert {:ok, second_import} =
             SourceData.import_warcraft_logs_api_response(%{
               report_code: "abc123",
               fight_id: 17,
               source_url: "https://www.warcraftlogs.com/reports/abc123#fight=17",
               query_name: "DamageTakenEvents",
               query_document:
                 "query DamageTakenEvents($fightIDs: [Int]) { reportData { report { events { data } } } }",
               query_variables: %{fightIDs: [17]},
               request_params: %{startTime: 0, endTime: 90_000},
               response_payload: payload,
               fetched_at: fetched_at,
               channel: "retail",
               build_key: "local",
               bronze_root: bronze_root
             })

    assert second_import.source_import_action == :updated
    assert second_import.source_import.id == first_import.source_import.id
    assert second_import.fetch.id == first_import.fetch.id
    assert Repo.aggregate(SourceImport, :count) == 1
    assert Repo.aggregate(WarcraftLogsApiFetch, :count) == 1

    assert SourceData.list_warcraft_logs_api_fetches(report_code: "abc123", fight_id: "17")
           |> Enum.map(& &1.id) == [first_import.fetch.id]
  end

  test "changed Warcraft Logs API response creates a new versioned source import" do
    bronze_root = make_bronze_root!()

    attrs = %{
      report_code: "abc123",
      fight_id: 17,
      query_name: "Events",
      request_params: %{startTime: 0, endTime: 90_000},
      fetched_at: ~U[2026-05-31 12:00:00.000000Z],
      bronze_root: bronze_root
    }

    assert {:ok, first_import} =
             SourceData.import_warcraft_logs_api_response(
               Map.put(attrs, :response_payload, warcraft_logs_payload(%{"id" => 1}))
             )

    assert {:ok, second_import} =
             SourceData.import_warcraft_logs_api_response(
               Map.put(attrs, :response_payload, warcraft_logs_payload(%{"id" => 2}))
             )

    assert second_import.source_import_action == :inserted
    refute second_import.source_import.id == first_import.source_import.id
    refute second_import.fetch.response_hash == first_import.fetch.response_hash
    assert Repo.aggregate(SourceImport, :count) == 2
    assert Repo.aggregate(WarcraftLogsApiFetch, :count) == 2
  end

  test "imports Warcraft Logs API response JSON files" do
    bronze_root = make_bronze_root!()
    path = write_json_fixture(warcraft_logs_payload(%{"id" => 1, "type" => "cast"}))

    assert {:ok, import} =
             SourceData.import_warcraft_logs_api_response_file(path,
               report_code: "file123",
               fight_id: 22,
               query_name: "Casts",
               request_params: %{startTime: 10, endTime: 20},
               bronze_root: bronze_root
             )

    assert import.source_import_action == :inserted
    assert import.fetch.report_code == "file123"
    assert import.fetch.response_payload["data"]
    assert File.regular?(import.fetch.artifact_path)
  end

  test "compares Warcraft Logs damage done totals against local silver rows" do
    bronze_root = make_bronze_root!()

    encounter =
      %DimEncounter{}
      |> DimEncounter.changeset(%{
        wow_encounter_id: "wcl-compare",
        name: "WCL Compare",
        difficulty_id: 16
      })
      |> Repo.insert!()

    insert_player_info!(encounter, "Player-Dps", "Dps-Realm")
    insert_player_info!(encounter, "Player-Other", "Other-Realm")
    insert_damage_done!(encounter, "Player-Dps", "Creature-Boss", 101, 1_000)
    insert_damage_done!(encounter, "Player-Dps", "Creature-Add", 102, 500)
    insert_damage_done!(encounter, "Player-Other", "Creature-Boss", 101, 200)

    assert {:ok, import} =
             SourceData.import_warcraft_logs_api_response(%{
               report_code: "abc123",
               fight_id: 17,
               query_name: "DamageDoneTable",
               response_payload:
                 warcraft_logs_table_payload([
                   %{"id" => 1, "name" => "Dps", "total" => 1_500, "type" => "Warlock"},
                   %{"id" => 2, "name" => "Other", "total" => 250, "type" => "Mage"},
                   %{"id" => 3, "name" => "Missing", "total" => 100, "type" => "Priest"}
                 ]),
               fetched_at: ~U[2026-05-31 12:00:00.000000Z],
               bronze_root: bronze_root
             })

    assert {:ok, comparison} =
             SourceData.compare_warcraft_logs_damage_done(encounter.id, import.fetch)

    assert comparison.local_total == 1_700
    assert comparison.warcraft_logs_total == 1_850
    assert comparison.delta == -150
    assert comparison.artifact_path == import.fetch.artifact_path
    assert comparison.matched_count == 1
    assert comparison.mismatched_count == 1
    assert comparison.warcraft_logs_only_count == 1

    assert [
             %{
               player_name: "Dps-Realm",
               local_total: 1_500,
               warcraft_logs_total: 1_500,
               status: :matched
             },
             %{
               player_name: "Missing",
               local_total: 0,
               warcraft_logs_total: 100,
               status: :warcraft_logs_only
             },
             %{
               player_name: "Other-Realm",
               local_total: 200,
               warcraft_logs_total: 250,
               status: :mismatched
             }
           ] = comparison.players
  end

  test "spell reference lookup honors source priority and build-separated channels" do
    attrs = %{
      spell_id: 123_456,
      current_name: "Low Priority Name",
      localized_names: %{"enUS" => "Low Priority Name"},
      product: "wow",
      channel: "retail",
      build_key: "11.2.0",
      locale: "enUS",
      source_system: "low_priority",
      source_priority: 50
    }

    assert {:ok, _reference} = SourceData.upsert_spell_reference(attrs)

    assert {:ok, _reference} =
             SourceData.upsert_spell_reference(%{
               attrs
               | current_name: "High Priority Name",
                 source_system: "high_priority",
                 source_priority: 10
             })

    assert {:ok, _reference} =
             SourceData.upsert_spell_reference(%{
               attrs
               | current_name: "Beta Name",
                 channel: "beta",
                 source_system: "beta_source",
                 source_priority: 1
             })

    assert {:ok, _reference} =
             SourceData.upsert_spell_reference(%{
               attrs
               | current_name: "PTR Name",
                 channel: "ptr",
                 source_system: "ptr_source",
                 source_priority: 1
             })

    assert SourceData.resolve_spell_name(123_456, build_key: "11.2.0") ==
             "High Priority Name"

    assert SourceData.resolve_spell_name(123_456, build_key: "11.2.0", channel: "beta") ==
             "Beta Name"

    assert SourceData.resolve_spell_name(123_456, build_key: "11.2.0", channel: "ptr") ==
             "PTR Name"

    assert Repo.aggregate(SpellReference, :count) == 4
  end

  test "encounter reference lookup keeps build scope and zone context" do
    attrs = %{
      encounter_id: 3180,
      current_name: "Retail Boss",
      localized_names: %{"enUS" => "Retail Boss"},
      zone_id: 2912,
      zone_name: "Manaforge Omega",
      instance_id: 1307,
      instance_name: "Manaforge Omega",
      difficulty_id: 0,
      product: "wow",
      channel: "retail",
      build_key: "11.2.0",
      locale: "enUS",
      source_system: "encounter_journal",
      source_priority: 20
    }

    assert {:ok, _reference} = SourceData.upsert_encounter_reference(attrs)

    assert {:ok, _reference} =
             SourceData.upsert_encounter_reference(%{
               attrs
               | current_name: "PTR Boss",
                 channel: "ptr",
                 build_key: "11.2.5",
                 difficulty_id: 16,
                 source_priority: 1
             })

    assert SourceData.resolve_encounter_name("3180", build_key: "11.2.0") == "Retail Boss"

    assert SourceData.resolve_encounter_name(3180, build_key: "11.2.5", channel: "ptr") ==
             "PTR Boss"

    reference = SourceData.get_encounter_reference(3180, build_key: "11.2.0")
    assert reference.zone_id == 2912
    assert reference.instance_id == 1307
    assert reference.difficulty_id == 0

    reference =
      SourceData.get_encounter_reference(3180,
        build_key: "11.2.5",
        channel: "ptr",
        difficulty_id: 16
      )

    assert reference.current_name == "PTR Boss"
    assert reference.difficulty_id == 16

    assert Repo.aggregate(EncounterReference, :count) == 2
  end

  test "imports spell references from local spell-name JSON maps" do
    path =
      write_json_fixture(%{
        "1214081" => "Arcane Expulsion",
        "1269183" => "Void Burst"
      })

    assert {:ok, import} =
             SourceData.import_reference_metadata_file(path,
               build_key: "11.2.5",
               build_version: "11.2.5.12345"
             )

    assert import.source_import_action == :inserted
    assert import.spells_inserted == 2
    assert import.encounters_inserted == 0
    assert import.encounter_spells_inserted == 0

    assert {:ok, second_import} =
             SourceData.import_reference_metadata_file(path,
               build_key: "11.2.5",
               build_version: "11.2.5.12345"
             )

    assert second_import.source_import_action == :updated
    assert second_import.spells_inserted == 0
    assert second_import.spells_updated == 2

    reference = SourceData.get_spell_reference(1_214_081, build_key: "11.2.5")
    assert reference.current_name == "Arcane Expulsion"
    assert reference.localized_names == %{"enUS" => "Arcane Expulsion"}
    assert reference.source_system == "local_spell_names_json"
    assert reference.source_import_id == import.source_import.id

    assert Repo.aggregate(SourceImport, :count) == 1
    assert Repo.aggregate(SpellReference, :count) == 2
  end

  test "imports bundled encounter metadata and encounter-spell relationships" do
    path =
      write_json_fixture(%{
        "spells" => [
          %{
            "spell_id" => 1_249_017,
            "name" => "Fearsome Cry",
            "description" => "Interruptible add cast"
          },
          %{
            "spell_id" => 1_262_289,
            "localized_names" => %{"enUS" => "Alndust Upheaval"}
          }
        ],
        "encounters" => [
          %{
            "encounter_id" => 3306,
            "name" => "Chimaerus",
            "zone_id" => 2939,
            "zone_name" => "The Dreamrift",
            "instance_id" => 1314,
            "instance_name" => "Manaforge Omega",
            "difficulty_id" => 16,
            "spells" => [
              %{
                "spell_id" => 1_249_017,
                "relationship_type" => "interruptible"
              }
            ]
          }
        ],
        "encounter_spells" => [
          %{
            "encounter_id" => 3306,
            "spell_id" => 1_262_289,
            "difficulty_id" => 16,
            "relationship_type" => "timeline"
          }
        ]
      })

    assert {:ok, first_import} =
             SourceData.import_reference_metadata_file(path,
               build_key: "11.2.5",
               channel: "ptr",
               source_system: "wowtools_export",
               source_priority: 20
             )

    assert first_import.spells_inserted == 2
    assert first_import.encounters_inserted == 1
    assert first_import.encounter_spells_inserted == 2

    assert {:ok, second_import} =
             SourceData.import_reference_metadata_file(path,
               build_key: "11.2.5",
               channel: "ptr",
               source_system: "wowtools_export",
               source_priority: 20
             )

    assert second_import.spells_updated == 2
    assert second_import.encounters_updated == 1
    assert second_import.encounter_spells_updated == 2

    spell = SourceData.get_spell_reference(1_249_017, build_key: "11.2.5", channel: "ptr")
    assert spell.current_name == "Fearsome Cry"
    assert spell.metadata["description"] == "Interruptible add cast"

    encounter =
      SourceData.get_encounter_reference(3306,
        build_key: "11.2.5",
        channel: "ptr",
        difficulty_id: 16
      )

    assert encounter.current_name == "Chimaerus"
    assert encounter.zone_id == 2939
    assert encounter.instance_id == 1314
    assert encounter.difficulty_id == 16

    assert SourceData.list_encounter_spell_references(
             encounter_id: 3306,
             build_key: "11.2.5",
             channel: "ptr",
             difficulty_id: 16
           )
           |> Enum.map(&{&1.spell_id, &1.relationship_type}) == [
             {1_249_017, "interruptible"},
             {1_262_289, "timeline"}
           ]

    assert Repo.aggregate(SourceImport, :count) == 1
    assert Repo.aggregate(EncounterSpellReference, :count) == 2
  end

  test "reference metadata import requires explicit build scope" do
    path = write_json_fixture(%{"1214081" => "Arcane Expulsion"})

    assert {:error, :build_key_required} = SourceData.import_reference_metadata_file(path)
  end

  defp write_dbm_fixture(body) do
    directory = Path.join(System.tmp_dir!(), "wgn-dbm-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    path = Path.join(directory, "Boss.lua")
    File.write!(path, body)

    on_exit(fn -> File.rm_rf(directory) end)

    path
  end

  defp write_wowanalyzer_fixture(body) do
    directory =
      Path.join(System.tmp_dir!(), "wgn-wowanalyzer-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    path = Path.join(directory, "Boss.ts")
    File.write!(path, body)

    on_exit(fn -> File.rm_rf(directory) end)

    path
  end

  defp make_dbm_root!(name) do
    directory =
      Path.join([
        System.tmp_dir!(),
        "wgn-dbm-roots-#{System.unique_integer([:positive])}",
        name
      ])

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf(Path.dirname(directory)) end)
    directory
  end

  defp make_wowanalyzer_root! do
    directory =
      Path.join(System.tmp_dir!(), "wgn-wowanalyzer-roots-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf(directory) end)
    directory
  end

  defp make_bronze_root! do
    directory =
      Path.join(
        System.tmp_dir!(),
        "wgn-warcraft-logs-bronze-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf(directory) end)
    directory
  end

  defp write_dbm_module!(root, relative_path, body) do
    path = Path.join(root, relative_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, body)
    path
  end

  defp write_wowanalyzer_module!(root, relative_path, body) do
    path = Path.join(root, relative_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, body)
    path
  end

  defp write_json_fixture(payload) do
    directory =
      Path.join(System.tmp_dir!(), "wgn-reference-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    path = Path.join(directory, "reference.json")
    File.write!(path, Jason.encode!(payload))

    on_exit(fn -> File.rm_rf(directory) end)

    path
  end

  defp warcraft_logs_payload(event) do
    %{
      "data" => %{
        "reportData" => %{
          "report" => %{
            "events" => %{
              "data" => [event]
            }
          }
        }
      }
    }
  end

  defp warcraft_logs_table_payload(entries) do
    %{
      "data" => %{
        "reportData" => %{
          "report" => %{
            "table" => %{
              "data" => %{
                "entries" => entries
              }
            }
          }
        }
      }
    }
  end

  defp insert_player_info!(%DimEncounter{} = encounter, player_guid, player_name) do
    %PlayerInfo{}
    |> PlayerInfo.changeset(%{
      encounter_dim_id: encounter.id,
      player_guid: player_guid,
      player_name: player_name,
      detected_role: "dps"
    })
    |> Repo.insert!()
  end

  defp insert_damage_done!(
         %DimEncounter{} = encounter,
         source_guid,
         target_guid,
         spell_id,
         total_amount
       ) do
    %DamageDone{}
    |> DamageDone.changeset(%{
      encounter_dim_id: encounter.id,
      source_guid: source_guid,
      target_guid: target_guid,
      spell_id: spell_id,
      total_amount: total_amount,
      hit_count: 1,
      max_hit: total_amount
    })
    |> Repo.insert!()
  end
end

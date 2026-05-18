defmodule WeGoNext.SourceDataTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias WeGoNext.Repo
  alias WeGoNext.SourceData

  alias WeGoNext.SourceData.{
    DbmMechanicCandidate,
    EncounterReference,
    SourceImport,
    SpellReference
  }

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

    assert {:ok, first_import} = SourceData.import_dbm_file(path)
    assert length(first_import.candidates) == 2

    assert {:ok, second_import} = SourceData.import_dbm_file(path)
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
                 source_priority: 1
             })

    assert SourceData.resolve_encounter_name("3180", build_key: "11.2.0") == "Retail Boss"

    assert SourceData.resolve_encounter_name(3180, build_key: "11.2.5", channel: "ptr") ==
             "PTR Boss"

    reference = SourceData.get_encounter_reference(3180, build_key: "11.2.0")
    assert reference.zone_id == 2912
    assert reference.instance_id == 1307

    assert Repo.aggregate(EncounterReference, :count) == 2
  end

  defp write_dbm_fixture(body) do
    directory = Path.join(System.tmp_dir!(), "wgn-dbm-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    path = Path.join(directory, "Boss.lua")
    File.write!(path, body)

    on_exit(fn -> File.rm_rf(directory) end)

    path
  end
end

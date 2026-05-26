defmodule WeGoNext.SourceData.DBM.ParserTest do
  use ExUnit.Case, async: true

  alias WeGoNext.SourceData.DBM.Parser

  test "extracts DBM module metadata and inferred warning candidates" do
    lua = """
    local mod = DBM:NewMod(2795, "DBM-Raids-Midnight", 2, 1314)

    mod:SetRevision("20260509052555")
    mod:SetCreatureID(256116, 256117)
    mod:SetEncounterID(3306)
    mod:SetZone(2939)

    local specWarnFearsomeCry = mod:NewSpecialWarningInterrupt(1249017, "HasInterrupt", nil, nil, 1, 2)--Add alert
    local specWarnRendingTear = mod:NewSpecialWarningDodgeCount(1272726, nil, nil, DBM_COMMON_L.FRONTAL, 2, 2)
    local specWarnUpheaval = mod:NewSpecialWarningBlizzTarget(1262289, nil, nil, DBM_COMMON_L.GROUPSOAK, 2, 2)

    local function setFallback(self)
      specWarnRendingTear:SetAlert(51, "frontal", 15, 2)
      specWarnUpheaval:SetAlert({149, 431}, "soakincoming", 19, 2)
    end
    """

    assert {:ok, parsed} = Parser.parse_string(lua, source_file: "ChimaerustheUndreamtGod.lua")

    assert parsed.module_id == 2795
    assert parsed.module_addon == "DBM-Raids-Midnight"
    assert parsed.module_map_id == 1314
    assert parsed.module_revision == "20260509052555"
    assert parsed.creature_ids == [256_116, 256_117]
    assert parsed.encounter_id == 3306
    assert parsed.zone_id == 2939

    assert length(parsed.warnings) == 3

    interrupt = Enum.find(parsed.warnings, &(&1.spell_id == 1_249_017))
    assert interrupt.warning_var == "specWarnFearsomeCry"
    assert interrupt.warning_constructor == "NewSpecialWarningInterrupt"
    assert interrupt.role_filter == "HasInterrupt"
    assert interrupt.comment == "Add alert"
    assert interrupt.inferred_mechanic_type == "interrupt"
    assert interrupt.confidence == "high"

    dodge = Enum.find(parsed.warnings, &(&1.spell_id == 1_272_726))
    assert dodge.label_tokens == ["FRONTAL"]
    assert dodge.alert_tokens == ["frontal"]
    assert dodge.inferred_mechanic_type == "avoidable"
    assert dodge.confidence == "high"

    soak = Enum.find(parsed.warnings, &(&1.spell_id == 1_262_289))
    assert soak.label_tokens == ["GROUPSOAK"]
    assert soak.alert_tokens == ["soakincoming"]
    assert soak.inferred_mechanic_type == "soak"
    assert soak.confidence == "medium"
  end

  test "parses focused Lua syntax without treating comments as declarations" do
    lua = """
    local mod = DBM:NewMod(100, 'DBM-Raids-Midnight', nil, 200)
    mod:SetRevision('single-quoted-revision')
    mod:SetCreatureID(111, 222)--inline creature comment
    mod:SetEncounterID(333, 444)
    mod:SetZone()

    --local specWarnCommented = mod:NewSpecialWarningInterrupt(999, "HasInterrupt", nil, nil, 1, 2)
    local specWarnTankCombo = mod:NewSpecialWarningDefensive(555, 'Tank', nil, DBM_COMMON_L.TANKCOMBO, 1, 2)--tank combo

    local function setFallback(self)
      specWarnTankCombo:SetAlert({1, 2}, 'defensive--not a comment', 1)
    end
    """

    assert {:ok, parsed} = Parser.parse_string(lua, source_file: "SingleQuotes.lua")

    assert parsed.module_id == 100
    assert parsed.module_addon == "DBM-Raids-Midnight"
    assert parsed.module_map_id == 200
    assert parsed.module_revision == "single-quoted-revision"
    assert parsed.creature_ids == [111, 222]
    assert parsed.encounter_id == 333
    assert parsed.zone_id == nil

    assert [warning] = parsed.warnings
    assert warning.warning_var == "specWarnTankCombo"
    assert warning.warning_constructor == "NewSpecialWarningDefensive"
    assert warning.spell_id == 555
    assert warning.role_filter == "Tank"
    assert warning.label_tokens == ["TANKCOMBO"]
    assert warning.alert_tokens == ["defensive--not a comment"]
    assert warning.comment == "tank combo"
    assert warning.inferred_mechanic_type == "tank_mechanic"
  end

  test "covers installed Midnight DBM corpus when available" do
    paths =
      WeGoNext.SourceData.default_dbm_midnight_roots()
      |> Enum.filter(&File.dir?/1)
      |> Enum.flat_map(fn root ->
        root
        |> Path.join("**/*.lua")
        |> Path.wildcard()
      end)
      |> Enum.sort()

    if paths == [] do
      assert paths == []
    else
      parsed_modules =
        Enum.map(paths, fn path ->
          assert {:ok, parsed} = Parser.parse_file(path)
          {path, parsed}
        end)

      warning_count =
        parsed_modules
        |> Enum.map(fn {_path, parsed} -> length(parsed.warnings) end)
        |> Enum.sum()

      files_with_warnings =
        Enum.count(parsed_modules, fn {_path, parsed} -> parsed.warnings != [] end)

      assert length(paths) >= 25
      assert files_with_warnings >= 20
      assert warning_count >= 100

      chimaerus =
        Enum.find(parsed_modules, fn {path, _parsed} ->
          String.ends_with?(path, "TheDreamrift/ChimaerustheUndreamtGod.lua")
        end)

      if chimaerus do
        {_path, parsed} = chimaerus

        assert parsed.module_id == 2795
        assert parsed.encounter_id == 3306
        assert parsed.zone_id == 2939
        assert length(parsed.warnings) == 10

        assert parsed.warnings
               |> Enum.find(&(&1.spell_id == 1_249_017))
               |> Map.fetch!(:inferred_mechanic_type) == "interrupt"
      end
    end
  end
end

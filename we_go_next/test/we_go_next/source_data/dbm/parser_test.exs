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
end

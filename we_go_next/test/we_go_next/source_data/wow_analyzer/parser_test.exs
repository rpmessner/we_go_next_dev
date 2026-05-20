defmodule WeGoNext.SourceData.WowAnalyzer.ParserTest do
  use ExUnit.Case, async: true

  alias WeGoNext.SourceData.WowAnalyzer.Parser

  test "extracts boss timeline entries with comments and inferred mechanics" do
    typescript = """
    import { buildBoss } from 'game/raids/builders';

    export const Chimaerus = buildBoss({
      id: 3306,
      name: 'Chimaerus the Undreamt God',
      timeline: {
        abilities: [
          // Alndust Upheaval (group soak)
          { id: 1262289, type: 'cast', bossOnly: true },
          { id: 1262290, type: 'begincast' },
          // summon kick adds
          { id: 1258610, type: 'summon' },
        ],
        debuffs: [
          // Consuming Miasma (dispel debuff)
          { id: 1257087 },
          // Criticality (p2 spreads)
          { id: 1281184, type: 'debuff' },
        ],
      },
    });
    """

    assert {:ok, parsed} = Parser.parse_string(typescript, source_file: "Chimaerus.ts")

    assert parsed.encounter_id == 3306
    assert parsed.encounter_name == "Chimaerus the Undreamt God"
    assert length(parsed.timeline_entries) == 5

    soak = Enum.find(parsed.timeline_entries, &(&1.spell_id == 1_262_289))
    assert soak.timeline_type == "ability"
    assert soak.event_type == "cast"
    assert soak.boss_only == true
    assert soak.comment == "Alndust Upheaval (group soak)"
    assert soak.inferred_mechanic_type == "soak"
    assert soak.confidence == "high"

    shared_comment = Enum.find(parsed.timeline_entries, &(&1.spell_id == 1_262_290))
    assert shared_comment.comment == "Alndust Upheaval (group soak)"
    assert shared_comment.event_type == "begincast"

    interrupt = Enum.find(parsed.timeline_entries, &(&1.spell_id == 1_258_610))
    assert interrupt.event_type == "summon"
    assert interrupt.inferred_mechanic_type == "interrupt"
    assert interrupt.confidence == "medium"

    dispel = Enum.find(parsed.timeline_entries, &(&1.spell_id == 1_257_087))
    assert dispel.timeline_type == "debuff"
    assert dispel.event_type == "debuff"
    assert dispel.inferred_mechanic_type == "healer_mechanic"
    assert dispel.confidence == "high"

    spread = Enum.find(parsed.timeline_entries, &(&1.spell_id == 1_281_184))
    assert spread.inferred_mechanic_type == "spread"
    assert spread.confidence == "medium"
    assert spread.source_line > 0
    assert spread.source_line_text =~ "{ id: 1281184"
    assert spread.raw_entry == %{"id" => 1_281_184, "type" => "debuff"}
  end

  test "extracts double-quoted encounter names" do
    typescript = """
    export const Beloren = buildBoss({
      id: 3182,
      name: "Belo'ren, Child of Al'ar",
      timeline: {
        abilities: [
          // Tank cones
          { id: 1261217, type: 'cast' },
        ],
      },
    });
    """

    assert {:ok, parsed} = Parser.parse_string(typescript)

    assert parsed.encounter_name == "Belo'ren, Child of Al'ar"

    assert [candidate] = parsed.timeline_entries
    assert candidate.inferred_mechanic_type == "tank_mechanic"
    assert candidate.confidence == "high"
  end
end

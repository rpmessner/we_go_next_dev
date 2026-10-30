defmodule WeGoNext.Silver.FeignDeathRealLogTest do
  use ExUnit.Case, async: true

  alias WeGoNext.CombatLogParser
  alias WeGoNext.Silver.Projector

  # Verbatim encounter boundaries and player UNIT_DIED lines from the Sept 6
  # Sszorak pull starting at 11:33:20.939 (dev gold pull 440).
  @fixture Path.expand("../../fixtures/feign_death_real_pull.txt", __DIR__)
  @start "9/6/2026 11:33:20.939-4"
  @madz "Player-1171-0B076010"
  @kahnu "Player-1171-0A34A5C5"

  test "both parser entry points distinguish unconscious deaths from real deaths" do
    {:ok, events} = CombatLogParser.parse_events(@fixture, 0, File.stat!(@fixture).size, @start)

    {:ok, filtered} =
      CombatLogParser.parse_events_filtered(@fixture, 0, File.stat!(@fixture).size, @start, %{
        event_types: ["UNIT_DIED"]
      })

    deaths = Enum.filter(events, &(&1.type == "UNIT_DIED"))
    assert Enum.map(filtered, &Map.delete(&1, :byte_offset)) == deaths

    assert [1, 1, 0] ==
             deaths
             |> Enum.filter(&(&1.target_guid == @madz))
             |> Enum.map(&Map.get(&1, :unconscious_on_death))
  end

  test "feigning does not clear the real death recap and missing flags remain compatible" do
    events = [
      %{
        type: "SPELL_DAMAGE",
        target_guid: @madz,
        source_guid: "Creature-Boss",
        time_into_fight: 1.0,
        spell_id: 123,
        amount: 100
      },
      %{type: "UNIT_DIED", target_guid: @madz, time_into_fight: 2.0, unconscious_on_death: 1},
      %{type: "UNIT_DIED", target_guid: @madz, time_into_fight: 3.0}
    ]

    assert [%{died_at_ms_into_fight: 3000, killing_blow_spell_id: 123}] =
             Projector.project(1, events).death
  end

  test "silver excludes both feigns, keeping the real death and the true first death" do
    {:ok, events} = CombatLogParser.parse_events(@fixture, 0, File.stat!(@fixture).size, @start)
    projection = Projector.project(1, events)

    assert [%{died_at_ms_into_fight: 171_398}] =
             Enum.filter(projection.death, &(&1.target_guid == @madz))

    assert %{target_guid: @kahnu, died_at_ms_into_fight: 155_271} = hd(projection.death)
    assert length(projection.death) == 25
  end
end

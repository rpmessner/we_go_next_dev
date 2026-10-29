defmodule WeGoNext.Analysis.SilverToolsTest do
  @moduledoc """
  Tool seam over persisted real-log slices. Damage comes from the existing July 19
  survival fixture. analysis_interrupts_real_slice.txt preserves a September 6
  Archive-WoWCombatLog-090626_103607.txt trash kick at 11:14:19.713-4 verbatim;
  it is not evidence of a raid-boss kick. Slice times are relative to the parser
  origin passed by each test. Misses and large pagination sets are faithful
  persisted silver fixtures, not claims about real actionable opportunities.
  """
  use WeGoNext.DataCase, async: false

  alias WeGoNext.{CombatLogFile, Repo}
  alias WeGoNext.Encounters.Encounter
  alias WeGoNext.Gold.DimEncounter
  alias WeGoNext.Silver.{DamageTaken, PlayerInfo, Projector}
  alias WeGoNext.Analysis.Tools.DamageTaken, as: DamageTool
  alias WeGoNext.Analysis.Tools.Interrupts
  alias WeGoNext.Silver.InterruptOpportunity

  setup do
    user = Repo.insert!(%WeGoNext.Accounts.User{name: "silver-tools"})
    log = Repo.insert!(%CombatLogFile{user_id: user.id, file_path: "/silver-tools.txt"})

    Repo.insert!(%Encounter{
      combat_log_file_id: log.id,
      name: "Lightblinded Vanguard",
      wow_encounter_id: "3180",
      start_byte: 0,
      start_time: ~U[2026-07-19 15:38:36.049000Z]
    })

    dim =
      Repo.insert!(%DimEncounter{
        source_file_path: log.file_path,
        start_byte: 0,
        name: "Lightblinded Vanguard",
        wow_encounter_id: "3180",
        start_time: ~U[2026-07-19 15:38:36.049000Z]
      })

    path = Path.expand("../../fixtures/survival_actions_real_pull.txt", __DIR__)

    {:ok, events} =
      WeGoNext.CombatLogParser.parse_events(
        path,
        0,
        File.stat!(path).size,
        "7/19/2026 11:38:36.049-4"
      )

    projection = Projector.project(dim.id, events)

    for attrs <- projection.damage_taken,
        do: Repo.insert!(DamageTaken.changeset(%DamageTaken{}, attrs))

    for attrs <- projection.player_info,
        do: Repo.insert!(PlayerInfo.changeset(%PlayerInfo{}, attrs))

    context =
      Repo.insert!(%WeGoNext.Analysis.Session{
        combat_log_file_id: log.id,
        started_at: ~U[2026-10-29 12:00:00.000000Z]
      })

    {:ok, context: context, dim: dim}
  end

  test "interrupts returns real silver kicks with a verification caveat", %{
    context: context,
    dim: dim
  } do
    path = Path.expand("../../fixtures/analysis_interrupts_real_slice.txt", __DIR__)

    {:ok, events} =
      WeGoNext.CombatLogParser.parse_events(
        path,
        0,
        File.stat!(path).size,
        "9/6/2026 11:14:19.000-4"
      )

    projection = Projector.project(dim.id, events)

    for attrs <- projection.interrupt_opportunity do
      Repo.insert!(InterruptOpportunity.changeset(%InterruptOpportunity{}, attrs))
    end

    assert {:ok, result} = Interrupts.run(%{"pulls" => [dim.id]}, context)

    assert [
             %{
               pull_id: id,
               interrupted_spell_id: 1_303_375,
               interrupter_guid: "Player-3678-0E27CA8C",
               interrupting_spell_id: 1766,
               outcome: "kick",
               opportunity_ms_into_fight: 713
             }
           ] = result.data.casts

    assert id == dim.id
    assert result.data.counts == %{kickable_casts: 1, kicks: 1, misses: 0}
    assert result.data.caveat =~ "we-23"
    assert result.data.caveat =~ "log_events"
    assert Interrupts.description() =~ result.data.caveat

    assert [
             %{
               pull_id: ^id,
               source: "silver.interrupt_opportunity",
               timestamp: _,
               ms_into_fight: 713
             }
           ] = result.evidence
  end

  test "damage_taken combines sources without combining players or pulls", %{
    context: context,
    dim: dim
  } do
    Repo.insert!(%DamageTaken{
      encounter_dim_id: dim.id,
      target_guid: "Player-1171-09045C8D",
      source_guid: "Creature-another",
      spell_id: 1_258_661,
      hit_count: 3,
      total_amount: 100
    })

    assert {:ok, result} =
             DamageTool.run(
               %{"pulls" => [dim.id], "spell" => 1_258_661, "player" => "Manaken"},
               context
             )

    assert [%{hit_count: 5, total_amount: 50_295}] = result.data

    assert {:ok, same} =
             DamageTool.run(
               %{"pulls" => [dim.id], "spell" => 1_258_661, "player" => "Player-1171-09045C8D"},
               context
             )

    assert same == result

    assert {:ok, %{data: []}} =
             DamageTool.run(%{"pulls" => [dim.id], "player" => "Other"}, context)
  end

  test "damage amounts retain integer precision beyond 32-bit totals", %{
    context: context,
    dim: dim
  } do
    Repo.insert!(%DamageTaken{
      encounter_dim_id: dim.id,
      target_guid: "Player-big",
      source_guid: "Creature-big",
      spell_id: 1,
      hit_count: 1,
      total_amount: 3_000_000_000
    })

    assert {:ok, result} =
             DamageTool.run(%{"pulls" => [dim.id], "player" => "Player-big"}, context)

    assert [%{total_amount: 3_000_000_000, player_name: nil}] = result.data

    assert Jason.decode!(Jason.encode!(result))["data"] |> hd() |> Map.fetch!("total_amount") ==
             3_000_000_000
  end

  test "Tools reject unknown and out-of-session pull ids", %{context: context, dim: dim} do
    foreign =
      Repo.insert!(%DimEncounter{
        source_file_path: "/foreign.txt",
        start_byte: 0,
        wow_encounter_id: "3180",
        name: "Foreign"
      })

    for tool <- [DamageTool, Interrupts], id <- [foreign.id, dim.id + 1_000_000] do
      assert {:error, reason} = tool.run(%{"pulls" => [dim.id, id]}, context)
      assert reason =~ "session log"
    end
  end

  test "misses are presented unchanged with an explicit caveat even on empty pages", %{
    context: context,
    dim: dim
  } do
    # Faithful persisted observation: today's silver labels completed casts as misses.
    Repo.insert!(%InterruptOpportunity{
      encounter_dim_id: dim.id,
      target_npc_guid: "Creature-miss",
      interrupted_spell_id: 1_258_681,
      opportunity_ms_into_fight: 2000,
      success: false
    })

    assert {:ok, result} = Interrupts.run(%{"pulls" => [dim.id]}, context)
    assert [%{outcome: "miss", success: false, interrupter_guid: nil}] = result.data.casts
    assert result.data.counts == %{kickable_casts: 1, kicks: 0, misses: 1}
    assert [%{timestamp: ~U[2026-07-19 15:38:38.049000Z], ms_into_fight: 2000}] = result.evidence
    Repo.delete_all(InterruptOpportunity)
    assert {:ok, empty} = Interrupts.run(%{"pulls" => [dim.id]}, context)
    assert empty.data.casts == []
    assert empty.data.counts == %{kickable_casts: 0, kicks: 0, misses: 0}
    assert empty.data.caveat == result.data.caveat
  end

  test "agent args require positive gold pull ids and typed optional filters", %{
    context: context,
    dim: dim
  } do
    args = %{"session_id" => context.id, "pulls" => [dim.id]}

    for tool <- [DamageTool, Interrupts] do
      assert :ok = WeGoNext.Analysis.Arguments.validate(args, tool.input_schema())

      for bad <- [
            Map.delete(args, "pulls"),
            %{args | "pulls" => []},
            %{args | "pulls" => [0]},
            %{args | "pulls" => ["1"]},
            Map.put(args, "extra", true)
          ] do
        assert {:error, _} = WeGoNext.Analysis.Arguments.validate(bad, tool.input_schema())
      end
    end

    assert :ok =
             WeGoNext.Analysis.Arguments.validate(
               Map.merge(args, %{"spell" => 0, "player" => "Manaken"}),
               DamageTool.input_schema()
             )

    for filters <- [
          %{"spell" => "1258661"},
          %{"spell" => -1},
          %{"player" => ""},
          %{"player" => 1}
        ] do
      assert {:error, _} =
               WeGoNext.Analysis.Arguments.validate(
                 Map.merge(args, filters),
                 DamageTool.input_schema()
               )
    end

    assert {:error, _} =
             WeGoNext.Analysis.Arguments.validate(
               Map.put(args, "spell", 1),
               Interrupts.input_schema()
             )
  end

  test "Tools paginate without dropping or duplicating silver rows", %{context: context, dim: dim} do
    for n <- 1..80 do
      Repo.insert!(%DamageTaken{
        encounter_dim_id: dim.id,
        target_guid: "Player-pagination",
        source_guid: "Creature-pagination",
        spell_id: n,
        hit_count: 1,
        total_amount: n
      })

      Repo.insert!(%InterruptOpportunity{
        encounter_dim_id: dim.id,
        target_npc_guid: "Creature-pagination",
        interrupted_spell_id: n,
        opportunity_ms_into_fight: n,
        success: false
      })
    end

    for tool <- [DamageTool, Interrupts] do
      args = %{"pulls" => [dim.id]}
      assert {:ok, first} = tool.run(args, context)
      assert first.truncated
      rows = drain(tool, args, context, first)
      assert length(rows) == if(tool == DamageTool, do: 83, else: 80)
      assert Enum.uniq(rows) == rows

      assert {:error, _} =
               tool.run(%{"pulls" => [dim.id, dim.id], "cursor" => first.next_cursor}, context)
    end
  end

  defp drain(tool, args, context, result) do
    assert byte_size(Jason.encode!(result)) <= 8192
    rows = if tool == DamageTool, do: result.data, else: result.data.casts
    if tool == Interrupts, do: assert(result.data.caveat =~ "log_events")

    if result.truncated do
      assert {:ok, next} = tool.run(Map.put(args, "cursor", result.next_cursor), context)
      rows ++ drain(tool, args, context, next)
    else
      assert result.next_cursor == nil
      rows
    end
  end

  test "damage_taken returns silver player by spell totals with pull evidence", %{
    context: context,
    dim: dim
  } do
    assert {:ok, result} = DamageTool.run(%{"pulls" => [dim.id], "spell" => 1_258_661}, context)

    assert [
             %{
               pull_id: id,
               player_guid: "Player-1171-09045C8D",
               player_name: "Manaken",
               spell_id: 1_258_661,
               hit_count: 2,
               total_amount: 50_195
             }
           ] = result.data

    assert id == dim.id

    assert [
             %{
               pull_id: ^id,
               source: "silver.damage_taken",
               timestamp: ~U[2026-07-19 15:38:36.049000Z]
             }
           ] = result.evidence

    refute result.truncated
  end
end

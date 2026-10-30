defmodule WeGoNext.Analysis.DamageDoneTest do
  use WeGoNext.DataCase, async: false

  alias WeGoNext.{CombatLogFile, CombatLogParser, Repo}
  alias WeGoNext.Analysis.Tools.DamageDone, as: Tool
  alias WeGoNext.Encounters.Encounter
  alias WeGoNext.Gold.DimEncounter
  alias WeGoNext.Silver.{DamageDone, Projector}

  setup do
    user = Repo.insert!(%WeGoNext.Accounts.User{name: "damage-done"})
    log = Repo.insert!(%CombatLogFile{user_id: user.id, file_path: "/damage-done.txt"})

    session =
      Repo.insert!(%WeGoNext.Analysis.Session{
        combat_log_file_id: log.id,
        started_at: DateTime.utc_now()
      })

    {:ok, session: session, log: log}
  end

  test "Sept 6 damage separates boss, priority and other against independent CSV sums", %{
    session: session,
    log: log
  } do
    path = Path.expand("../../fixtures/analysis_damage_done_sept6.txt", __DIR__)

    expected =
      Path.expand("../../fixtures/analysis_damage_done_sept6_expected.json", __DIR__)
      |> File.read!()
      |> Jason.decode!()

    {:ok, events} =
      CombatLogParser.parse_events(path, 0, File.stat!(path).size, "9/6/2026 11:03:00.375-4")

    for {boss, index} <- [{"3379", 0}, {"3420", 1}, {"3421", 2}] do
      dim = insert_pull(log, boss, index)
      # The fixture preserves raw direct-player hits, each selected once per player/NPC
      # within one real pull. The JSON oracle was summed independently with Python csv,
      # amount field 28 (swing) / 31 (spell), not the NIF or silver projector.
      selected =
        Enum.filter(events, fn event ->
          case String.split(event.target_guid || "", "-") do
            ["Creature", _, _, _, _, npc, _] -> npc in target_ids(boss)
            _ -> false
          end
        end)

      projection = Projector.project(dim.id, selected)

      for attrs <- projection.damage_done,
          do: Repo.insert!(DamageDone.changeset(%DamageDone{}, attrs))

      assert {:ok, first} = Tool.run(%{"pulls" => [dim.id]}, session)
      rows = drain(%{"pulls" => [dim.id]}, session, first)
      assert length(rows) == map_size(expected[boss])

      for row <- rows do
        totals = expected[boss][row.player_guid]
        assert row.boss_damage == totals["boss"]
        assert row.priority_damage == totals["priority"]
        assert row.other_damage == totals["other"]
        assert row.total_damage == totals["boss"] + totals["priority"] + totals["other"]
        assert_in_delta row.boss_share + row.priority_share + row.other_share, 1.0, 0.00001
      end
    end
  end

  test "player and target class select players without changing share denominators", %{
    session: session,
    log: log
  } do
    dim = insert_pull(log, "3421", 0)

    Repo.insert!(%WeGoNext.Silver.PlayerInfo{
      encounter_dim_id: dim.id,
      player_guid: "Player-owner",
      player_name: "Owner"
    })

    for {npc, amount} <- [{257_361, 3_000_000_000}, {264_023, 600}, {999, 400}] do
      Repo.insert!(%DamageDone{
        encounter_dim_id: dim.id,
        source_guid: "Player-owner",
        target_guid: "Creature-0-1-2-3-#{npc}-0001",
        spell_id: 123,
        total_amount: amount
      })
    end

    args = %{"pulls" => [dim.id], "target_class" => "priority", "player" => "Owner"}
    assert {:ok, page} = Tool.run(args, session)
    assert [row] = page.data
    assert row.total_damage == 3_000_001_000
    assert row.priority_damage == 600
    assert_in_delta row.priority_share, 600 / 3_000_001_000, 0.000000001
    assert {:ok, same} = Tool.run(%{args | "player" => "Player-owner"}, session)
    assert same == page
    assert [evidence] = page.evidence
    assert evidence.pull_id == dim.id
    assert evidence.source == "silver.damage_done"
    assert Enum.map(evidence.samples, & &1.target_class) == [:boss, :priority, :other]
    assert Enum.all?(evidence.samples, &(&1.spell_id == 123))
    assert {:ok, %{data: []}} = Tool.run(%{args | "player" => "Missing"}, session)
  end

  test "unknown catalogs and zero damage never claim clean boss or priority coverage", %{
    session: session,
    log: log
  } do
    dim = insert_pull(log, "9999", 0)

    for {guid, amount} <- [{"Player-unknown", 10}, {"Player-zero", 0}] do
      Repo.insert!(%DamageDone{
        encounter_dim_id: dim.id,
        source_guid: guid,
        target_guid: "Creature-0-1-2-3-257347-0001",
        spell_id: 0,
        total_amount: amount
      })
    end

    assert {:ok, page} = Tool.run(%{"pulls" => [dim.id]}, session)
    assert [unknown, zero] = page.data
    assert unknown.other_damage == 10
    assert unknown.boss_damage == 0
    refute unknown.targets_verified
    assert unknown.player_name == nil
    assert zero.total_damage == 0
    assert zero.other_share == 0.0
    assert hd(page.evidence).target_catalog.notes =~ "not padding"

    assert {:ok, %{data: []}} =
             Tool.run(%{"pulls" => [dim.id], "target_class" => "boss"}, session)
  end

  test "pagination is bounded, lossless and bound to filters and session", %{
    session: session,
    log: log
  } do
    dim = insert_pull(log, "3421", 0)

    for n <- 1..80 do
      Repo.insert!(%DamageDone{
        encounter_dim_id: dim.id,
        source_guid: "Player-#{n}",
        target_guid: "Creature-0-1-2-3-257361-0001",
        spell_id: n,
        total_amount: n
      })
    end

    args = %{"pulls" => [dim.id]}
    assert {:ok, first} = Tool.run(args, session)
    assert first.truncated
    rows = drain(args, session, first)
    assert length(rows) == 80
    assert Enum.uniq(rows) == rows
    assert Enum.sum_by(rows, & &1.total_damage) == 3240

    assert {:error, _} =
             Tool.run(
               Map.merge(args, %{"cursor" => first.next_cursor, "target_class" => "boss"}),
               session
             )

    assert {:error, _} =
             Tool.run(Map.put(args, "cursor", first.next_cursor), %{
               session
               | id: Ecto.UUID.generate()
             })
  end

  test "cross-log pulls are rejected and schema validates target classes", %{
    session: session,
    log: log
  } do
    dim = insert_pull(log, "3420", 0)

    foreign =
      Repo.insert!(%DimEncounter{
        source_file_path: "/foreign.txt",
        start_byte: 0,
        wow_encounter_id: "3420",
        name: "Sszorak"
      })

    assert {:error, reason} = Tool.run(%{"pulls" => [dim.id, foreign.id]}, session)
    assert reason =~ "session log"
    assert {:error, _} = Tool.run(%{"pulls" => [dim.id + 100_000]}, session)
    args = %{"session_id" => session.id, "pulls" => [dim.id]}
    assert :ok = WeGoNext.Analysis.Arguments.validate(args, Tool.input_schema())

    for bad <- [
          %{"target_class" => "padding"},
          %{"player" => ""},
          %{"pulls" => []},
          %{"pulls" => [0]}
        ] do
      assert {:error, _} =
               WeGoNext.Analysis.Arguments.validate(Map.merge(args, bad), Tool.input_schema())
    end
  end

  test "target catalogs remain encounter scoped and distinguish unverified coverage" do
    alias WeGoNext.GameData.Raids.{DamageTargets, MidnightLairs, VenomousAbyss}

    for raid <- [VenomousAbyss, MidnightLairs] do
      assert Enum.sort(Map.keys(raid.damage_targets())) ==
               Enum.sort(Enum.map(raid.bosses(), & &1.encounter_id))

      for {encounter, targets} <- raid.damage_targets() do
        assert targets.boss != []
        assert Enum.all?(targets.boss ++ targets.priority, &is_integer/1)
        assert MapSet.disjoint?(MapSet.new(targets.boss), MapSet.new(targets.priority))
        assert targets.verified == encounter in [3379, 3420, 3421]
        assert targets.notes =~ ".lua:"
      end
    end

    targets = DamageTargets.for_encounter("3421")
    assert DamageTargets.classify("Creature-0-1-2-3-257368-0001", targets) == :boss
    assert DamageTargets.classify("Vehicle-0-1-2-3-264023-0001", targets) == :priority
    assert DamageTargets.classify("Creature-0-1-2-3-252959-0001", targets) == :other
    assert DamageTargets.classify("Creature-0-1-2-3-invalid-0001", targets) == :other
    assert DamageTargets.classify("Player-1", targets) == :other
    refute DamageTargets.for_encounter("3492").verified
  end

  defp target_ids("3379"), do: ["252959", "253032"]
  defp target_ids("3420"), do: ["257347", "261479", "261488", "261484"]
  defp target_ids("3421"), do: ["257361", "257368", "264023"]

  defp insert_pull(log, boss, index) do
    start =
      case boss do
        "3379" -> ~U[2026-09-06 15:03:00.375000Z]
        "3420" -> ~U[2026-09-06 15:22:15.759000Z]
        "3421" -> ~U[2026-09-06 16:32:15.482000Z]
        _ -> DateTime.add(~U[2026-09-06 15:03:00.375000Z], index, :second)
      end

    Repo.insert!(%Encounter{
      combat_log_file_id: log.id,
      name: boss,
      wow_encounter_id: boss,
      start_byte: index,
      start_time: start
    })

    Repo.insert!(%DimEncounter{
      source_file_path: log.file_path,
      name: boss,
      wow_encounter_id: boss,
      start_byte: index,
      start_time: start
    })
  end

  defp drain(args, session, page) do
    assert byte_size(Jason.encode!(page)) <= 8192
    assert length(page.evidence) == length(page.data)

    if page.truncated do
      assert {:ok, next} = Tool.run(Map.put(args, "cursor", page.next_cursor), session)
      page.data ++ drain(args, session, next)
    else
      page.data
    end
  end
end

defmodule WeGoNext.Analysis.LogEventsTest do
  use WeGoNext.DataCase, async: false

  alias WeGoNext.Analysis.Tools.LogEvents
  alias WeGoNext.{CombatLogFile, Repo}
  alias WeGoNext.Encounters.Encounter
  alias WeGoNext.Gold.DimEncounter

  setup do
    fixture = Path.expand("../../fixtures/survival_actions_real_pull.txt", __DIR__)
    path = Path.join(System.tmp_dir!(), "log-events-#{System.unique_integer([:positive])}.txt")
    slice = File.read!(fixture)
    # Identical matching events outside the gold range must never leak in.
    File.write!(path, slice <> slice <> slice)
    start_byte = byte_size(slice)
    on_exit(fn -> File.rm(path) end)
    user = Repo.insert!(%WeGoNext.Accounts.User{name: "log-events"})
    log = Repo.insert!(%CombatLogFile{user_id: user.id, file_path: path})
    start = ~U[2026-07-19 15:38:36.049000Z]

    Repo.insert!(%Encounter{
      combat_log_file_id: log.id,
      name: "Lightblinded Vanguard",
      wow_encounter_id: "3180",
      start_byte: start_byte,
      start_time: start
    })

    dim =
      Repo.insert!(%DimEncounter{
        source_file_path: path,
        name: "Lightblinded Vanguard",
        wow_encounter_id: "3180",
        start_byte: start_byte,
        end_byte: 2 * start_byte,
        start_time: start,
        fight_time_ms: 300_000
      })

    context =
      Repo.insert!(%WeGoNext.Analysis.Session{combat_log_file_id: log.id, started_at: start})

    {:ok, context: context, dim: dim, log: log, path: path}
  end

  test "agent schema requires one pull and typed selective filters", %{context: context, dim: dim} do
    args = %{
      "session_id" => context.id,
      "pull" => dim.id,
      "filters" => %{"spell_ids" => [6262, 0]}
    }

    assert :ok = WeGoNext.Analysis.Arguments.validate(args, LogEvents.input_schema())

    for bad <- [
          Map.delete(args, "pull"),
          Map.delete(args, "filters"),
          Map.put(args, "pull", [dim.id]),
          Map.put(args, "pull", 0),
          Map.put(args, "unknown", true)
        ] do
      assert {:error, _} = WeGoNext.Analysis.Arguments.validate(bad, LogEvents.input_schema())
    end

    for filters <- [
          %{"event_types" => []},
          %{"source_guids" => [1]},
          %{"target_guids" => [""]},
          %{"spell_ids" => ["6262"]},
          %{"spell_ids" => [-1]},
          %{"time_min_ms" => -1},
          %{"time_max_ms" => 0.5},
          %{"unknown" => true}
        ] do
      assert {:error, _} =
               WeGoNext.Analysis.Arguments.validate(
                 %{args | "filters" => filters},
                 LogEvents.input_schema()
               )
    end
  end

  test "log_events is an enabled Tool" do
    assert WeGoNext.Analysis.Registry.fetch("log_events") == LogEvents
  end

  test "filter lists OR within and AND across, with inclusive millisecond bounds", %{
    context: context,
    dim: dim
  } do
    filters = %{
      "event_types" => ["SPELL_CAST_SUCCESS", "SPELL_HEAL"],
      "source_guids" => ["Player-1171-09045C8D", "Player-absent"],
      "target_guids" => ["Player-1171-09045C8D"],
      "spell_ids" => [6262, 22_812],
      "time_min_ms" => 93_034,
      "time_max_ms" => 93_034
    }

    assert {:ok, result} = LogEvents.run(%{"pull" => dim.id, "filters" => filters}, context)
    assert [%{spell_id: 6262, type: "SPELL_HEAL", time_into_fight: 93.034}] = result.data

    assert {:ok, %{data: []}} =
             LogEvents.run(
               %{
                 "pull" => dim.id,
                 "filters" => %{filters | "time_min_ms" => 93_035, "time_max_ms" => 93_035}
               },
               context
             )
  end

  test "time-only windows are allowed but whole-pull requests are rejected", %{
    context: context,
    dim: dim
  } do
    assert {:ok, result} =
             LogEvents.run(
               %{
                 "pull" => dim.id,
                 "filters" => %{"time_min_ms" => 11_569, "time_max_ms" => 11_569}
               },
               context
             )

    assert [%{spell_id: 22_812, source_name: "Grdengnome-WyrmrestAccord-US"}] = result.data

    for filters <- [
          %{},
          %{"event_types" => []},
          %{"time_min_ms" => 0},
          %{"time_min_ms" => 0, "time_max_ms" => 300_000}
        ] do
      assert {:error, reason} = LogEvents.run(%{"pull" => dim.id, "filters" => filters}, context)
      assert reason =~ "Narrow"
    end

    assert {:error, reason} =
             LogEvents.run(
               %{"pull" => dim.id, "filters" => %{"time_min_ms" => 100, "time_max_ms" => 99}},
               context
             )

    assert reason =~ "time_max_ms"
  end

  test "missing and truncated files produce path-specific errors", %{
    context: context,
    path: path,
    dim: dim
  } do
    args = %{"pull" => dim.id, "filters" => %{"spell_ids" => [6262]}}
    File.rename!(path, path <> ".moved")
    on_exit(fn -> File.rm(path <> ".moved") end)
    assert {:error, reason} = LogEvents.run(args, context)
    assert reason =~ path
    File.rename!(path <> ".moved", path)
    Repo.update!(Ecto.Changeset.change(dim, end_byte: File.stat!(path).size + 1))
    assert {:error, reason} = LogEvents.run(args, context)
    assert reason =~ path
    assert reason =~ "truncated"
  end

  test "rejects foreign pulls and incomplete gold byte ranges", %{context: context, dim: dim} do
    foreign =
      Repo.insert!(%DimEncounter{
        source_file_path: "/other-session-log.txt",
        start_byte: 0,
        name: "Foreign",
        wow_encounter_id: "3180"
      })

    for id <- [foreign.id, dim.id + 1_000_000] do
      assert {:error, reason} =
               LogEvents.run(%{"pull" => id, "filters" => %{"spell_ids" => [6262]}}, context)

      assert reason =~ "session log"
    end

    Repo.update!(Ecto.Changeset.change(dim, end_byte: nil))

    assert {:error, reason} =
             LogEvents.run(%{"pull" => dim.id, "filters" => %{"spell_ids" => [6262]}}, context)

    assert reason =~ "byte range"
  end

  test "pages stay capped and preserve every event with filter-bound cursors", %{
    context: context,
    dim: dim
  } do
    args = %{"pull" => dim.id, "filters" => %{"target_guids" => ["Player-1171-09045C8D"]}}
    assert {:ok, first} = LogEvents.run(args, context)
    assert first.truncated
    rows = drain(args, context, first)
    assert length(rows) == 20
    offsets = Enum.map(rows, & &1.byte_offset)
    assert Enum.uniq(offsets) == offsets
    assert offsets == Enum.sort(offsets)

    assert {:error, _} =
             LogEvents.run(
               %{args | "filters" => %{"spell_ids" => [6262]}}
               |> Map.put("cursor", first.next_cursor),
               context
             )
  end

  defp drain(args, context, page) do
    assert byte_size(Jason.encode!(page)) <= 8192
    assert length(page.evidence) == length(page.data)

    if page.truncated do
      assert {:ok, next} = LogEvents.run(Map.put(args, "cursor", page.next_cursor), context)
      page.data ++ drain(args, context, next)
    else
      assert page.next_cursor == nil
      page.data
    end
  end

  test "raw events retain names and absolute byte evidence within the pull", %{
    context: context,
    dim: dim,
    path: path
  } do
    args = %{"pull" => dim.id, "filters" => %{"spell_ids" => [1_258_661]}}
    assert {:ok, result} = LogEvents.run(args, context)
    assert length(result.data) == 2
    assert Enum.all?(result.data, &(&1.spell_id == 1_258_661))
    assert Enum.all?(result.data, &(&1.target_name == "Manaken-WyrmrestAccord-US"))

    for {event, evidence} <- Enum.zip(result.data, result.evidence) do
      assert evidence.pull_id == dim.id
      assert evidence.timestamp == event.timestamp
      assert evidence.byte_offset == event.byte_offset
      assert event.byte_offset >= dim.start_byte and event.byte_offset < dim.end_byte
      {:ok, file} = File.open(path, [:read, :binary])
      assert {:ok, line} = :file.pread(file, event.byte_offset, 100)
      File.close(file)
      assert String.starts_with?(line, event.timestamp <> "  ")
    end
  end
end

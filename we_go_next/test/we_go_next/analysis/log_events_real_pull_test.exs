defmodule WeGoNext.Analysis.LogEventsRealPullTest do
  @moduledoc "Opt-in timing/cap check: ANALYSIS_REAL_LOG is the Sept 6 reference log."
  use WeGoNext.DataCase, async: false

  alias WeGoNext.Analysis.Tools.LogEvents
  alias WeGoNext.{CombatLogFile, CombatLogParser, Repo}
  alias WeGoNext.Encounters.Encounter
  alias WeGoNext.Gold.DimEncounter

  @tag skip: is_nil(System.get_env("ANALYSIS_REAL_LOG"))
  @tag timeout: 120_000
  test "filtered Twin Fangs Tool call takes at most half a second and stays capped" do
    path = System.fetch_env!("ANALYSIS_REAL_LOG")
    {:ok, boundaries, _} = CombatLogParser.scan_boundaries(path, 0)

    pull =
      boundaries
      |> Enum.filter(&Map.has_key?(&1, :wow_encounter_id))
      |> Enum.max_by(&(&1.end_byte - &1.start_byte))

    assert pull.name == "The Twin Fangs"
    assert pull.start_timestamp == "9/6/2026 13:55:51.477-4"
    user = Repo.insert!(%WeGoNext.Accounts.User{name: "log-events-real"})
    log = Repo.insert!(%CombatLogFile{user_id: user.id, file_path: path})
    start = ~U[2026-09-06 17:55:51.477000Z]

    Repo.insert!(%Encounter{
      combat_log_file_id: log.id,
      name: pull.name,
      wow_encounter_id: to_string(pull.wow_encounter_id),
      start_byte: pull.start_byte,
      start_time: start
    })

    dim =
      Repo.insert!(%DimEncounter{
        source_file_path: path,
        name: pull.name,
        wow_encounter_id: to_string(pull.wow_encounter_id),
        start_byte: pull.start_byte,
        end_byte: pull.end_byte,
        start_time: start
      })

    context =
      Repo.insert!(%WeGoNext.Analysis.Session{combat_log_file_id: log.id, started_at: start})

    args = %{
      "pull" => dim.id,
      "filters" => %{"event_types" => ["SPELL_CAST_SUCCESS"], "spell_ids" => [6262]}
    }

    {us, response} = :timer.tc(fn -> LogEvents.run(args, context) end)
    assert {:ok, result} = response
    assert result.data != []
    assert us <= 500_000
    {rows, pages, max_bytes} = drain(args, context, result)
    assert Enum.all?(rows, &(&1.spell_id == 6262 and &1.type == "SPELL_CAST_SUCCESS"))

    assert Enum.all?(
             rows,
             &(&1.byte_offset >= pull.start_byte and &1.byte_offset < pull.end_byte)
           )

    assert Enum.uniq_by(rows, & &1.byte_offset) == rows
    broad_args = %{"pull" => dim.id, "filters" => %{"event_types" => ["SPELL_DAMAGE"]}}
    assert {:ok, broad} = LogEvents.run(broad_args, context)
    assert broad.truncated
    assert byte_size(Jason.encode!(broad)) <= 8192

    assert {:ok, continuation} =
             LogEvents.run(Map.put(broad_args, "cursor", broad.next_cursor), context)

    assert byte_size(Jason.encode!(continuation)) <= 8192
    assert List.last(broad.data).byte_offset < hd(continuation.data).byte_offset

    IO.puts(
      "log_events Twin Fangs bytes=#{pull.end_byte - pull.start_byte} filtered_call_ms=#{us / 1000} rows=#{length(rows)} pages=#{pages} max_bytes=#{max_bytes}"
    )
  end

  defp drain(args, context, page) do
    bytes = byte_size(Jason.encode!(page))
    assert bytes <= 8192
    assert length(page.data) == length(page.evidence)

    if page.truncated do
      assert {:ok, next} = LogEvents.run(Map.put(args, "cursor", page.next_cursor), context)
      {rest, pages, max_bytes} = drain(args, context, next)
      {page.data ++ rest, pages + 1, max(bytes, max_bytes)}
    else
      assert page.next_cursor == nil
      {page.data, 1, bytes}
    end
  end
end

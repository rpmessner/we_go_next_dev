defmodule WeGoNext.Analysis.SilverToolsRealPullTest do
  @moduledoc "Opt-in cap check: ANALYSIS_REAL_LOG is the Sept 6 reference combat log."
  use WeGoNext.DataCase, async: false

  alias WeGoNext.Analysis.Tools.{DamageTaken, Interrupts}
  alias WeGoNext.{CombatLogFile, CombatLogParser, Repo}
  alias WeGoNext.Encounters.Encounter
  alias WeGoNext.Gold.DimEncounter
  alias WeGoNext.Silver

  @tag skip: is_nil(System.get_env("ANALYSIS_REAL_LOG"))
  @tag timeout: 120_000
  test "both silver Tools stay capped and cursors cover the largest real pull" do
    path = System.fetch_env!("ANALYSIS_REAL_LOG")
    {:ok, boundaries, _} = CombatLogParser.scan_boundaries(path, 0)

    pull =
      boundaries
      |> Enum.filter(&Map.has_key?(&1, :wow_encounter_id))
      |> Enum.max_by(&(&1.end_byte - &1.start_byte))

    {:ok, events} =
      CombatLogParser.parse_events(path, pull.start_byte, pull.end_byte, pull.start_timestamp)

    assert length(events) == 368_632
    assert pull.name == "The Twin Fangs"
    assert pull.start_timestamp == "9/6/2026 13:55:51.477-4"

    user = Repo.insert!(%WeGoNext.Accounts.User{name: "largest-real-pull"})
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
        start_time: start
      })

    context =
      Repo.insert!(%WeGoNext.Analysis.Session{combat_log_file_id: log.id, started_at: start})

    projection = Silver.Projector.project(dim.id, events)

    for {schema, key} <- [
          {Silver.DamageTaken, :damage_taken},
          {Silver.InterruptOpportunity, :interrupt_opportunity},
          {Silver.PlayerInfo, :player_info}
        ] do
      for attrs <- Map.fetch!(projection, key),
          do: Repo.insert!(schema.changeset(struct(schema), attrs))
    end

    args = %{"pulls" => [dim.id]}
    {:ok, first} = DamageTaken.run(args, context)
    assert first.truncated
    {damage, damage_pages, damage_max} = drain(DamageTaken, args, context, first)
    assert Enum.uniq(damage) == damage

    assert Enum.sum(Enum.map(damage, & &1.hit_count)) ==
             Enum.sum(Enum.map(projection.damage_taken, & &1.hit_count))

    assert Enum.sum(Enum.map(damage, & &1.total_amount)) ==
             Enum.sum(Enum.map(projection.damage_taken, & &1.total_amount))

    {:ok, first} = Interrupts.run(args, context)
    {interrupts, interrupt_pages, interrupt_max} = drain(Interrupts, args, context, first)
    assert length(interrupts) == length(projection.interrupt_opportunity)

    IO.puts(
      "Largest real pull #{pull.name}: bytes=#{pull.end_byte - pull.start_byte}, events=#{length(events)}, damage_rows=#{length(damage)}, damage_pages=#{damage_pages}, damage_max_bytes=#{damage_max}, interrupt_rows=#{length(interrupts)}, interrupt_pages=#{interrupt_pages}, interrupt_max_bytes=#{interrupt_max}"
    )
  end

  defp drain(tool, args, context, page) do
    bytes = byte_size(Jason.encode!(page))
    assert bytes <= 8192
    rows = if tool == DamageTaken, do: page.data, else: page.data.casts
    assert length(page.evidence) == length(rows)
    if tool == Interrupts, do: assert(page.data.caveat =~ "log_events")

    if page.truncated do
      assert is_binary(page.next_cursor)
      assert {:ok, next} = tool.run(Map.put(args, "cursor", page.next_cursor), context)
      {rest, pages, max_bytes} = drain(tool, args, context, next)
      {rows ++ rest, pages + 1, max(bytes, max_bytes)}
    else
      assert page.next_cursor == nil
      {rows, 1, bytes}
    end
  end
end

defmodule WeGoNext.Analysis.DeathsSurvivalTest do
  @moduledoc """
  Survival Tool evidence from Felthuzad's real Sept 6 Sszorak pull 5 death.
  The checked-in slice preserves verbatim encounter boundaries, player combatant
  info, survival casts/auras, and damage involving that player in the death window
  from Archive-WoWCombatLog-090626_103607.txt, bytes 163524737..232589586.
  It retains earlier Healthstone/Unending Resolve uses to test window exclusion.
  """
  use WeGoNext.DataCase, async: false

  alias WeGoNext.Analysis.Result
  alias WeGoNext.Analysis.Tools.Deaths
  alias WeGoNext.{CombatLogFile, CombatLogParser, Repo, Silver}
  alias WeGoNext.Gold.DimEncounter

  @origin "9/6/2026 11:33:20.939-4"
  @start ~U[2026-09-06 15:33:20.939000Z]

  test "deaths exposes a recorded defensive in the death window with pull and time evidence" do
    path = Path.expand("../../fixtures/analysis_death_survival_real_slice.txt", __DIR__)
    {dim, context} = persist_pull(path, 0, File.stat!(path).size)
    args = %{"pulls" => [dim.id]}
    pages = pages(args, context)
    rows = Enum.flat_map(pages, & &1.data)
    assert [first | rest] = rows
    assert first.player_name == "Felthuzad"
    assert first.died_at_ms_into_fight == 196_359
    assert first.window_ms == 10_000

    assert first.survival == %{
             observed: [
               %{name: "Dark Pact", state: :used_in_window, last_used_at_ms_into_fight: 190_032}
             ],
             externals_received: []
           }

    assert Enum.all?(rest, &(not Map.has_key?(&1, :survival)))
    assert Enum.flat_map(rows, & &1.damage_recap) |> length() == first.recap_count
    assert first.recap_count == 16

    assert Enum.all?(Enum.flat_map(pages, & &1.evidence), fn evidence ->
             evidence.pull_id == dim.id and evidence.source == "silver.death" and
               evidence.timestamp == @start and evidence.ms_into_fight == 196_359
           end)

    assert Deaths.description() =~ "not proof"
    assert Deaths.description() =~ "not repeated"
  end

  test "an observed defensive remains visible without a damage recap" do
    path = Path.expand("../../fixtures/analysis_death_survival_real_slice.txt", __DIR__)
    {dim, context} = persist_pull(path, 0, File.stat!(path).size)
    death = Repo.get_by!(Silver.Death, encounter_dim_id: dim.id)
    Repo.update!(Ecto.Changeset.change(death, damage_recap: []))
    assert {:ok, page} = Deaths.run(%{"pulls" => [dim.id]}, context)

    assert [
             %{
               recap_index: nil,
               recap_count: 0,
               survival: %{observed: [%{name: "Dark Pact", last_used_at_ms_into_fight: 190_032}]}
             }
           ] = page.data

    assert byte_size(Jason.encode!(page)) <= Result.cap()
  end

  @tag skip: is_nil(System.get_env("ANALYSIS_REAL_LOG"))
  @tag timeout: 120_000
  test "compact survival does not add pages on Sept 6 Sszorak pull 5" do
    path = System.fetch_env!("ANALYSIS_REAL_LOG")
    {:ok, boundaries, _} = CombatLogParser.scan_boundaries(path, 0)
    pull = boundaries |> Enum.filter(&(&1[:name] == "Sszorak")) |> Enum.at(4)
    assert pull.start_timestamp == @origin
    {dim, context} = persist_pull(path, pull.start_byte, pull.end_byte)
    args = %{"pulls" => [dim.id]}
    actual = pages(args, context)
    rows = Enum.flat_map(actual, & &1.data)
    assert length(rows) == 383
    assert Enum.count(rows, &Map.has_key?(&1, :survival)) == 25

    legacy_rows =
      for page <- actual,
          {row, evidence} <- Enum.zip(page.data, page.evidence),
          do: {Map.delete(row, :survival), evidence}

    legacy =
      Stream.unfold(args, fn
        nil ->
          nil

        args ->
          {:ok, page} = Result.page(legacy_rows, args, {Deaths.name(), context.id})
          {page, if(page.truncated, do: Map.put(args, "cursor", page.next_cursor))}
      end)
      |> Enum.to_list()

    assert length(actual) == length(legacy)
    assert length(actual) == 48
    assert Enum.flat_map(legacy, & &1.data) == Enum.map(rows, &Map.delete(&1, :survival))

    IO.puts(
      "Sszorak pull 5 deaths: before_pages=#{length(legacy)}, after_pages=#{length(actual)}, " <>
        "fragments=#{length(rows)}, max_bytes=#{Enum.max(Enum.map(actual, &byte_size(Jason.encode!(&1))))}"
    )
  end

  defp persist_pull(path, start_byte, end_byte) do
    user = Repo.insert!(%WeGoNext.Accounts.User{name: "deaths-survival"})
    log = Repo.insert!(%CombatLogFile{user_id: user.id, file_path: path})

    dim =
      Repo.insert!(%DimEncounter{
        source_file_path: path,
        start_byte: start_byte,
        name: "Sszorak",
        wow_encounter_id: "3420",
        start_time: @start
      })

    Repo.insert!(%WeGoNext.Encounters.Encounter{
      combat_log_file_id: log.id,
      start_byte: start_byte,
      name: dim.name,
      wow_encounter_id: dim.wow_encounter_id,
      start_time: @start
    })

    {:ok, events} = CombatLogParser.parse_events(path, start_byte, end_byte, @origin)
    projection = Silver.Projector.project(dim.id, events)

    for {schema, key} <- [
          {Silver.PlayerInfo, :player_info},
          {Silver.Death, :death},
          {Silver.SurvivalAction, :survival_action},
          {Silver.DefensiveBuffWindow, :defensive_buff_window}
        ],
        attrs <- Map.fetch!(projection, key),
        do: Repo.insert!(schema.changeset(struct(schema), attrs))

    {dim, %{id: Ecto.UUID.generate(), combat_log_file_id: log.id}}
  end

  defp pages(args, context) do
    Stream.unfold(args, fn
      nil ->
        nil

      args ->
        assert {:ok, page} = Deaths.run(args, context)
        assert byte_size(Jason.encode!(page)) <= Result.cap()
        assert length(page.data) == length(page.evidence)
        {page, if(page.truncated, do: Map.put(args, "cursor", page.next_cursor))}
    end)
    |> Enum.to_list()
  end
end

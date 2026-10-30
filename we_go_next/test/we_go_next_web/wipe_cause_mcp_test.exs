defmodule WeGoNextWeb.WipeCauseMCPTest do
  use WeGoNextWeb.ConnCase, async: false
  alias WeGoNext.Analysis.{BuiltInQuestions, Session, ToolCall}
  alias WeGoNext.Analysis.Tools.WipeCause
  alias WeGoNext.Gold.{DimEncounter, FactWipeCause}
  alias WeGoNext.Silver.{Death, DeathDerivation}

  setup do
    user = Repo.insert!(%WeGoNext.Accounts.User{name: "wipe-cause"})
    log = Repo.insert!(%WeGoNext.CombatLogFile{user_id: user.id, file_path: "/wipe.txt"})

    dim =
      Repo.insert!(%DimEncounter{
        source_file_path: log.file_path,
        start_byte: 0,
        name: "Sszorak",
        wow_encounter_id: "3420",
        success: false,
        fight_time_ms: 411_678,
        start_time: ~U[2026-09-06 15:33:20.939000Z],
        silver_death_derivation_version: DeathDerivation.current_version()
      })

    Repo.insert!(%WeGoNext.Encounters.Encounter{
      combat_log_file_id: log.id,
      start_byte: 0,
      name: dim.name,
      wow_encounter_id: dim.wow_encounter_id,
      start_time: dim.start_time,
      fight_time_ms: dim.fight_time_ms,
      success: false
    })

    Repo.insert!(%WeGoNext.Silver.PlayerInfo{
      encounter_dim_id: dim.id,
      player_guid: "Player-Kahnu",
      player_name: "Kahnu"
    })

    Repo.insert!(%Death{
      encounter_dim_id: dim.id,
      target_guid: "Player-Kahnu",
      died_at_ms_into_fight: 155_271,
      killing_blow_spell_id: 1_285_999,
      damage_recap: [%{"spell_name" => "Mutilate"}]
    })

    assert {:ok, _} = FactWipeCause.rebuild_for_encounter(dim.id)
    session = Repo.insert!(%Session{combat_log_file_id: log.id, started_at: DateTime.utc_now()})
    {:ok, dim: dim, session: session}
  end

  test "cost and binding: Q1/Q4 path records exactly one Tool call and zero model calls", %{
    dim: dim,
    session: session
  } do
    assert [%{id: "wipe_cause", title: "Why did this pull wipe?", tool: "wipe_cause"}] =
             BuiltInQuestions.all()

    assert {:ok, result} =
             BuiltInQuestions.answer("wipe_cause", %{
               "session_id" => session.id,
               "pulls" => [dim.id]
             })

    assert result.data.model_calls == 0
    assert result.data.model_cost_usd == 0

    assert [
             %{
               player_name: "Kahnu",
               died_at_ms_into_fight: 155_271,
               avoidable: nil,
               status: "current"
             }
           ] = result.data.deciding_deaths

    assert [%{tool: "wipe_cause", error: nil}] = Repo.all(ToolCall)

    assert result.data.most_common_deciding_killing_blow == %{
             spell_id: 1_285_999,
             spell_name: "Mutilate",
             count: 1
           }

    assert {:error, _} = BuiltInQuestions.answer("missing", %{})
  end

  test "MCP answers from gold with pull/time evidence", %{dim: dim, session: session} do
    conn =
      %{build_conn() | host: "localhost"}
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Plug.Conn.put_req_header("accept", "application/json, text/event-stream")
      |> post(
        "/analysis/mcp",
        Jason.encode!(%{
          jsonrpc: "2.0",
          id: 1,
          method: "tools/call",
          params: %{name: "wipe_cause", arguments: %{session_id: session.id, pulls: [dim.id]}}
        })
      )

    assert %{"result" => %{"isError" => false, "content" => [%{"text" => text}]}} =
             json_response(conn, 200)

    result = Jason.decode!(text)

    assert [%{"pull_id" => id, "ms_into_fight" => 155_271, "source" => "gold.fact_wipe_cause"}] =
             result["evidence"]

    assert id == dim.id
    assert hd(result["data"]["deciding_deaths"])["player_name"] == "Kahnu"
  end

  test "missing/stale/empty states and log scope are explicit", %{dim: dim, session: session} do
    args = %{"pulls" => [dim.id]}
    assert {:error, _} = WipeCause.run(%{"pulls" => [dim.id + 9999]}, session)
    Repo.delete_all(FactWipeCause)

    Repo.update!(
      Ecto.Changeset.change(Repo.get!(DimEncounter, dim.id), wipe_cause_derivation_version: nil)
    )

    assert {:ok, %{data: %{deciding_deaths: [%{status: "missing_or_stale_gold"}]}}} =
             WipeCause.run(args, session)

    Repo.update!(
      Ecto.Changeset.change(Repo.get!(DimEncounter, dim.id), silver_death_derivation_version: nil)
    )

    assert {:ok, %{data: %{deciding_deaths: [%{status: "stale_silver_deaths"}]}}} =
             WipeCause.run(args, session)
  end

  test "across-pull repeated spell ties are deterministic, unknown blows excluded" do
    rows =
      for spell <- [3, 2, 3, 2, nil],
          do: %{killing_blow_spell_id: spell, killing_blow_spell_name: "name"}

    assert WipeCause.most_common(rows) == %{spell_id: 2, spell_name: "name", count: 2}
    assert WipeCause.most_common([]) == nil
  end
end

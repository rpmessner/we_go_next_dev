defmodule WeGoNextWeb.AnalysisStartupTest do
  use WeGoNextWeb.ConnCase, async: false
  alias WeGoNext.Analysis.{Session, ToolCall}

  setup do
    user = Repo.insert!(%WeGoNext.Accounts.User{name: "startup"})

    log =
      Repo.insert!(%WeGoNext.CombatLogFile{
        user_id: user.id,
        file_path: "/logs/Archive-090626.txt",
        last_parsed_at: ~U[2026-09-06 12:00:00Z]
      })

    Repo.insert!(%WeGoNext.Encounters.Encounter{
      combat_log_file_id: log.id,
      name: "Sszorak",
      wow_encounter_id: "42"
    })

    {:ok, log: log}
  end

  test "boss is the first positional argument" do
    assert %{"result" => %{"prompts" => [%{"arguments" => args}]}} = rpc("prompts/list")
    assert Enum.map(args, & &1["name"]) == ["boss", "log"]
  end

  test "blank arguments mean latest imported log and no boss", %{log: log} do
    text = prompt(%{"log" => " \t", "boss" => ""})
    assert text =~ "# Between-pull method"
    assert Repo.one!(Session).combat_log_file_id == log.id
    assert Repo.one!(Session).boss == nil
  end

  test "filename fragments and surrounding whitespace resolve imported logs", %{log: log} do
    assert prompt(%{"log" => " 090626 ", "boss" => " Sszorak "}) =~ "# Between-pull method"
    assert Repo.one!(Session).combat_log_file_id == log.id
    assert Repo.one!(Session).boss == "Sszorak"
  end

  test "unknown or ambiguous log returns choices without minting a session", %{log: log} do
    Repo.insert!(%WeGoNext.CombatLogFile{
      user_id: log.user_id,
      file_path: "/logs/other-090626.txt",
      last_parsed_at: ~U[2026-09-07 12:00:00Z]
    })

    for value <- ["Twin Fangs", "090626", "999999999999999999999999999999"] do
      text = prompt(%{"log" => value})
      assert text =~ "No Analysis session started"
      assert text =~ "Archive-090626.txt"
      assert text =~ "2026-09-06"
      assert text =~ "1 encounter"
      assert text =~ "log"
    end

    assert Repo.aggregate(Session, :count) == 0
  end

  test "log choices show only the five most recent imports", %{log: log} do
    for n <- 1..6 do
      Repo.insert!(%WeGoNext.CombatLogFile{
        user_id: log.user_id,
        file_path: "/logs/recent-#{n}.txt",
        last_parsed_at: DateTime.add(~U[2026-09-07 12:00:00Z], n, :second)
      })
    end

    text = prompt(%{"log" => "missing"})
    assert text =~ "recent-6.txt"
    assert text =~ "recent-2.txt"
    refute text =~ "recent-1.txt"
    refute text =~ "Archive-090626.txt"
    assert Repo.aggregate(Session, :count) == 0
  end

  test "no imported logs gives a helpful prompt without a session" do
    Repo.delete_all(WeGoNext.Encounters.Encounter)
    Repo.delete_all(WeGoNext.CombatLogFile)
    assert prompt(%{}) =~ "No imported logs are available"
    assert Repo.aggregate(Session, :count) == 0
  end

  test "unimported logs are not selectable", %{log: log} do
    pending =
      Repo.insert!(%WeGoNext.CombatLogFile{user_id: log.user_id, file_path: "/logs/pending.txt"})

    assert prompt(%{"log" => "pending"}) =~ "No Analysis session started"
    assert prompt(%{"log" => to_string(pending.id)}) =~ "No Analysis session started"
    assert Repo.aggregate(Session, :count) == 0
  end

  test "unknown boss is unset with a warning, but the session starts" do
    text = prompt(%{"boss" => "Twin Fangs"})
    assert text =~ "Unknown boss"
    assert text =~ "# Between-pull method"
    assert Repo.one!(Session).boss == nil
  end

  test "unusable argument shapes return a normal helpful prompt" do
    for args <- [%{"log" => 9}, %{"other" => "value"}, []] do
      assert prompt(args) =~ "No Analysis session started"
    end

    assert Repo.aggregate(Session, :count) == 0
  end

  test "start_session is discoverable without a required session id" do
    assert %{"result" => %{"tools" => tools}} = rpc("tools/list")
    tool = Enum.find(tools, &(&1["name"] == "start_session"))
    assert tool
    assert tool["inputSchema"]["required"] == []
  end

  test "start_session returns instructions, loaded Playbooks and an audited session", %{log: log} do
    assert %{"result" => %{"isError" => false, "content" => [%{"text" => json}]}} =
             rpc("tools/call", %{
               "name" => "start_session",
               "arguments" => %{"boss" => "Sszorak", "log" => "090626"}
             })

    result = Jason.decode!(json)
    session = Repo.one!(Session)
    assert result["data"]["session_id"] == session.id
    assert result["data"]["instructions"] =~ "# Between-pull method"
    assert result["data"]["instructions"] =~ "[Sszorak pull 4, 2:31, deaths]"
    assert session.combat_log_file_id == log.id
    assert session.boss == "Sszorak"
    assert [%{"id" => "between-pulls"}] = session.loaded_playbooks
    call = Repo.one!(ToolCall)
    assert call.session_id == session.id
    assert call.tool == "start_session"
    assert call.result == result
    assert call.result_size <= 8192
  end

  test "start_session shares the prompt's blank and unusable argument handling" do
    assert %{"result" => %{"isError" => false, "content" => [%{"text" => json}]}} =
             rpc("tools/call", %{"name" => "start_session", "arguments" => %{"log" => "missing"}})

    result = Jason.decode!(json)
    assert result["data"]["session_id"] == nil
    assert result["data"]["instructions"] =~ "No Analysis session started"
    assert Repo.aggregate(Session, :count) == 0
    assert Repo.one!(ToolCall).session_id == nil

    assert %{"result" => %{"isError" => false}} =
             rpc("tools/call", %{
               "name" => "start_session",
               "arguments" => %{"log" => "", "boss" => " "}
             })

    assert Repo.aggregate(Session, :count) == 1
  end

  defp prompt(args) do
    assert %{"result" => %{"messages" => [%{"content" => %{"text" => text}}]}} =
             rpc("prompts/get", %{"name" => "analysis-session", "arguments" => args})

    text
  end

  defp rpc(method, params \\ %{}) do
    %{Phoenix.ConnTest.build_conn() | host: "localhost"}
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> post(
      "/analysis/mcp",
      Jason.encode!(%{jsonrpc: "2.0", id: 1, method: method, params: params})
    )
    |> json_response(200)
  end
end

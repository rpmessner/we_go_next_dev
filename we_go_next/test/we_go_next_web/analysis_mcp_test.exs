defmodule WeGoNextWeb.AnalysisMCPTest do
  use WeGoNextWeb.ConnCase, async: false
  alias WeGoNext.Analysis.{Session, ToolCall}

  setup do
    user = Repo.insert!(%WeGoNext.Accounts.User{name: "analysis-mcp"})

    log =
      Repo.insert!(%WeGoNext.CombatLogFile{
        user_id: user.id,
        file_path: "/mcp.txt",
        last_parsed_at: ~U[2026-09-06 12:00:00Z]
      })

    {:ok, log: log}
  end

  test "initializes and lists only enabled Tools and the session prompt" do
    assert %{
             "result" => %{
               "protocolVersion" => "2025-03-26",
               "capabilities" => %{"tools" => %{}, "prompts" => %{}}
             }
           } = rpc("initialize", %{"protocolVersion" => "2025-03-26"})

    assert %{"result" => %{"tools" => tools}} = rpc("tools/list")

    assert Enum.map(tools, & &1["name"]) == [
             "start_session",
             "session_context",
             "list_pulls",
             "pull_summary",
             "deaths",
             "failures",
             "damage_taken",
             "interrupts",
             "list_playbooks",
             "get_playbook",
             "record_verdict"
           ]

    assert Enum.all?(
             Enum.reject(tools, &(&1["name"] == "start_session")),
             &("session_id" in &1["inputSchema"]["required"])
           )

    assert Enum.find(tools, &(&1["name"] == "interrupts"))["description"] =~ "log_events"
    assert %{"result" => %{"prompts" => [%{"name" => "analysis-session"}]}} = rpc("prompts/list")
  end

  test "prompt mints durable log-scoped sessions and Tool calls are recorded", %{log: log} do
    response =
      rpc("prompts/get", %{
        "name" => "analysis-session",
        "arguments" => %{"log" => to_string(log.id), "boss" => "Sszorak"}
      })

    assert %{"result" => %{"messages" => [%{"content" => %{"text" => text}}]}} = response
    session = Repo.one!(Session)
    assert text =~ session.id
    assert text =~ "session_context"
    assert text =~ "# Between-pull method"
    assert text =~ "[Sszorak pull 4, 2:31, deaths]"
    assert [%{"id" => "between-pulls", "git_commit" => commit}] = session.loaded_playbooks

    assert commit ==
             WeGoNext.Analysis.Playbooks.git_commit(WeGoNext.Analysis.Playbooks.directory())

    assert session.combat_log_file_id == log.id
    assert session.boss == nil
    assert text =~ "Unknown boss"

    assert %{"result" => %{"isError" => false, "content" => [%{"text" => result}]}} =
             rpc("tools/call", %{
               "name" => "list_pulls",
               "arguments" => %{"session_id" => session.id}
             })

    assert %{"data" => [], "evidence" => [], "truncated" => false, "next_cursor" => nil} =
             Jason.decode!(result)

    assert Repo.one!(ToolCall).session_id == session.id
    rpc("prompts/get", %{"name" => "analysis-session"})
    assert Repo.aggregate(Session, :count) == 2
  end

  test "silver Tools execute and record through MCP", %{log: log} do
    session =
      Repo.insert!(%Session{
        combat_log_file_id: log.id,
        started_at: ~U[2026-10-29 12:00:00.000000Z]
      })

    Repo.insert!(%WeGoNext.Encounters.Encounter{
      combat_log_file_id: log.id,
      start_byte: 0,
      wow_encounter_id: "3180",
      name: "Vanguard"
    })

    dim =
      Repo.insert!(%WeGoNext.Gold.DimEncounter{
        source_file_path: log.file_path,
        start_byte: 0,
        wow_encounter_id: "3180",
        name: "Vanguard"
      })

    for name <- ["damage_taken", "interrupts"] do
      assert %{"result" => %{"isError" => false, "content" => [%{"text" => json}]}} =
               rpc("tools/call", %{
                 "name" => name,
                 "arguments" => %{"session_id" => session.id, "pulls" => [dim.id]}
               })

      assert %{"evidence" => [], "truncated" => false} = Jason.decode!(json)
    end

    assert Repo.aggregate(ToolCall, :count) == 2
  end

  test "prompt selects active boss Playbooks by name or game id and excludes retired ones", %{
    log: log
  } do
    alias WeGoNext.Analysis.Playbooks

    for {id, status} <- [{"test-boss", "active"}, {"test-retired", "retired"}] do
      path = Path.join(Playbooks.directory(), "#{id}.md")
      on_exit(fn -> File.rm!(path) end)

      File.write!(path, """
      ---
      title: Test boss method
      scope: boss
      encounter_ids: [42]
      question_families: ["mechanics"]
      status: #{status}
      ---
      Instructions for #{id}.
      """)
    end

    Repo.insert!(%WeGoNext.Encounters.Encounter{
      combat_log_file_id: log.id,
      name: "Sszorak",
      wow_encounter_id: "42"
    })

    for boss <- ["Sszorak", "42", "Other"] do
      response =
        rpc("prompts/get", %{"name" => "analysis-session", "arguments" => %{"boss" => boss}})

      assert %{"result" => %{"messages" => [%{"content" => %{"text" => text}}]}} = response
      assert text =~ "# Between-pull method"
      assert text =~ "Instructions for test-boss." == (boss != "Other")
      refute text =~ "Instructions for test-retired."
    end

    sessions = Repo.all(Session)

    for session <- sessions do
      ids = Enum.map(session.loaded_playbooks, & &1["id"])
      assert "test-boss" in ids == (session.boss == "Sszorak")
      refute "test-retired" in ids
    end

    session = hd(sessions)

    assert %{"result" => %{"isError" => false, "content" => [%{"text" => data}]}} =
             rpc("tools/call", %{
               "name" => "list_playbooks",
               "arguments" => %{"session_id" => session.id, "question_family" => "mechanics"}
             })

    assert Enum.any?(Jason.decode!(data)["data"], &(&1["id"] == "test-boss"))
    refute Enum.any?(Jason.decode!(data)["data"], &(&1["id"] == "test-retired"))

    assert %{"result" => %{"isError" => true}} =
             rpc("tools/call", %{
               "name" => "get_playbook",
               "arguments" => %{"session_id" => session.id, "id" => "test-retired"}
             })
  end

  test "prompt records null provenance when git is unavailable" do
    path = System.fetch_env!("PATH")
    System.put_env("PATH", "")

    try do
      assert %{"result" => _} = rpc("prompts/get", %{"name" => "analysis-session"})

      assert [%{"id" => "between-pulls", "git_commit" => nil}] =
               Repo.one!(Session).loaded_playbooks
    after
      System.put_env("PATH", path)
    end
  end

  test "invalid Tool arguments return Tool results, not protocol errors" do
    assert %{"result" => %{"isError" => true, "content" => [%{"text" => text}]}} =
             rpc("tools/call", %{
               "name" => "list_pulls",
               "arguments" => %{"session_id" => "unknown"}
             })

    assert text =~ "Unknown Analysis session"
    assert Repo.one!(ToolCall).result == Jason.decode!(text)
    assert Repo.one!(ToolCall).error =~ "Unknown Analysis session"
  end

  test "non-loopback callers and malicious browser origins are rejected before dispatch" do
    conn = %{request_conn() | remote_ip: {10, 0, 0, 1}}

    assert post(
             conn,
             "/analysis/mcp",
             Jason.encode!(%{jsonrpc: "2.0", id: 1, method: "tools/list"})
           ).status == 403

    conn = request_conn() |> Plug.Conn.put_req_header("origin", "https://attacker.example")
    assert post(conn, "/analysis/mcp", "{}").status == 403
    assert Repo.aggregate(Session, :count) == 0
  end

  test "IPv6 loopback is allowed and forwarded headers cannot bypass socket checks" do
    for ip <- [{0, 0, 0, 0, 0, 0, 0, 1}, {0, 0, 0, 0, 0, 65_535, 32_767, 1}] do
      conn = %{request_conn() | remote_ip: ip}

      assert post(
               conn,
               "/analysis/mcp",
               Jason.encode!(%{jsonrpc: "2.0", id: 1, method: "tools/list"})
             ).status == 200
    end

    conn = %{request_conn() | remote_ip: {192, 168, 1, 3}}
    conn = Plug.Conn.put_req_header(conn, "x-forwarded-for", "127.0.0.1")
    assert post(conn, "/analysis/mcp", "{}").status == 403
  end

  test "default log is the most recently imported, not the newest catalogue row", %{log: log} do
    Repo.insert!(%WeGoNext.CombatLogFile{
      user_id: log.user_id,
      file_path: "/older.txt",
      last_parsed_at: ~U[2026-09-05 12:00:00Z]
    })

    assert %{"result" => _} = rpc("prompts/get", %{"name" => "analysis-session"})
    assert Repo.one!(Session).combat_log_file_id == log.id

    assert %{"result" => %{"messages" => [%{"content" => %{"text" => text}}]}} =
             rpc("prompts/get", %{
               "name" => "analysis-session",
               "arguments" => %{"log" => "999999999999999999999999999999"}
             })

    assert text =~ "No Analysis session started"
    assert Repo.aggregate(Session, :count) == 1
  end

  test "the negotiated March protocol accepts batches but not batched initialization" do
    requests = [
      %{jsonrpc: "2.0", id: 1, method: "tools/list"},
      %{jsonrpc: "2.0", method: "notifications/initialized"},
      %{jsonrpc: "2.0", id: 2, method: "ping"}
    ]

    assert [%{"id" => 1, "result" => _}, %{"id" => 2, "result" => %{}}] =
             post(request_conn(), "/analysis/mcp", Jason.encode!(requests)) |> json_response(200)

    assert %{"error" => %{"code" => -32_600}} =
             post(
               request_conn(),
               "/analysis/mcp",
               Jason.encode!([%{jsonrpc: "2.0", id: 1, method: "initialize"}])
             )
             |> json_response(200)
  end

  test "notifications are accepted, GET is unsupported, malformed JSON is a parse error" do
    assert post(
             request_conn(),
             "/analysis/mcp",
             Jason.encode!(%{jsonrpc: "2.0", method: "notifications/initialized"})
           ).status == 202

    assert get(request_conn(), "/analysis/mcp").status == 405

    assert %{"error" => %{"code" => -32_700}} =
             post(request_conn(), "/analysis/mcp", "{") |> json_response(200)

    assert %{"error" => %{"code" => -32_601}} = rpc("not/a/method")
  end

  defp rpc(method, params \\ %{}) do
    request_conn()
    |> post(
      "/analysis/mcp",
      Jason.encode!(%{jsonrpc: "2.0", id: 1, method: method, params: params})
    )
    |> json_response(200)
  end

  defp request_conn do
    %{Phoenix.ConnTest.build_conn() | host: "localhost"}
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Plug.Conn.put_req_header("accept", "application/json, text/event-stream")
  end
end

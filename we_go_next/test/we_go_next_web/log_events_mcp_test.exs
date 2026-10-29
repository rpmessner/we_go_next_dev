defmodule WeGoNextWeb.LogEventsMCPTest do
  use WeGoNextWeb.ConnCase, async: false

  alias WeGoNext.Analysis.{Session, ToolCall}
  alias WeGoNext.{CombatLogFile, Repo}
  alias WeGoNext.Encounters.Encounter
  alias WeGoNext.Gold.DimEncounter

  test "MCP returns and records raw byte evidence and path-specific file errors" do
    fixture = Path.expand("../fixtures/survival_actions_real_pull.txt", __DIR__)

    path =
      Path.join(System.tmp_dir!(), "log-events-mcp-#{System.unique_integer([:positive])}.txt")

    File.cp!(fixture, path)
    on_exit(fn -> File.rm(path) end)
    user = Repo.insert!(%WeGoNext.Accounts.User{name: "log-events-mcp"})
    log = Repo.insert!(%CombatLogFile{user_id: user.id, file_path: path})
    start = ~U[2026-07-19 15:38:36.049000Z]

    Repo.insert!(%Encounter{
      combat_log_file_id: log.id,
      name: "Vanguard",
      wow_encounter_id: "3180",
      start_byte: 0,
      start_time: start
    })

    dim =
      Repo.insert!(%DimEncounter{
        source_file_path: path,
        name: "Vanguard",
        wow_encounter_id: "3180",
        start_byte: 0,
        end_byte: File.stat!(path).size,
        start_time: start
      })

    session = Repo.insert!(%Session{combat_log_file_id: log.id, started_at: start})

    args = %{
      "session_id" => session.id,
      "pull" => dim.id,
      "filters" => %{"spell_ids" => [22_812]}
    }

    assert %{"result" => %{"isError" => false, "content" => [%{"text" => json}]}} = call(args)

    assert %{
             "data" => [
               %{"spell_name" => "Barkskin", "source_name" => "Grdengnome-WyrmrestAccord-US"}
             ],
             "evidence" => [
               %{
                 "pull_id" => id,
                 "timestamp" => "7/19/2026 11:38:47.618-4",
                 "byte_offset" => offset
               }
             ]
           } = Jason.decode!(json)

    assert id == dim.id
    assert offset > 0
    assert Repo.one!(ToolCall).result == Jason.decode!(json)

    File.rm!(path)

    assert %{"result" => %{"isError" => true, "content" => [%{"text" => error_json}]}} =
             call(args)

    assert Jason.decode!(error_json)["error"] =~ path
    assert Repo.aggregate(ToolCall, :count) == 2
  end

  defp call(args) do
    %{Phoenix.ConnTest.build_conn() | host: "localhost"}
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Plug.Conn.put_req_header("accept", "application/json, text/event-stream")
    |> post(
      "/analysis/mcp",
      Jason.encode!(%{
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: %{name: "log_events", arguments: args}
      })
    )
    |> json_response(200)
  end
end

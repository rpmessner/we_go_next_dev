defmodule WeGoNextWeb.IngestControllerTest do
  use WeGoNextWeb.ConnCase, async: false

  import Plug.Conn

  alias WeGoNext.Gold.FactFailure
  alias WeGoNext.Repo

  setup do
    original_token = Application.get_env(:we_go_next, :mirror_ingest_token)
    original_max = Application.get_env(:we_go_next, :mirror_ingest_max_bytes)

    Application.put_env(:we_go_next, :mirror_ingest_token, "test-token")
    Application.put_env(:we_go_next, :mirror_ingest_max_bytes, 10_000)

    on_exit(fn ->
      restore_env(:mirror_ingest_token, original_token)
      restore_env(:mirror_ingest_max_bytes, original_max)
    end)

    :ok
  end

  test "ingests an authorized snapshot", %{conn: conn} do
    response =
      conn
      |> put_req_header("authorization", "Bearer test-token")
      |> post(~p"/api/ingest", snapshot())
      |> json_response(200)

    assert response["status"] == "ok"
    assert response["source_encounter_key"] == "endpoint-encounter"
    assert response["inserted"] == 1
    assert Repo.aggregate(FactFailure, :count) == 1
  end

  test "rejects missing or wrong bearer token", %{conn: conn} do
    assert %{"error" => "unauthorized"} =
             conn
             |> post(~p"/api/ingest", snapshot())
             |> json_response(401)

    assert %{"error" => "unauthorized"} =
             conn
             |> recycle()
             |> put_req_header("authorization", "Bearer wrong")
             |> post(~p"/api/ingest", snapshot())
             |> json_response(401)
  end

  test "rejects unsupported schema versions", %{conn: conn} do
    assert %{"error" => "unsupported_schema_version"} =
             conn
             |> put_req_header("authorization", "Bearer test-token")
             |> post(~p"/api/ingest", %{snapshot() | schema_version: 999})
             |> json_response(422)
  end

  test "rejects oversized ingest requests before controller handling", %{conn: conn} do
    Application.put_env(:we_go_next, :mirror_ingest_max_bytes, 1)

    assert %{"error" => "payload_too_large"} =
             conn
             |> put_req_header("authorization", "Bearer test-token")
             |> put_req_header("content-length", "2")
             |> post(~p"/api/ingest", snapshot())
             |> json_response(413)
  end

  defp restore_env(key, nil), do: Application.delete_env(:we_go_next, key)
  defp restore_env(key, value), do: Application.put_env(:we_go_next, key, value)

  defp snapshot do
    %{
      schema_version: 1,
      encounter: %{
        source_encounter_key: "endpoint-encounter",
        wow_encounter_id: "boss-one",
        name: "Endpoint Boss",
        start_time: "2026-06-28T20:00:00Z",
        success: false
      },
      players: [%{player_guid: "Player-One", player_name: "One"}],
      criteria: [
        %{
          criterion_key: "endpoint-criterion",
          ruleset_id: 10,
          ruleset_version: 1,
          product: "wow",
          channel: "retail",
          spell_id: 101,
          spell_name: "Swirl",
          mechanic_type: "avoidable",
          threshold: %{"max_hits" => 0},
          active: true
        }
      ],
      facts: [
        %{
          player_guid: "Player-One",
          criterion_key: "endpoint-criterion",
          ruleset_id: 10,
          ruleset_version: 1,
          product: "wow",
          channel: "retail",
          failure_count: 1,
          total_damage: 100
        }
      ]
    }
  end
end

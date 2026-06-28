defmodule WeGoNextWeb.Plugs.IngestContentLength do
  @moduledoc """
  Rejects oversized ingest requests before JSON body parsing.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{request_path: "/api/ingest"} = conn, _opts) do
    max_bytes = Application.get_env(:we_go_next, :mirror_ingest_max_bytes, 1_000_000)

    case content_length(conn) do
      length when is_integer(length) and length > max_bytes ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(:request_entity_too_large, Jason.encode!(%{error: "payload_too_large"}))
        |> halt()

      _length ->
        conn
    end
  end

  def call(conn, _opts), do: conn

  defp content_length(conn) do
    conn
    |> get_req_header("content-length")
    |> List.first()
    |> parse_integer()
  end

  defp parse_integer(nil), do: nil

  defp parse_integer(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> nil
    end
  end
end

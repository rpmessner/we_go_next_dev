defmodule WeGoNextWeb.Plugs.AnalysisMCP do
  @moduledoc "Dev-only stateless Streamable HTTP MCP endpoint, guarded before body parsing."
  import Plug.Conn
  alias WeGoNext.Analysis.MCP
  def init(opts), do: opts

  def call(%{path_info: ["analysis", "mcp"]} = conn, _opts) do
    cond do
      not loopback?(conn.remote_ip) or not local_origin?(conn) ->
        send_resp(conn, 403, "Loopback only") |> halt()

      conn.method != "POST" ->
        conn |> put_resp_header("allow", "POST") |> send_resp(405, "Method not allowed") |> halt()

      not json?(conn) ->
        send_resp(conn, 415, "Use application/json") |> halt()

      true ->
        respond(conn)
    end
  end

  def call(conn, _opts), do: conn

  defp respond(conn) do
    case read_body(conn, length: 65_536, read_length: 65_536) do
      {:ok, body, conn} ->
        response =
          case Jason.decode(body) do
            {:ok, request} -> MCP.dispatch(request)
            {:error, _} -> MCP.error(nil, -32_700, "Parse error")
          end

        case response do
          :notification ->
            send_resp(conn, 202, "") |> halt()

          result ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(result))
            |> halt()
        end

      {:more, _, conn} ->
        send_resp(conn, 413, "Request too large") |> halt()

      {:error, _} ->
        send_resp(conn, 400, "Could not read request") |> halt()
    end
  end

  defp loopback?({127, _, _, _}), do: true
  defp loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp loopback?({0, 0, 0, 0, 0, 65_535, high, _}) when high in 32_512..32_767, do: true
  defp loopback?(_), do: false

  defp json?(conn),
    do:
      Enum.any?(
        get_req_header(conn, "content-type"),
        &String.starts_with?(&1, "application/json")
      )

  defp local_origin?(conn) do
    conn.host in ["localhost", "127.0.0.1", "::1", "[::1]"] and
      Enum.all?(get_req_header(conn, "origin"), fn origin ->
        uri = URI.parse(origin)
        uri.scheme in ["http", "https"] and uri.host in ["localhost", "127.0.0.1", "::1"]
      end)
  end
end

defmodule WeGoNextWeb.Plugs.PublicViewer do
  @moduledoc """
  Shared-secret slug gate for public mirror viewer routes.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    expected = Application.get_env(:we_go_next, :public_viewer_slug)
    slug = conn.path_params["slug"]

    if valid_slug?(slug, expected) do
      put_session(conn, :public_viewer_slug, slug)
    else
      conn
      |> send_resp(:not_found, "Not Found")
      |> halt()
    end
  end

  defp valid_slug?(slug, expected) when is_binary(slug) and is_binary(expected) do
    byte_size(slug) == byte_size(expected) and Plug.Crypto.secure_compare(slug, expected)
  end

  defp valid_slug?(_slug, _expected), do: false
end

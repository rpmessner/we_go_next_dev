defmodule WeGoNextWeb.Plugs.RequireMode do
  @moduledoc """
  Gates routes that only exist in one application run mode.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(mode) when mode in [:parser, :public], do: mode

  @impl true
  def call(conn, mode) do
    if WeGoNext.mode() == mode do
      conn
    else
      conn
      |> send_resp(:not_found, "Not Found")
      |> halt()
    end
  end
end

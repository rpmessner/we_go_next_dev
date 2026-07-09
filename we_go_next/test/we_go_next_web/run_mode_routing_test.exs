defmodule WeGoNextWeb.RunModeRoutingTest do
  use WeGoNextWeb.ConnCase, async: false

  setup do
    original_mode = WeGoNext.mode()

    on_exit(fn ->
      Application.put_env(:we_go_next, :mode, original_mode)
    end)

    :ok
  end

  test "public mode serves only public viewer routes", %{conn: conn} do
    Application.put_env(:we_go_next, :mode, :public)

    assert conn
           |> get(~p"/failures")
           |> response(404) == "Not Found"

    assert conn
           |> get(~p"/settings")
           |> response(404) == "Not Found"

    assert conn
           |> get(~p"/")
           |> response(404) == "Not Found"
  end

  test "parser mode keeps local operator routes available", %{conn: conn} do
    Application.put_env(:we_go_next, :mode, :parser)

    assert conn
           |> get(~p"/failures")
           |> html_response(200) =~ "Mechanic Failures"

    assert conn
           |> get(~p"/settings")
           |> html_response(200) =~ "Settings"
  end
end

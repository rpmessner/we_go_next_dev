defmodule WeGoNextWeb.MirrorRemovalTest do
  use WeGoNextWeb.ConnCase, async: false

  test "local settings no longer offer document upload credentials", %{conn: conn} do
    html = conn |> get("/settings") |> html_response(200)

    assert html =~ "Warcraft Logs Credentials"
    refute html =~ "R2 Document Store"
    refute html =~ "save_document_r2_credentials"
  end

  test "retired report URLs have no route" do
    assert Phoenix.Router.route_info(WeGoNextWeb.Router, "GET", "/r/raid-night", "localhost") ==
             :error

    assert Phoenix.Router.route_info(
             WeGoNextWeb.Router,
             "GET",
             "/r/raid-night/encounters/pull",
             "localhost"
           ) == :error
  end
end

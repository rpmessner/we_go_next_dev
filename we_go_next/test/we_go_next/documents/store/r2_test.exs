defmodule WeGoNext.Documents.Store.R2Test do
  use ExUnit.Case, async: false

  import Plug.Conn

  alias WeGoNext.Documents.Store.R2

  setup do
    Req.Test.verify_on_exit!()

    original_r2 = Application.get_env(:we_go_next, :documents_r2)

    Application.put_env(:we_go_next, :documents_r2, %{
      endpoint: "https://account.r2.cloudflarestorage.com",
      bucket: "raid-documents",
      access_key_id: "access-key-id",
      secret_access_key: "secret-access-key",
      req_options: [plug: {Req.Test, __MODULE__}]
    })

    on_exit(fn -> restore_env(:documents_r2, original_r2) end)

    :ok
  end

  test "puts objects through ReqS3 using the configured R2 endpoint and bucket" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "PUT"
      assert conn.host == "account.r2.cloudflarestorage.com"
      assert conn.request_path == "/raid-documents/encounters/source-key.json"
      assert Req.Test.raw_body(conn) == ~s({"ok":true})

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, "")
    end)

    assert :ok = R2.put("encounters/source-key.json", ~s({"ok":true}))
  end

  test "fetches objects and maps missing objects in exists checks" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/raid-documents/index.json"

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, ~s({"schema_version":1}))
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "HEAD"
      assert conn.request_path == "/raid-documents/missing.json"
      send_resp(conn, 404, "")
    end)

    assert {:ok, ~s({"schema_version":1})} = R2.fetch("index.json")
    assert {:ok, false} = R2.exists?("missing.json")
  end

  defp restore_env(key, nil), do: Application.delete_env(:we_go_next, key)
  defp restore_env(key, value), do: Application.put_env(:we_go_next, key, value)
end

defmodule WeGoNext.Documents.Store.FileSystemTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Documents.Store.FileSystem

  setup do
    original_documents_root = Application.fetch_env!(:we_go_next, :documents_root)

    documents_root =
      Path.join(System.tmp_dir!(), "wgn-store-#{System.unique_integer([:positive])}")

    Application.put_env(:we_go_next, :documents_root, documents_root)

    on_exit(fn ->
      Application.put_env(:we_go_next, :documents_root, original_documents_root)
      File.rm_rf(documents_root)
    end)

    {:ok, documents_root: documents_root}
  end

  test "puts, fetches, and checks keys under the configured root", %{
    documents_root: documents_root
  } do
    key = "encounters/source-key.json"
    body = ~s({"source_encounter_key":"source-key"})

    assert {:ok, false} = FileSystem.exists?(key)
    assert :ok = FileSystem.put(key, body)
    assert {:ok, true} = FileSystem.exists?(key)
    assert {:ok, ^body} = FileSystem.fetch(key)
    assert File.read!(Path.join(documents_root, key)) == body
  end
end

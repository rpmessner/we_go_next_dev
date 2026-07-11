# Wipe test-generated encounter documents from previous runs.
File.rm_rf!(Application.fetch_env!(:we_go_next, :documents_root))

ExUnit.start()

case Application.ensure_all_started(:wallaby) do
  {:ok, _} ->
    Application.put_env(:wallaby, :base_url, WeGoNextWeb.Endpoint.url())

  {:error, _} ->
    IO.puts("\n⚠️  Wallaby failed to start - feature tests will be skipped\n")
end

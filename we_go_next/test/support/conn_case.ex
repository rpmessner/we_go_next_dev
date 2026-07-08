defmodule WeGoNextWeb.ConnCase do
  @moduledoc """
  Test case for web requests and LiveView tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint WeGoNextWeb.Endpoint

      use WeGoNextWeb, :verified_routes

      import Phoenix.ConnTest
      import Phoenix.LiveViewTest

      alias WeGoNext.Repo
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(WeGoNext.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(WeGoNext.Repo, {:shared, self()})
    end

    original_documents_root = Application.fetch_env!(:we_go_next, :documents_root)

    documents_root =
      Path.join(System.tmp_dir!(), "wgn-documents-#{System.unique_integer([:positive])}")

    Application.put_env(:we_go_next, :documents_root, documents_root)

    on_exit(fn ->
      wait_for_import_worker_idle()
      Application.put_env(:we_go_next, :documents_root, original_documents_root)
      File.rm_rf(documents_root)
    end)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  defp wait_for_import_worker_idle(deadline_ms \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + deadline_ms
    wait_for_import_worker_idle_until(deadline)
  end

  defp wait_for_import_worker_idle_until(deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      :ok
    else
      case WeGoNext.ImportWorker.active_imports() do
        imports when map_size(imports) == 0 ->
          :ok

        _imports ->
          Process.sleep(50)
          wait_for_import_worker_idle_until(deadline)
      end
    end
  catch
    :exit, _reason -> :ok
  end
end

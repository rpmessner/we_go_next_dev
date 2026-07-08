defmodule WeGoNextWeb.FeatureCase do
  @moduledoc """
  This module defines the test case to be used by feature tests.

  It provides page objects for common UI interactions.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      use Wallaby.Feature

      alias WeGoNext.Repo
      alias WeGoNext.Integration.Pages.FailuresPage
      alias WeGoNext.Integration.Pages.HomePage
      alias WeGoNext.Integration.Pages.SettingsPage

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import WeGoNextWeb.FeatureCase

      @fixtures_path Path.expand("../fixtures", __DIR__)
      @base_log_fixture Path.join(@fixtures_path, "combat_log_base.txt")

      def setup_user_with_path(path) do
        user = WeGoNext.Accounts.get_or_create_default_user()

        if user.wow_logs_path != path do
          WeGoNext.Accounts.set_wow_logs_path(user, path)
        end

        user
      end

      def setup_user_with_fixtures do
        temp_dir =
          Path.join(
            System.tmp_dir!(),
            "wgn-feature-fixtures-#{System.unique_integer([:positive])}"
          )

        File.mkdir_p!(temp_dir)

        @base_log_fixture
        |> File.cp!(Path.join(temp_dir, "WoWCombatLog-112725_120000.txt"))

        on_exit(fn -> File.rm_rf!(temp_dir) end)

        setup_user_with_path(temp_dir)
      end
    end
  end

  setup tags do
    # Set up the database sandbox
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(WeGoNext.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(WeGoNext.Repo, {:shared, self()})
    end

    # Clear any existing encounter store state
    WeGoNext.EncounterStore.clear()

    original_documents_root = Application.fetch_env!(:we_go_next, :documents_root)

    documents_root =
      Path.join(System.tmp_dir!(), "wgn-documents-#{System.unique_integer([:positive])}")

    Application.put_env(:we_go_next, :documents_root, documents_root)

    on_exit(fn ->
      wait_for_import_worker_idle()
      Application.put_env(:we_go_next, :documents_root, original_documents_root)
      File.rm_rf(documents_root)
    end)

    # Set up metadata for phoenix_ecto
    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(WeGoNext.Repo, self())
    {:ok, session} = Wallaby.start_session(metadata: metadata)

    {:ok, session: session}
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

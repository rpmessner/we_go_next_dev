defmodule WeGoNext.ApplicationTest do
  use ExUnit.Case, async: true

  test "local app includes import and file watcher children" do
    child_ids = child_ids(WeGoNext.Application.children())

    assert WeGoNext.ImportTaskSupervisor in child_ids
    assert WeGoNext.ImportWorker in child_ids
    assert WeGoNext.FileWatcher in child_ids
    assert WeGoNextWeb.Endpoint in child_ids
  end

  test "boot migration child is opt-in" do
    refute WeGoNext.ReleaseMigrator in child_ids(
             WeGoNext.Application.children(run_migrations_on_boot: false)
           )

    assert WeGoNext.ReleaseMigrator in child_ids(
             WeGoNext.Application.children(run_migrations_on_boot: true)
           )
  end

  test "release migrator runs the configured migration callback on start" do
    parent = self()
    start_supervised!({WeGoNext.ReleaseMigrator, migrate: fn -> send(parent, :migrated) end})
    assert_receive :migrated
  end

  test "mix release is configured for unix deployment" do
    release = WeGoNext.MixProject.project()[:releases][:we_go_next]
    assert release[:include_executables_for] == [:unix]
    assert release[:applications][:runtime_tools] == :permanent
  end

  defp child_ids(children) do
    children
    |> Enum.map(&Supervisor.child_spec(&1, []).id)
    |> MapSet.new()
  end
end

defmodule WeGoNext.RunModeTest do
  use ExUnit.Case, async: true

  test "defaults to parser mode" do
    assert WeGoNext.mode() == :parser
  end

  test "parser mode includes import and file watcher children" do
    child_ids = child_ids(WeGoNext.Application.children(:parser))

    assert WeGoNext.ImportTaskSupervisor in child_ids
    assert WeGoNext.ImportWorker in child_ids
    assert WeGoNext.FileWatcher in child_ids
    assert WeGoNextWeb.Endpoint in child_ids
  end

  test "public mode omits parser-only children" do
    child_ids = child_ids(WeGoNext.Application.children(:public))

    refute WeGoNext.ImportTaskSupervisor in child_ids
    refute WeGoNext.ImportWorker in child_ids
    refute WeGoNext.FileWatcher in child_ids
    assert WeGoNextWeb.Endpoint in child_ids
  end

  defp child_ids(children) do
    children
    |> Enum.map(&Supervisor.child_spec(&1, []).id)
    |> MapSet.new()
  end
end

defmodule WeGoNext.FileWatcherCleanup do
  @moduledoc false

  # on_exit runs after the sandbox owner exits. Watch-off now persists its flag,
  # so teardown needs its own connection, shared with the watcher process.
  def stop do
    case Ecto.Adapters.SQL.Sandbox.checkout(WeGoNext.Repo) do
      :ok -> Ecto.Adapters.SQL.Sandbox.mode(WeGoNext.Repo, {:shared, self()})
      {:already, :owner} -> :ok
      {:already, :allowed} -> :ok
    end

    WeGoNext.FileWatcher.stop_watching()
  end
end

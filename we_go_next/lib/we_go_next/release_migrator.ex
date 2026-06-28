defmodule WeGoNext.ReleaseMigrator do
  @moduledoc false

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    migrate = Keyword.get(opts, :migrate, &WeGoNext.Release.migrate/0)
    migrate.()

    {:ok, %{}}
  end
end

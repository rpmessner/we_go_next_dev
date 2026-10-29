defmodule WeGoNext.DataCase do
  @moduledoc "Database-backed context tests isolated by the SQL sandbox."
  use ExUnit.CaseTemplate

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(WeGoNext.Repo)
    :ok
  end
end

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

  setup _tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(WeGoNext.Repo)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end

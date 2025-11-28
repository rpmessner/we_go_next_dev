defmodule WeGoNextWeb.FeatureCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use Wallaby.Feature

      alias WeGoNext.Repo
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
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

    # Set up metadata for phoenix_ecto
    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(WeGoNext.Repo, self())
    {:ok, session} = Wallaby.start_session(metadata: metadata)

    {:ok, session: session}
  end
end

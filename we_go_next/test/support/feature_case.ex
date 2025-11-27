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

  setup _tags do
    {:ok, session} = Wallaby.start_session()
    {:ok, session: session}
  end
end

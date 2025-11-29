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
      alias WeGoNext.Integration.Pages.HomePage
      alias WeGoNext.Integration.Pages.EncounterDetailPage
      alias WeGoNext.Integration.Pages.SettingsPage

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import WeGoNextWeb.FeatureCase

      @fixtures_path Path.expand("../fixtures", __DIR__)

      def setup_user_with_path(path) do
        user = WeGoNext.Accounts.get_or_create_default_user()

        if user.wow_logs_path != path do
          WeGoNext.Accounts.set_wow_logs_path(user, path)
        end

        user
      end

      def setup_user_with_fixtures do
        setup_user_with_path(@fixtures_path)
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

    # Set up metadata for phoenix_ecto
    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(WeGoNext.Repo, self())
    {:ok, session} = Wallaby.start_session(metadata: metadata)

    {:ok, session: session}
  end
end

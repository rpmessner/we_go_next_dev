defmodule WeGoNextWeb.EncounterLiveIndexTest do
  use WeGoNextWeb.ConnCase, async: false

  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer, FactFailure}
  alias WeGoNext.Repo
  alias WeGoNext.Rules
  alias WeGoNext.Rules.{MechanicCriterion, Ruleset}
  alias WeGoNext.Silver.{DamageTaken, PlayerInfo}

  setup do
    Repo.delete_all(FactFailure)
    Repo.delete_all(DimMechanicCriterion)
    Repo.delete_all(DamageTaken)
    Repo.delete_all(PlayerInfo)
    Repo.delete_all(DimPlayer)
    Repo.delete_all(DimEncounter)
    Repo.delete_all(MechanicCriterion)
    Repo.delete_all(Ruleset)

    :ok
  end

  test "renders current-tier mechanics and recompute status", %{conn: conn} do
    html =
      conn
      |> get(~p"/")
      |> html_response(200)

    assert html =~ "Current-Tier Mechanics"
    assert html =~ "0 synced mechanics"
    assert html =~ "0 failure-ready mechanics"
    assert html =~ "Sync Mechanics &amp; Rebuild"
    refute html =~ "Seed Bundled Rules"
    refute html =~ "Promote Active Rules"
    refute html =~ "Rules Operations"
    refute html =~ "No active ruleset"
    assert html =~ "Sync the code-defined current-tier raid mechanics"
    assert html =~ "Data Recompute"
    assert html =~ "0 imported pulls"
    assert html =~ "0 tracked failure rows"
    assert html =~ "Rebuild Failures"
    assert html =~ "Force Reimport Log"
    assert html =~ "Rebuild failures after mechanic definitions or failure logic change"
    assert html =~ "Use force reimport after combat-log import logic changed"
  end

  test "renders current-tier synced mechanics as the normal active path", %{conn: conn} do
    assert {:ok, %{ruleset: active_ruleset, criteria: criteria, promoted: promoted}} =
             Rules.sync_current_tier_rules(activate: true, promote: true)

    html =
      conn
      |> get(~p"/")
      |> html_response(200)

    assert active_ruleset.name == "Midnight Season 1 Mechanics"
    assert length(criteria) == 27
    assert length(promoted.criteria) == 27
    assert html =~ "27 synced mechanics"
    assert html =~ "27 failure-ready mechanics"
    refute html =~ "Active: Midnight Season 1 Mechanics"
    assert Repo.aggregate(DimMechanicCriterion, :count) == 27
  end
end

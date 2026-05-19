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

  test "renders rules operations status", %{conn: conn} do
    html =
      conn
      |> get(~p"/")
      |> html_response(200)

    assert html =~ "Rules Operations"
    assert html =~ "No active ruleset"
    assert html =~ "0 authored rules"
    assert html =~ "0 gold snapshots"
    assert html =~ "Seed Bundled Rules"
    assert html =~ "Promote Active Rules"
    assert html =~ "Medallion Recompute"
    assert html =~ "0 gold encounters"
    assert html =~ "0 failure facts"
    assert html =~ "Rebuild Gold Facts"
    assert html =~ "Force Reimport Log"
    assert html =~ "Use gold rebuild after rules, promotions, or gold fact logic changed"
    assert html =~ "Use force reimport after parser or silver projection logic changed"
  end

  test "seeds, activates, and promotes bundled rules from the home page", %{conn: conn} do
    assert {:ok, %{ruleset: ruleset}} = Rules.seed_initial_rules()

    assert {:ok, active_ruleset} = Rules.activate_ruleset(ruleset)
    assert {:ok, %{criteria: [_first, _second]}} = Rules.promote_active_ruleset_to_gold()
    assert active_ruleset.name == "Initial Mechanic Rules"

    html =
      conn
      |> get(~p"/")
      |> html_response(200)

    assert html =~ "Active: Initial Mechanic Rules v1"
    assert html =~ "2 gold snapshots"
    assert html =~ "Active ruleset has 2 authored rules"
    assert html =~ "and 2 promoted snapshots"
    assert Repo.aggregate(DimMechanicCriterion, :count) == 2
  end
end

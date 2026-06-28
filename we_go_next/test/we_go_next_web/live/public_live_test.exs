defmodule WeGoNextWeb.PublicLiveTest do
  use WeGoNextWeb.ConnCase, async: false

  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer, FactFailure}
  alias WeGoNext.Mirror.PublicReport
  alias WeGoNext.Repo
  alias WeGoNext.Rules.Ruleset

  setup do
    original_mode = WeGoNext.mode()

    Application.put_env(:we_go_next, :mode, :public)

    on_exit(fn ->
      Application.put_env(:we_go_next, :mode, original_mode)
    end)

    %{report: insert_report!("raid-night", "Raid Night")}
  end

  test "valid report slug renders public encounter list", %{conn: conn, report: report} do
    encounter = insert_encounter!(report, "encounter-one", "Boss One", ~U[2026-06-28 20:00:00Z])
    player = insert_player!("Player-One", "One")
    criterion = insert_criterion!("criterion-swirl", 101, "Swirl", "avoidable")
    insert_failure!(encounter, player, criterion, 2, 500)

    html =
      conn
      |> get(~p"/r/raid-night")
      |> html_response(200)

    assert html =~ "Public Encounters"
    assert html =~ "Boss One"
    assert html =~ "2"
    assert html =~ "500"
    refute html =~ "Settings"
  end

  test "bad slug returns 404", %{conn: conn} do
    assert conn
           |> get(~p"/r/wrong")
           |> response(404) == "Not Found"
  end

  test "disabled report slug returns 404", %{conn: conn} do
    insert_report!("disabled-report", "Disabled", false)

    assert conn
           |> get(~p"/r/disabled-report")
           |> response(404) == "Not Found"
  end

  test "public mode parser routes remain unavailable", %{conn: conn} do
    assert conn
           |> get(~p"/settings")
           |> response(404) == "Not Found"
  end

  test "public failures page renders grouped gold failures without readiness panel", %{
    conn: conn,
    report: report
  } do
    encounter = insert_encounter!(report, "encounter-one", "Boss One", ~U[2026-06-28 20:00:00Z])
    player = insert_player!("Player-One", "One")
    criterion = insert_criterion!("criterion-swirl", 101, "Swirl", "avoidable")
    insert_failure!(encounter, player, criterion, 3, 700)

    html =
      conn
      |> get(~p"/r/raid-night/failures")
      |> html_response(200)

    assert html =~ "Public Failure Totals"
    assert html =~ "One"
    assert html =~ "Swirl"
    assert html =~ "700"
    refute html =~ "Data Readiness"
    refute html =~ "Settings"
  end

  test "public encounter failure page renders per-encounter breakdown", %{
    conn: conn,
    report: report
  } do
    encounter = insert_encounter!(report, "encounter-one", "Boss One", ~U[2026-06-28 20:00:00Z])
    player = insert_player!("Player-One", "One")
    criterion = insert_criterion!("criterion-kick", 202, "Shadow Volley", "interrupt")
    insert_failure!(encounter, player, criterion, 1, 0)

    html =
      conn
      |> get(~p"/r/raid-night/encounters/#{encounter.source_encounter_key}")
      |> html_response(200)

    assert html =~ "Boss One"
    assert html =~ "Shadow Volley"
    assert html =~ "Interrupt"
    assert html =~ "One"
  end

  test "public encounter failure page handles unknown encounter key", %{conn: conn} do
    html =
      conn
      |> get(~p"/r/raid-night/encounters/missing")
      |> html_response(200)

    assert html =~ "Encounter Not Found"
  end

  test "public report only renders encounters scoped to that report", %{
    conn: conn,
    report: report
  } do
    other_report = insert_report!("other-report", "Other")
    encounter = insert_encounter!(report, "shared-key", "Boss One", ~U[2026-06-28 20:00:00Z])
    other = insert_encounter!(other_report, "shared-key", "Other Boss", ~U[2026-06-28 21:00:00Z])
    player = insert_player!("Player-One", "One")
    criterion = insert_criterion!("criterion-swirl", 101, "Swirl", "avoidable")

    insert_failure!(encounter, player, criterion, 1, 100)
    insert_failure!(other, player, criterion, 9, 900)

    html =
      conn
      |> get(~p"/r/raid-night")
      |> html_response(200)

    assert html =~ "Boss One"
    refute html =~ "Other Boss"
  end

  test "public LiveViews do not reference Accounts or silver modules" do
    source =
      [
        "lib/we_go_next_web/live/public_live/encounters.ex",
        "lib/we_go_next_web/live/public_live/failures.ex",
        "lib/we_go_next_web/live/public_live/encounter_failures.ex"
      ]
      |> Enum.map(&File.read!(Path.expand("../../../#{&1}", __DIR__)))
      |> Enum.join("\n")

    refute source =~ "Accounts"
    refute source =~ "WeGoNext.Silver"
    refute source =~ "silver."
  end

  defp insert_report!(slug, title, enabled \\ true) do
    %PublicReport{}
    |> PublicReport.changeset(%{slug: slug, title: title, enabled: enabled})
    |> Repo.insert!()
  end

  defp insert_encounter!(%PublicReport{} = report, source_encounter_key, name, start_time) do
    %DimEncounter{}
    |> DimEncounter.changeset(%{
      public_report_id: report.id,
      source_encounter_key: source_encounter_key,
      wow_encounter_id: source_encounter_key,
      name: name,
      difficulty_id: 16,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "test-instance",
      start_time: start_time,
      end_time: DateTime.add(start_time, 300, :second),
      success: false,
      fight_time_ms: 300_000
    })
    |> Repo.insert!()
  end

  defp insert_player!(guid, name) do
    %DimPlayer{}
    |> DimPlayer.changeset(%{player_guid: guid, player_name: name})
    |> Repo.insert!()
  end

  defp insert_criterion!(criterion_key, spell_id, spell_name, mechanic_type) do
    ruleset =
      %Ruleset{}
      |> Ruleset.changeset(%{name: "Public Live Rules #{System.unique_integer([:positive])}"})
      |> Repo.insert!()

    %DimMechanicCriterion{}
    |> DimMechanicCriterion.changeset(%{
      criterion_key: criterion_key,
      source_rule_id: System.unique_integer([:positive]),
      ruleset_id: ruleset.id,
      ruleset_version: ruleset.version,
      spell_id: spell_id,
      spell_name: spell_name,
      mechanic_type: mechanic_type,
      threshold: threshold_for(mechanic_type),
      active: true
    })
    |> Repo.insert!()
  end

  defp threshold_for("interrupt"), do: %{"must_interrupt" => true}
  defp threshold_for(_mechanic_type), do: %{"max_hits" => 0}

  defp insert_failure!(encounter, player, criterion, failure_count, total_damage) do
    %FactFailure{}
    |> FactFailure.changeset(%{
      encounter_dim_id: encounter.id,
      player_dim_id: player.id,
      criterion_dim_id: criterion.id,
      ruleset_id: criterion.ruleset_id,
      ruleset_version: criterion.ruleset_version,
      product: criterion.product,
      channel: criterion.channel,
      build_version: criterion.build_version,
      build_key: criterion.build_key,
      derivation_version: 1,
      rebuilt_at: ~U[2026-06-28 20:06:00Z],
      failure_count: failure_count,
      total_damage: total_damage
    })
    |> Repo.insert!()
  end
end

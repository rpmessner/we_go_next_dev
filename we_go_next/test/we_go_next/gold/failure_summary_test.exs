defmodule WeGoNext.Gold.FailureSummaryTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Gold.{
    DimEncounter,
    DimMechanicCriterion,
    DimPlayer,
    FactFailure,
    FailureSummary
  }

  alias WeGoNext.Gold.FactFailure.Derivation
  alias WeGoNext.Repo
  alias WeGoNext.Rules.{MechanicCriterion, Ruleset}
  alias WeGoNext.Silver.DamageTaken

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    ruleset =
      %Ruleset{}
      |> Ruleset.changeset(%{name: "Failure Summary Rules", status: "active"})
      |> Repo.insert!()

    suffix = System.unique_integer([:positive])

    one =
      %DimPlayer{}
      |> DimPlayer.changeset(%{
        player_guid: "Player-One-#{suffix}",
        player_name: "One",
        class_id: 1,
        spec_id: 71
      })
      |> Repo.insert!()

    raid = get_or_insert_player!("__RAID__", "Raid")

    swirl = insert_criterion!(ruleset, 101, "Swirl", "avoidable")
    cast = insert_criterion!(ruleset, 202, "Shadow Volley", "interrupt")

    early = insert_encounter!("boss-one", "Boss One", ~U[2026-05-01 20:00:00Z])
    late = insert_encounter!("boss-two", "Boss Two", ~U[2026-05-03 20:00:00Z])

    {:ok,
     ruleset: ruleset, one: one, raid: raid, swirl: swirl, cast: cast, early: early, late: late}
  end

  test "list_grouped_failures groups by player and criterion", %{
    one: one,
    raid: raid,
    swirl: swirl,
    cast: cast,
    early: early,
    late: late
  } do
    insert_failure!(early, one, swirl, 2, 500)
    insert_failure!(late, one, swirl, 3, 700)
    insert_failure!(late, raid, cast, 1, 0)

    rows = FailureSummary.list_grouped_failures()

    assert [
             %{
               player_name: "One",
               spell_name: "Swirl",
               failure_count: 5,
               total_damage: 1_200,
               encounter_count: 2
             },
             %{
               player_name: "Raid",
               spell_name: "Shadow Volley",
               failure_count: 1,
               total_damage: 0,
               encounter_count: 1
             }
           ] = rows

    assert [
             %{player_name: "One", failure_count: 5, failures: [_]},
             %{player_name: "Raid", failure_count: 1, failures: [_]}
           ] = FailureSummary.group_by_player(rows)
  end

  test "list_grouped_failures applies inclusive date filters", %{
    one: one,
    swirl: swirl,
    early: early,
    late: late
  } do
    insert_failure!(early, one, swirl, 2, 500)
    insert_failure!(late, one, swirl, 3, 700)

    assert [
             %{
               spell_name: "Swirl",
               failure_count: 3,
               total_damage: 700,
               encounter_count: 1
             }
           ] =
             FailureSummary.list_grouped_failures(%{
               start_date: ~D[2026-05-03],
               end_date: ~D[2026-05-03]
             })
  end

  test "default_filters uses the latest imported encounter as the end date", %{
    early: _early,
    late: _late
  } do
    assert FailureSummary.default_filters() == %{
             start_date: ~D[2026-04-20],
             end_date: ~D[2026-05-03]
           }
  end

  test "default_filters is empty without imported encounter dates" do
    Repo.delete_all(FactFailure)
    Repo.delete_all(DimEncounter)

    assert FailureSummary.default_filters() == %{}
  end

  test "readiness reports matching imported observations without tracked failures", %{
    one: one,
    swirl: swirl,
    early: early
  } do
    insert_damage_taken!(early, one.player_guid, swirl.spell_id)

    readiness =
      FailureSummary.readiness(%{
        start_date: ~D[2026-05-01],
        end_date: ~D[2026-05-01]
      })

    assert readiness.active_promoted_snapshots_count == 2
    assert readiness.failure_ready_mechanics_count == 2
    assert readiness.scoped_encounters_count == 1
    assert readiness.matching_silver_observation_count == 1
    assert readiness.imported_observation_count == 1
    assert readiness.matching_criteria_count == 1
    assert readiness.selected_fact_count == 0
    assert readiness.selected_failure_row_count == 0

    assert diagnostic_titles(readiness) == ["No tracked failures"]
  end

  test "readiness reports stale failures when current mechanic definitions are not represented",
       %{
         one: one,
         swirl: swirl,
         early: early
       } do
    insert_failure!(early, one, swirl, 1, 100, ruleset_version: 99)

    readiness = FailureSummary.readiness()

    assert readiness.selected_fact_count == 1
    assert readiness.selected_failure_row_count == 1
    assert readiness.stale_fact_count == 1
    assert readiness.stale_mechanic_definition_count == 1

    assert "Facts may be stale" in diagnostic_titles(readiness)
    assert "Failure logic changed" in diagnostic_titles(readiness)
  end

  test "readiness reports failures built by old failure logic", %{
    one: one,
    swirl: swirl,
    early: early
  } do
    insert_failure!(early, one, swirl, 1, 100, derivation_version: 0)

    readiness = FailureSummary.readiness()

    assert readiness.selected_fact_count == 1
    assert readiness.selected_failure_row_count == 1
    assert readiness.stale_derivation_fact_count == 1
    assert readiness.stale_failure_logic_count == 1
    assert readiness.current_derivation_version == Derivation.current_version()

    assert "Failure logic changed" in diagnostic_titles(readiness)
  end

  test "readiness treats current fact builder derivation as fresh", %{
    one: one,
    swirl: swirl,
    early: early
  } do
    rebuilt_at = ~U[2026-05-03 21:00:00Z]

    insert_failure!(early, one, swirl, 1, 100,
      derivation_version: Derivation.current_version(),
      rebuilt_at: rebuilt_at
    )

    readiness = FailureSummary.readiness()

    assert readiness.stale_derivation_fact_count == 0
    assert DateTime.compare(readiness.latest_rebuilt_at, rebuilt_at) == :eq
    refute "Failure logic changed" in diagnostic_titles(readiness)
  end

  test "zero_fact_rule_diagnostics explains current-tier avoidable mechanics that produce no failures",
       %{
         ruleset: ruleset,
         early: early,
         late: late
       } do
    insert_authored_rule!(ruleset, 301, "Stale Snapshot", "boss-one")

    no_encounter = insert_authored_rule!(ruleset, 302, "No Encounter", "missing-boss")
    insert_snapshot!(ruleset, no_encounter)

    no_silver = insert_authored_rule!(ruleset, 303, "No Silver", early.wow_encounter_id)
    insert_snapshot!(ruleset, no_silver)

    spell_mismatch = insert_authored_rule!(ruleset, 304, "Wrong Spell", late.wow_encounter_id)
    insert_snapshot!(ruleset, spell_mismatch)
    insert_damage_taken!(late, "Player-Other", 999_304)

    inactive =
      insert_authored_rule!(ruleset, 305, "Inactive Rule", early.wow_encounter_id, active: false)

    insert_snapshot!(ruleset, inactive, active: false)

    diagnostics = FailureSummary.zero_fact_rule_diagnostics()
    reasons_by_spell = Map.new(diagnostics, &{&1.spell_id, &1.reason})

    assert reasons_by_spell[301] == :stale_gold_snapshot
    assert reasons_by_spell[302] == :no_matching_encounter
    assert reasons_by_spell[303] == :no_silver_damage_rows
    assert reasons_by_spell[304] == :spell_id_mismatch
    assert reasons_by_spell[305] == :inactive_rule

    readiness = FailureSummary.readiness()

    assert "Some mechanics produced no failures" in diagnostic_titles(readiness)
    assert length(readiness.zero_fact_rule_diagnostics) == 5
  end

  defp insert_encounter!(wow_encounter_id, name, start_time) do
    %DimEncounter{}
    |> DimEncounter.changeset(%{
      wow_encounter_id: wow_encounter_id,
      name: name,
      difficulty_id: 16,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "test-instance",
      start_time: start_time
    })
    |> Repo.insert!()
  end

  defp insert_criterion!(ruleset, spell_id, spell_name, mechanic_type) do
    %DimMechanicCriterion{}
    |> DimMechanicCriterion.changeset(%{
      source_rule_id: System.unique_integer([:positive]),
      ruleset_id: ruleset.id,
      ruleset_version: ruleset.version,
      spell_id: spell_id,
      spell_name: spell_name,
      mechanic_type: mechanic_type,
      threshold: %{"max_hits" => 0},
      active: true
    })
    |> Repo.insert!()
  end

  defp insert_authored_rule!(ruleset, spell_id, spell_name, boss_encounter_id, attrs \\ []) do
    %MechanicCriterion{}
    |> MechanicCriterion.changeset(%{
      ruleset_id: ruleset.id,
      spell_id: spell_id,
      spell_name: spell_name,
      mechanic_type: "avoidable",
      boss_encounter_id: boss_encounter_id,
      boss_name: "Diagnostic Boss",
      threshold: %{"max_hits" => 0},
      active: Keyword.get(attrs, :active, true)
    })
    |> Repo.insert!()
  end

  defp insert_snapshot!(ruleset, rule, attrs \\ []) do
    %DimMechanicCriterion{}
    |> DimMechanicCriterion.changeset(%{
      source_rule_id: rule.id,
      ruleset_id: ruleset.id,
      ruleset_version: ruleset.version,
      spell_id: rule.spell_id,
      spell_name: rule.spell_name,
      mechanic_type: rule.mechanic_type,
      boss_encounter_id: rule.boss_encounter_id,
      boss_name: rule.boss_name,
      difficulty_id: rule.difficulty_id,
      threshold: rule.threshold,
      active: Keyword.get(attrs, :active, rule.active)
    })
    |> Repo.insert!()
  end

  defp get_or_insert_player!(guid, name) do
    case Repo.get_by(DimPlayer, player_guid: guid) do
      %DimPlayer{} = player ->
        player

      nil ->
        %DimPlayer{}
        |> DimPlayer.changeset(%{player_guid: guid, player_name: name})
        |> Repo.insert!()
    end
  end

  defp insert_failure!(encounter, player, criterion, failure_count, total_damage, attrs \\ []) do
    %FactFailure{}
    |> FactFailure.changeset(%{
      encounter_dim_id: encounter.id,
      player_dim_id: player.id,
      criterion_dim_id: criterion.id,
      ruleset_id: criterion.ruleset_id,
      ruleset_version: Keyword.get(attrs, :ruleset_version, criterion.ruleset_version),
      product: criterion.product,
      channel: criterion.channel,
      build_version: criterion.build_version,
      build_key: criterion.build_key,
      derivation_version: Keyword.get(attrs, :derivation_version),
      rebuilt_at: Keyword.get(attrs, :rebuilt_at),
      failure_count: failure_count,
      total_damage: total_damage
    })
    |> Repo.insert!()
  end

  defp insert_damage_taken!(encounter, player_guid, spell_id) do
    %DamageTaken{}
    |> DamageTaken.changeset(%{
      encounter_dim_id: encounter.id,
      target_guid: player_guid,
      source_guid: "Creature-#{System.unique_integer([:positive])}",
      spell_id: spell_id,
      total_amount: 100,
      hit_count: 1,
      max_hit: 100,
      overkill_total: 0,
      source_is_npc: true
    })
    |> Repo.insert!()
  end

  defp diagnostic_titles(readiness) do
    Enum.map(readiness.diagnostics, & &1.title)
  end
end

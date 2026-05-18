defmodule Mix.Tasks.Wgn.RebuildGoldTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import ExUnit.CaptureIO

  alias Mix.Tasks.Wgn.RebuildGold
  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer, FactFailure}
  alias WeGoNext.Repo
  alias WeGoNext.Rules.Ruleset
  alias WeGoNext.Silver.{DamageTaken, PlayerInfo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)
    end)

    :ok
  end

  test "rebuilds active ruleset facts for all gold encounters from silver rows" do
    ruleset = insert_ruleset!("Active Ruleset", "active")
    first_encounter = insert_dim_encounter!("boss-one")
    second_encounter = insert_dim_encounter!("boss-two")

    first_criterion = insert_criterion!(ruleset, first_encounter, 101)
    second_criterion = insert_criterion!(ruleset, second_encounter, 202)

    insert_player_info!(first_encounter, "Player-One", "One")
    insert_player_info!(second_encounter, "Player-Two", "Two")
    insert_damage_taken!(first_encounter, "Player-One", 101, 100, 1)
    insert_damage_taken!(second_encounter, "Player-Two", 202, 200, 1)

    output = capture_task_output(fn -> RebuildGold.run([]) end)

    assert output =~ "Rebuilt gold.fact_failure for 2 encounter(s) using active ruleset."
    assert output =~ "inserted 2 fact row(s)."

    assert fact_exists?(first_encounter, "Player-One", first_criterion)
    assert fact_exists?(second_encounter, "Player-Two", second_criterion)
  end

  test "accepts explicit ruleset id and keeps active ruleset facts intact" do
    active_ruleset = insert_ruleset!("Active Ruleset", "active")
    draft_ruleset = insert_ruleset!("Draft Ruleset", "draft")
    encounter = insert_dim_encounter!("boss-one")

    active_criterion = insert_criterion!(active_ruleset, encounter, 303)
    draft_criterion = insert_criterion!(draft_ruleset, encounter, 303)

    insert_player_info!(encounter, "Player-One", "One")
    insert_damage_taken!(encounter, "Player-One", 303, 100, 1)

    RebuildGold.run([])
    assert fact_exists?(encounter, "Player-One", active_criterion)
    refute fact_exists?(encounter, "Player-One", draft_criterion)

    output =
      capture_task_output(fn -> RebuildGold.run(["--ruleset-id", "#{draft_ruleset.id}"]) end)

    assert output =~ "using ruleset_id=#{draft_ruleset.id}"
    assert fact_exists?(encounter, "Player-One", active_criterion)
    assert fact_exists?(encounter, "Player-One", draft_criterion)
  end

  test "can rebuild a single encounter" do
    ruleset = insert_ruleset!("Active Ruleset", "active")
    first_encounter = insert_dim_encounter!("boss-one")
    second_encounter = insert_dim_encounter!("boss-two")

    first_criterion = insert_criterion!(ruleset, first_encounter, 101)
    second_criterion = insert_criterion!(ruleset, second_encounter, 202)

    insert_player_info!(first_encounter, "Player-One", "One")
    insert_player_info!(second_encounter, "Player-Two", "Two")
    insert_damage_taken!(first_encounter, "Player-One", 101, 100, 1)
    insert_damage_taken!(second_encounter, "Player-Two", 202, 200, 1)

    output =
      capture_task_output(fn -> RebuildGold.run(["--encounter-id", "#{first_encounter.id}"]) end)

    assert output =~ "for 1 encounter(s)"
    assert fact_exists?(first_encounter, "Player-One", first_criterion)
    refute fact_exists?(second_encounter, "Player-Two", second_criterion)
  end

  defp capture_task_output(fun) do
    capture_io(fn ->
      fun.()
      flush_shell_messages()
    end)
  end

  defp flush_shell_messages do
    receive do
      {:mix_shell, :info, [message]} ->
        IO.puts(message)
        flush_shell_messages()
    after
      0 -> :ok
    end
  end

  defp fact_exists?(encounter, player_guid, criterion) do
    player = Repo.get_by(DimPlayer, player_guid: player_guid)
    encounter_id = encounter.id
    criterion_id = criterion.id

    player &&
      Repo.exists?(
        from(failure in FactFailure,
          where:
            failure.encounter_dim_id == ^encounter_id and
              failure.player_dim_id == ^player.id and
              failure.criterion_dim_id == ^criterion_id
        )
      )
  end

  defp insert_dim_encounter!(wow_encounter_id) do
    %DimEncounter{}
    |> DimEncounter.changeset(%{
      wow_encounter_id: wow_encounter_id,
      name: "Test Boss",
      difficulty_id: 16,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "test-instance"
    })
    |> Repo.insert!()
  end

  defp insert_ruleset!(name, status) do
    %Ruleset{}
    |> Ruleset.changeset(%{name: name, status: status})
    |> Repo.insert!()
  end

  defp insert_criterion!(%Ruleset{} = ruleset, %DimEncounter{} = encounter, spell_id) do
    %DimMechanicCriterion{}
    |> DimMechanicCriterion.changeset(%{
      source_rule_id: System.unique_integer([:positive]),
      ruleset_id: ruleset.id,
      ruleset_version: ruleset.version,
      spell_id: spell_id,
      spell_name: "Bad #{spell_id}",
      mechanic_type: "avoidable",
      boss_encounter_id: encounter.wow_encounter_id,
      difficulty_id: 16,
      threshold: %{"max_hits" => 0}
    })
    |> Repo.insert!()
  end

  defp insert_player_info!(encounter, player_guid, player_name) do
    %PlayerInfo{}
    |> PlayerInfo.changeset(%{
      encounter_dim_id: encounter.id,
      player_guid: player_guid,
      player_name: player_name,
      class_id: 1,
      spec_id: 71,
      detected_role: "unknown"
    })
    |> Repo.insert!()
  end

  defp insert_damage_taken!(encounter, player_guid, spell_id, total_amount, hit_count) do
    %DamageTaken{}
    |> DamageTaken.changeset(%{
      encounter_dim_id: encounter.id,
      target_guid: player_guid,
      source_guid: "Creature-A",
      spell_id: spell_id,
      total_amount: total_amount,
      hit_count: hit_count,
      max_hit: total_amount,
      overkill_total: 0,
      source_is_npc: true
    })
    |> Repo.insert!()
  end
end

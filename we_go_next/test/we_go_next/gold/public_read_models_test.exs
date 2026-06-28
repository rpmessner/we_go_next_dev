defmodule WeGoNext.Gold.PublicReadModelsTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer, FactFailure}
  alias WeGoNext.Gold.PublicReadModels
  alias WeGoNext.Repo
  alias WeGoNext.Rules.Ruleset

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "list_encounters returns gold-backed encounter aggregates" do
    old = insert_encounter!("old", ~U[2026-06-01 20:00:00Z])
    recent = insert_encounter!("recent", ~U[2026-06-02 20:00:00Z])
    player = insert_player!("Player-One", "One")
    criterion = insert_criterion!(101, "Swirl")

    insert_failure!(old, player, criterion, 1, 100)
    insert_failure!(recent, player, criterion, 3, 700)

    assert [
             %{
               source_encounter_key: recent_key,
               name: "Boss recent",
               failure_count: 3,
               total_damage: 700,
               failing_player_count: 1,
               criterion_count: 1
             },
             %{
               source_encounter_key: old_key,
               name: "Boss old",
               failure_count: 1,
               total_damage: 100
             }
           ] = PublicReadModels.list_encounters()

    assert recent_key == recent.source_encounter_key
    assert old_key == old.source_encounter_key
  end

  test "encounter_failures returns per-encounter player and criterion breakdown" do
    encounter = insert_encounter!("breakdown", ~U[2026-06-03 20:00:00Z])
    one = insert_player!("Player-One", "One")
    two = insert_player!("Player-Two", "Two")
    swirl = insert_criterion!(101, "Swirl")
    volley = insert_criterion!(202, "Shadow Volley", "interrupt")

    insert_failure!(encounter, one, swirl, 2, 500)
    insert_failure!(encounter, one, volley, 1, 0)
    insert_failure!(encounter, two, swirl, 4, 900)

    assert {:ok, breakdown} = PublicReadModels.encounter_failures(encounter.source_encounter_key)

    assert breakdown.encounter.source_encounter_key == encounter.source_encounter_key

    assert breakdown.counts == %{
             failure_count: 7,
             total_damage: 1_400,
             failing_player_count: 2,
             criterion_count: 2
           }

    assert [
             %{player_name: "One", failure_count: 3, total_damage: 500, failures: [_, _]},
             %{player_name: "Two", failure_count: 4, total_damage: 900, failures: [_]}
           ] = breakdown.player_groups

    assert Enum.map(breakdown.failures, & &1.spell_name) == ["Swirl", "Shadow Volley", "Swirl"]
  end

  test "encounter_failures returns not_found for unknown source encounter key" do
    assert {:error, :not_found} = PublicReadModels.encounter_failures("missing")
  end

  test "public read models query only mirrored gold tables" do
    encounter = insert_encounter!("gold-only", ~U[2026-06-04 20:00:00Z])
    player = insert_player!("Player-One", "One")
    criterion = insert_criterion!(101, "Swirl")
    insert_failure!(encounter, player, criterion, 1, 100)

    queries =
      capture_repo_queries(fn ->
        PublicReadModels.list_encounters()
        PublicReadModels.encounter_failures(encounter.source_encounter_key)
      end)

    assert Enum.any?(queries, &String.contains?(&1, ~s("gold"."dim_encounter")))
    assert Enum.any?(queries, &String.contains?(&1, ~s("gold"."fact_failure")))

    forbidden = [
      ~s("silver".),
      ~s("rules".),
      ~s("public".),
      ~s("users"),
      ~s("combat_log_files"),
      ~s("encounters")
    ]

    refute Enum.any?(queries, fn query ->
             Enum.any?(forbidden, &String.contains?(query, &1))
           end)
  end

  test "public read model source stays Accounts-free" do
    path = Path.expand("../../../lib/we_go_next/gold/public_read_models.ex", __DIR__)
    source = File.read!(path)

    refute source =~ "WeGoNext.Accounts"
    refute source =~ "Accounts."
  end

  defp capture_repo_queries(fun) do
    test_pid = self()
    handler_id = {__MODULE__, self(), System.unique_integer([:positive])}

    :telemetry.attach(
      handler_id,
      [:we_go_next, :repo, :query],
      fn _event, _measurements, metadata, _config ->
        send(test_pid, {:repo_query, metadata.query})
      end,
      nil
    )

    try do
      fun.()
      collect_queries([])
    after
      :telemetry.detach(handler_id)
    end
  end

  defp collect_queries(acc) do
    receive do
      {:repo_query, query} -> collect_queries([query | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp insert_encounter!(suffix, start_time) do
    %DimEncounter{}
    |> DimEncounter.changeset(%{
      source_head_sha256: String.duplicate("a", 64),
      wow_encounter_id: "boss-#{suffix}",
      name: "Boss #{suffix}",
      difficulty_id: 16,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "test-instance",
      start_time: start_time,
      end_time: DateTime.add(start_time, 300, :second),
      success: false,
      fight_time_ms: 300_000,
      start_byte: System.unique_integer([:positive]),
      end_byte: System.unique_integer([:positive]) + 1000
    })
    |> Repo.insert!()
  end

  defp insert_player!(guid, name) do
    %DimPlayer{}
    |> DimPlayer.changeset(%{player_guid: guid, player_name: name})
    |> Repo.insert!()
  end

  defp insert_criterion!(spell_id, spell_name, mechanic_type \\ "avoidable") do
    ruleset =
      %Ruleset{}
      |> Ruleset.changeset(%{name: "Public Read Model Rules #{System.unique_integer()}"})
      |> Repo.insert!()

    %DimMechanicCriterion{}
    |> DimMechanicCriterion.changeset(%{
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
      rebuilt_at: ~U[2026-06-04 21:00:00Z],
      failure_count: failure_count,
      total_damage: total_damage
    })
    |> Repo.insert!()
  end
end

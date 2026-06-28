defmodule WeGoNext.Mirror.OutboxTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer, FactFailure}
  alias WeGoNext.Mirror.{MirrorUpload, Outbox}
  alias WeGoNext.Repo
  alias WeGoNext.Rules.Ruleset

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "enqueue coalesces repeated publish intent as stale" do
    assert {:ok, %MirrorUpload{state: "pending"} = upload} = Outbox.enqueue("encounter-key")
    assert {:ok, %MirrorUpload{id: same_id, state: "stale"}} = Outbox.enqueue("encounter-key")

    assert same_id == upload.id
    assert Repo.aggregate(MirrorUpload, :count) == 1
  end

  test "process_pending publishes a bounded batch and marks rows published" do
    encounter = insert_snapshot_rows!("success-key")
    Outbox.enqueue(encounter.source_encounter_key)

    calls = :ets.new(:upload_calls, [:public])

    result =
      Outbox.process_pending(
        limit: 1,
        config: %{
          public_base_url: "https://public.example/",
          ingest_token: "secret",
          report_slug: "raid-night"
        },
        post_fun: fn url, snapshot, token ->
          :ets.insert(calls, {:call, url, snapshot.encounter.source_encounter_key, token})
          {:ok, %{status: 200, body: %{"status" => "ok"}}}
        end
      )

    assert result == %{published: 1, error: 0}

    assert [
             {:call, "https://public.example/api/reports/raid-night/ingest", "success-key",
              "secret"}
           ] =
             :ets.lookup(calls, :call)

    assert %MirrorUpload{state: "published", published_at: %DateTime{}, attempt_count: 1} =
             Repo.get_by!(MirrorUpload, source_encounter_key: "success-key")
  end

  test "process_pending records upload errors for retry" do
    encounter = insert_snapshot_rows!("error-key")
    Outbox.enqueue(encounter.source_encounter_key)

    result =
      Outbox.process_pending(
        config: %{
          public_base_url: "https://public.example",
          ingest_token: "secret",
          report_slug: "raid-night"
        },
        post_fun: fn _url, _snapshot, _token -> {:ok, %{status: 500, body: "nope"}} end
      )

    assert result == %{published: 0, error: 1}

    assert %MirrorUpload{state: "error", last_error: last_error, attempt_count: 1} =
             Repo.get_by!(MirrorUpload, source_encounter_key: "error-key")

    assert last_error =~ "http_error"
  end

  defp insert_snapshot_rows!(source_encounter_key) do
    encounter =
      %DimEncounter{}
      |> DimEncounter.changeset(%{
        source_encounter_key: source_encounter_key,
        wow_encounter_id: source_encounter_key,
        name: "Mirror Boss",
        start_time: ~U[2026-06-28 20:00:00Z]
      })
      |> Repo.insert!()

    player =
      %DimPlayer{}
      |> DimPlayer.changeset(%{player_guid: "Player-#{source_encounter_key}", player_name: "One"})
      |> Repo.insert!()

    ruleset =
      %Ruleset{}
      |> Ruleset.changeset(%{name: "Outbox Rules #{source_encounter_key}"})
      |> Repo.insert!()

    criterion =
      %DimMechanicCriterion{}
      |> DimMechanicCriterion.changeset(%{
        source_rule_id: System.unique_integer([:positive]),
        ruleset_id: ruleset.id,
        ruleset_version: ruleset.version,
        spell_id: System.unique_integer([:positive]),
        spell_name: "Bad",
        mechanic_type: "avoidable",
        threshold: %{"max_hits" => 0}
      })
      |> Repo.insert!()

    %FactFailure{}
    |> FactFailure.changeset(%{
      encounter_dim_id: encounter.id,
      player_dim_id: player.id,
      criterion_dim_id: criterion.id,
      ruleset_id: criterion.ruleset_id,
      ruleset_version: criterion.ruleset_version,
      product: criterion.product,
      channel: criterion.channel,
      failure_count: 1,
      total_damage: 100
    })
    |> Repo.insert!()

    encounter
  end
end

defmodule WeGoNext.Mirror.OutboxTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Mirror.{MirrorUpload, Outbox}
  alias WeGoNext.Repo

  alias WeGoNext.Support.{
    FailingDestinationDocumentStore,
    StubDestinationDocumentStore,
    StubSourceDocumentStore
  }

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    StubSourceDocumentStore.reset!()
    StubDestinationDocumentStore.reset!()

    :ok
  end

  test "enqueue coalesces repeated publish intent as stale" do
    assert {:ok, %MirrorUpload{state: "pending"} = upload} = Outbox.enqueue("encounter-key")
    assert {:ok, %MirrorUpload{id: same_id, state: "stale"}} = Outbox.enqueue("encounter-key")

    assert same_id == upload.id
    assert Repo.aggregate(MirrorUpload, :count) == 1
  end

  test "process_pending uploads a bounded batch and refreshes a public index of uploaded encounters" do
    put_source_document!("already-uploaded", ~U[2026-07-08 19:00:00Z])
    put_source_document!("pending-key", ~U[2026-07-08 20:00:00Z])
    put_source_document!("not-uploaded", ~U[2026-07-08 21:00:00Z])

    insert_upload!("already-uploaded", "published")
    Outbox.enqueue("pending-key")
    Outbox.enqueue("not-uploaded")

    result =
      Outbox.process_pending(
        limit: 1,
        max_concurrency: 2,
        source_store: StubSourceDocumentStore,
        destination_store: StubDestinationDocumentStore
      )

    assert result == %{published: 1, error: 0}

    assert %MirrorUpload{state: "published", published_at: %DateTime{}, attempt_count: 1} =
             Repo.get_by!(MirrorUpload, source_encounter_key: "pending-key")

    assert %MirrorUpload{state: "pending", attempt_count: 0} =
             Repo.get_by!(MirrorUpload, source_encounter_key: "not-uploaded")

    assert {:ok, pending_body} =
             StubDestinationDocumentStore.fetch("encounters/pending-key.json")

    assert Jason.decode!(pending_body)["source_encounter_key"] == "pending-key"

    assert {:ok, index_body} = StubDestinationDocumentStore.fetch("index.json")
    index = Jason.decode!(index_body)

    assert Enum.map(index["encounters"], & &1["source_encounter_key"]) == [
             "pending-key",
             "already-uploaded"
           ]
  end

  test "process_pending keeps all concurrently uploaded encounters in the public index" do
    put_source_document!("first-key", ~U[2026-07-08 20:00:00Z])
    put_source_document!("second-key", ~U[2026-07-08 20:05:00Z])

    Outbox.enqueue("first-key")
    Outbox.enqueue("second-key")

    assert %{published: 2, error: 0} =
             Outbox.process_pending(
               limit: 2,
               max_concurrency: 2,
               source_store: StubSourceDocumentStore,
               destination_store: StubDestinationDocumentStore
             )

    assert {:ok, index_body} = StubDestinationDocumentStore.fetch("index.json")

    assert Enum.map(Jason.decode!(index_body)["encounters"], & &1["source_encounter_key"]) == [
             "second-key",
             "first-key"
           ]
  end

  test "process_pending marks rows error when the public index refresh fails" do
    put_source_document!("error-key", ~U[2026-07-08 20:00:00Z])
    Outbox.enqueue("error-key")

    result =
      Outbox.process_pending(
        limit: 1,
        source_store: StubSourceDocumentStore,
        destination_store: FailingDestinationDocumentStore
      )

    assert result == %{published: 0, error: 1}

    assert %MirrorUpload{state: "error", last_error: last_error, attempt_count: 1} =
             Repo.get_by!(MirrorUpload, source_encounter_key: "error-key")

    assert last_error =~ "index_failed"
    assert {:ok, _body} = StubDestinationDocumentStore.fetch("encounters/error-key.json")
    assert {:error, :enoent} = StubDestinationDocumentStore.fetch("index.json")
  end

  defp put_source_document!(source_encounter_key, start_time) do
    document = document(source_encounter_key, start_time)

    StubSourceDocumentStore.put(
      "encounters/#{source_encounter_key}.json",
      Jason.encode!(document)
    )
  end

  defp document(source_encounter_key, start_time) do
    %{
      schema_version: 1,
      generated_at: "2026-07-08T20:10:00Z",
      derivation_version: "test",
      source_encounter_key: source_encounter_key,
      encounter: %{
        id: System.unique_integer([:positive]),
        source_encounter_key: source_encounter_key,
        wow_encounter_id: "fixture-boss",
        name: "Fixture Boss #{source_encounter_key}",
        difficulty_id: 16,
        difficulty_name: "Mythic",
        group_size: 20,
        instance_id: "fixture-instance",
        start_time: start_time,
        end_time: DateTime.add(start_time, 300, :second),
        success: false,
        fight_time_ms: 300_000,
        operator: %{}
      },
      counts: %{players: 1, deaths: 0, interrupt_opportunities: 0, operator: %{}},
      roster: [],
      deaths: [],
      pull_review: %{damage_done: [], low_dps: [], damage_taken_spells: [], debuffs: %{all: []}},
      failure_preview: %{counts: %{mechanics: 0, players: 0, failures: 0, damage: 0}},
      interrupt_coverage: %{spell_coverage: [], player_contributions: []},
      personal_pull_summary: %{players: []},
      observed_mechanics: %{mechanics: []}
    }
  end

  defp insert_upload!(source_encounter_key, state) do
    %MirrorUpload{}
    |> MirrorUpload.changeset(%{
      source_encounter_key: source_encounter_key,
      state: state,
      published_at: if(state == "published", do: DateTime.utc_now(), else: nil)
    })
    |> Repo.insert!()
  end
end

defmodule WeGoNext.Documents.UploadWorkerTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Application
  alias WeGoNext.Documents.UploadWorker
  alias WeGoNext.Mirror.{MirrorUpload, Outbox}
  alias WeGoNext.Repo
  alias WeGoNext.Support.{StubDestinationDocumentStore, StubSourceDocumentStore}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    StubSourceDocumentStore.reset!()
    StubDestinationDocumentStore.reset!()

    :ok
  end

  test "is supervised only in parser mode" do
    assert Application.children(:parser)
           |> Enum.any?(&(&1 == WeGoNext.Documents.UploadWorker))

    refute Application.children(:public)
           |> Enum.any?(&(&1 == WeGoNext.Documents.UploadWorker))
  end

  test "drain_once publishes pending outbox rows without sleeping" do
    put_source_document!("worker-key")
    Outbox.enqueue("worker-key")

    worker =
      start_supervised!(
        {UploadWorker,
         name: __MODULE__.Worker,
         interval_ms: false,
         limit: 2,
         max_concurrency: 1,
         outbox_opts: [
           source_store: StubSourceDocumentStore,
           destination_store: StubDestinationDocumentStore
         ]}
      )

    assert %{published: 1, error: 0} = UploadWorker.drain_once(worker)

    assert %MirrorUpload{state: "published", attempt_count: 1} =
             Repo.get_by!(MirrorUpload, source_encounter_key: "worker-key")

    assert {:ok, _body} = StubDestinationDocumentStore.fetch("encounters/worker-key.json")
    assert {:ok, index_body} = StubDestinationDocumentStore.fetch("index.json")

    assert [%{"source_encounter_key" => "worker-key"}] = Jason.decode!(index_body)["encounters"]
  end

  defp put_source_document!(source_encounter_key) do
    document = %{
      schema_version: 1,
      generated_at: "2026-07-08T20:10:00Z",
      derivation_version: "test",
      source_encounter_key: source_encounter_key,
      encounter: %{
        id: System.unique_integer([:positive]),
        source_encounter_key: source_encounter_key,
        wow_encounter_id: "fixture-boss",
        name: "Worker Fixture Boss",
        difficulty_id: 16,
        difficulty_name: "Mythic",
        group_size: 20,
        instance_id: "fixture-instance",
        start_time: "2026-07-08T20:00:00Z",
        end_time: "2026-07-08T20:05:00Z",
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

    StubSourceDocumentStore.put(
      "encounters/#{source_encounter_key}.json",
      Jason.encode!(document)
    )
  end
end

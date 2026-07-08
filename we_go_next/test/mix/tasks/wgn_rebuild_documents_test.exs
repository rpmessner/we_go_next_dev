defmodule Mix.Tasks.Wgn.RebuildDocumentsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Wgn.RebuildDocuments
  alias WeGoNext.Gold.DimEncounter
  alias WeGoNext.Repo
  alias WeGoNext.Silver.PlayerInfo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Mix.shell(Mix.Shell.Process)

    original_documents_root = Application.fetch_env!(:we_go_next, :documents_root)

    documents_root =
      Path.join(System.tmp_dir!(), "wgn-documents-#{System.unique_integer([:positive])}")

    Application.put_env(:we_go_next, :documents_root, documents_root)

    on_exit(fn ->
      Application.put_env(:we_go_next, :documents_root, original_documents_root)
      File.rm_rf(documents_root)
      Mix.shell(Mix.Shell.IO)
    end)

    {:ok, documents_root: documents_root}
  end

  test "backfills encounter documents and index", %{documents_root: documents_root} do
    encounter = insert_encounter!("task-boss")
    insert_player_info!(encounter, "Player-One", "One")

    output = capture_task_output(fn -> RebuildDocuments.run([]) end)

    assert output =~ "Rebuilt encounter documents for 1 pull(s)."

    encounter_path =
      Path.join([documents_root, "encounters", "#{encounter.source_encounter_key}.json"])

    index_path = Path.join(documents_root, "index.json")

    assert File.exists?(encounter_path)
    assert File.exists?(index_path)

    assert encounter_path |> File.read!() |> Jason.decode!() |> Map.fetch!("source_encounter_key") ==
             encounter.source_encounter_key

    assert [index_entry] =
             index_path |> File.read!() |> Jason.decode!() |> Map.fetch!("encounters")

    assert index_entry["source_encounter_key"] == encounter.source_encounter_key
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

  defp insert_encounter!(wow_encounter_id) do
    source_start_byte = System.unique_integer([:positive])

    %DimEncounter{}
    |> DimEncounter.changeset(%{
      source_head_sha256: String.duplicate("d", 64),
      wow_encounter_id: wow_encounter_id,
      name: "Task Boss",
      difficulty_id: 16,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "task-instance",
      start_time: ~U[2026-07-08 12:00:00Z],
      end_time: ~U[2026-07-08 12:05:00Z],
      success: false,
      fight_time_ms: 300_000,
      start_byte: source_start_byte,
      end_byte: source_start_byte + 1000
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
      detected_role: "dps"
    })
    |> Repo.insert!()
  end
end

defmodule WeGoNext.ImporterTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Accounts.User
  alias WeGoNext.{CombatLogFile, Importer, Repo}
  alias WeGoNext.Encounters.Encounter, as: EncounterRecord

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    dir = Path.join(System.tmp_dir!(), "wgn-importer-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    user =
      Repo.insert!(%User{
        name: "user-#{System.unique_integer([:positive])}",
        wow_logs_path: dir
      })

    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, dir: dir, user: user}
  end

  test "sync_log fetches existing duplicate encounters without counting them as new", %{
    dir: dir,
    user: user
  } do
    source_path = Path.expand("../fixtures/WoWCombatLog-112725_120000.txt", __DIR__)
    log_path = Path.join(dir, "WoWCombatLog-112725_120000.txt")
    File.cp!(source_path, log_path)

    combat_log_file =
      insert_combat_log_file!(%{
        file_path: log_path,
        file_size: 0,
        user_id: user.id
      })

    existing =
      insert_encounter!(%{
        combat_log_file_id: combat_log_file.id,
        start_time: ~U[2025-11-27 12:00:01.000000Z],
        analysis: %{"source" => "existing"}
      })

    assert {:ok, %{new_encounters: 0}} = Importer.sync_log(combat_log_file)

    assert Repo.aggregate(EncounterRecord, :count) == 1

    persisted = Repo.get!(EncounterRecord, existing.id)
    assert persisted.analysis == %{"source" => "existing"}
    assert persisted.end_byte == existing.end_byte
  end

  defp insert_combat_log_file!(attrs) do
    attrs =
      Map.merge(
        %{
          file_size: 0,
          file_mtime: DateTime.utc_now() |> DateTime.truncate(:second),
          last_parsed_byte: 0,
          source: :live
        },
        attrs
      )

    %CombatLogFile{}
    |> CombatLogFile.changeset(attrs)
    |> Repo.insert!()
  end

  defp insert_encounter!(attrs) do
    attrs =
      Map.merge(
        %{
          wow_encounter_id: "2887",
          name: "Test Boss",
          difficulty_id: 15,
          difficulty_name: "Heroic",
          group_size: 20,
          instance_id: "2652",
          end_time: ~U[2025-11-27 12:00:45.000000Z],
          success: false,
          fight_time_ms: 44_000,
          start_byte: 240,
          end_byte: 2_569,
          is_reset: false,
          analysis: %{}
        },
        attrs
      )

    %EncounterRecord{}
    |> EncounterRecord.changeset(attrs)
    |> Repo.insert!()
  end
end

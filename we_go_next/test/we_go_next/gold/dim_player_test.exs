defmodule WeGoNext.Gold.DimPlayerTest do
  use ExUnit.Case, async: false
  import Ecto.Query

  alias WeGoNext.Accounts.User
  alias WeGoNext.CombatLogFile
  alias WeGoNext.Encounters.Encounter
  alias WeGoNext.Gold.DimPlayer
  alias WeGoNext.Repo
  alias WeGoNext.Silver.PlayerInfo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    dir =
      Path.join(System.tmp_dir!(), "wgn-gold-dim-player-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    user =
      Repo.insert!(%User{
        name: "user-#{System.unique_integer([:positive])}",
        wow_logs_path: dir
      })

    combat_log_file = insert_combat_log_file!(dir, user)
    encounter = insert_encounter!(combat_log_file, 0)
    other_encounter = insert_encounter!(combat_log_file, 1)

    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, encounter: encounter, other_encounter: other_encounter}
  end

  test "upsert_from_silver inserts player dimension rows for the encounter", %{
    encounter: encounter
  } do
    insert_player_info!(encounter, "Player-Tank", "Tank", 1, 73)
    insert_player_info!(encounter, "Player-Healer", "Healer", 5, 257)

    assert {2, nil} = DimPlayer.upsert_from_silver(encounter.id)

    assert %DimPlayer{player_name: "Tank", class_id: 1, spec_id: 73} =
             Repo.get_by!(DimPlayer, player_guid: "Player-Tank")

    assert %DimPlayer{player_name: "Healer", class_id: 5, spec_id: 257} =
             Repo.get_by!(DimPlayer, player_guid: "Player-Healer")
  end

  test "upsert_from_silver updates existing rows by player_guid with Type 1 behavior", %{
    encounter: encounter
  } do
    player_info = insert_player_info!(encounter, "Player-One", "Oldname", 1, 71)

    assert {1, nil} = DimPlayer.upsert_from_silver(encounter.id)

    player_info
    |> PlayerInfo.changeset(%{player_name: "Newname", class_id: 2, spec_id: 65})
    |> Repo.update!()

    assert {1, nil} = DimPlayer.upsert_from_silver(encounter.id)

    assert Repo.aggregate(
             from(player in DimPlayer, where: player.player_guid == "Player-One"),
             :count
           ) == 1

    assert %DimPlayer{player_name: "Newname", class_id: 2, spec_id: 65} =
             Repo.get_by!(DimPlayer, player_guid: "Player-One")
  end

  test "upsert_from_silver only reads player info for the requested encounter", %{
    encounter: encounter,
    other_encounter: other_encounter
  } do
    insert_player_info!(encounter, "Player-In-Scope", "Inscope", 3, 102)
    insert_player_info!(other_encounter, "Player-Out-Of-Scope", "Outscope", 4, 253)

    assert {1, nil} = DimPlayer.upsert_from_silver(encounter.id)

    assert Repo.get_by(DimPlayer, player_guid: "Player-In-Scope")
    refute Repo.get_by(DimPlayer, player_guid: "Player-Out-Of-Scope")
  end

  defp insert_combat_log_file!(dir, user) do
    file_path = Path.join(dir, "WoWCombatLog-test.txt")
    File.write!(file_path, "COMBAT_LOG_VERSION,22\n")

    %CombatLogFile{}
    |> CombatLogFile.changeset(%{
      file_path: file_path,
      file_size: 22,
      file_mtime: DateTime.utc_now() |> DateTime.truncate(:second),
      source: :live,
      user_id: user.id,
      last_parsed_byte: 0
    })
    |> Repo.insert!()
  end

  defp insert_encounter!(combat_log_file, offset_seconds) do
    start_time = DateTime.utc_now() |> DateTime.add(offset_seconds, :second)

    %Encounter{}
    |> Encounter.changeset(%{
      wow_encounter_id: "test-boss-#{System.unique_integer([:positive])}",
      name: "Test Boss",
      difficulty_id: 16,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "test-instance",
      start_time: start_time,
      end_time: DateTime.add(start_time, 120, :second),
      success: false,
      fight_time_ms: 120_000,
      start_byte: 0,
      end_byte: 1_000,
      combat_log_file_id: combat_log_file.id,
      analysis: %{}
    })
    |> Repo.insert!()
  end

  defp insert_player_info!(encounter, player_guid, player_name, class_id, spec_id) do
    %PlayerInfo{}
    |> PlayerInfo.changeset(%{
      encounter_id: encounter.id,
      player_guid: player_guid,
      player_name: player_name,
      class_id: class_id,
      spec_id: spec_id,
      detected_role: "unknown"
    })
    |> Repo.insert!()
  end
end

defmodule WeGoNext.Gold.DimPlayerTest do
  use ExUnit.Case, async: false
  import Ecto.Query

  alias WeGoNext.Gold.{DimEncounter, DimPlayer}
  alias WeGoNext.Repo
  alias WeGoNext.Silver.PlayerInfo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    dim_encounter = insert_dim_encounter!("boss-one")
    other_dim_encounter = insert_dim_encounter!("boss-two")

    {:ok, dim_encounter: dim_encounter, other_dim_encounter: other_dim_encounter}
  end

  test "upsert_from_silver inserts player dimension rows for the encounter", %{
    dim_encounter: dim_encounter
  } do
    insert_player_info!(dim_encounter, "Player-Tank", "Tank", 1, 73)
    insert_player_info!(dim_encounter, "Player-Healer", "Healer", 5, 257)

    assert {2, nil} = DimPlayer.upsert_from_silver(dim_encounter.id)

    assert %DimPlayer{player_name: "Tank", class_id: 1, spec_id: 73} =
             Repo.get_by!(DimPlayer, player_guid: "Player-Tank")

    assert %DimPlayer{player_name: "Healer", class_id: 5, spec_id: 257} =
             Repo.get_by!(DimPlayer, player_guid: "Player-Healer")
  end

  test "upsert_from_silver updates existing rows by player_guid with Type 1 behavior", %{
    dim_encounter: dim_encounter
  } do
    player_info = insert_player_info!(dim_encounter, "Player-One", "Oldname", 1, 71)

    assert {1, nil} = DimPlayer.upsert_from_silver(dim_encounter.id)

    player_info
    |> PlayerInfo.changeset(%{player_name: "Newname", class_id: 2, spec_id: 65})
    |> Repo.update!()

    assert {1, nil} = DimPlayer.upsert_from_silver(dim_encounter.id)

    assert Repo.aggregate(
             from(player in DimPlayer, where: player.player_guid == "Player-One"),
             :count
           ) == 1

    assert %DimPlayer{player_name: "Newname", class_id: 2, spec_id: 65} =
             Repo.get_by!(DimPlayer, player_guid: "Player-One")
  end

  test "upsert_from_silver only reads player info for the requested encounter", %{
    dim_encounter: dim_encounter,
    other_dim_encounter: other_dim_encounter
  } do
    insert_player_info!(dim_encounter, "Player-In-Scope", "Inscope", 3, 102)
    insert_player_info!(other_dim_encounter, "Player-Out-Of-Scope", "Outscope", 4, 253)

    assert {1, nil} = DimPlayer.upsert_from_silver(dim_encounter.id)

    assert Repo.get_by(DimPlayer, player_guid: "Player-In-Scope")
    refute Repo.get_by(DimPlayer, player_guid: "Player-Out-Of-Scope")
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

  defp insert_player_info!(dim_encounter, player_guid, player_name, class_id, spec_id) do
    %PlayerInfo{}
    |> PlayerInfo.changeset(%{
      encounter_dim_id: dim_encounter.id,
      player_guid: player_guid,
      player_name: player_name,
      class_id: class_id,
      spec_id: spec_id,
      detected_role: "unknown"
    })
    |> Repo.insert!()
  end
end

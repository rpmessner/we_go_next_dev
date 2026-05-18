defmodule WeGoNext.Gold.EncounterIdentityTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Accounts.User
  alias WeGoNext.{CombatLogFile, Repo}
  alias WeGoNext.Encounters.Encounter, as: EncounterRecord
  alias WeGoNext.Gold.{DimEncounter, EncounterIdentity}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    user =
      Repo.insert!(%User{
        name: "identity-user-#{System.unique_integer([:positive])}"
      })

    combat_log_file =
      %CombatLogFile{}
      |> CombatLogFile.changeset(%{
        user_id: user.id,
        file_path: "/tmp/WoWCombatLog-identity.txt",
        source: :live,
        head_sha256: String.duplicate("a", 64)
      })
      |> Repo.insert!()

    {:ok, combat_log_file: combat_log_file}
  end

  test "bridges public encounter records to gold encounter ids by source fingerprint and start byte",
       %{combat_log_file: combat_log_file} do
    public_encounter = insert_public_encounter!(combat_log_file, 1_000)
    dim_encounter = insert_dim_encounter!(combat_log_file, 1_000)
    _other_dim_encounter = insert_dim_encounter!(combat_log_file, 2_000)

    assert %DimEncounter{id: dim_id} =
             EncounterIdentity.fetch_for_public_encounter(public_encounter, combat_log_file)

    assert dim_id == dim_encounter.id

    assert [%EncounterRecord{dim_encounter_id: ^dim_id}] =
             EncounterIdentity.attach_dim_encounter_ids([public_encounter], combat_log_file)
  end

  test "falls back to source file path when no fingerprint is available", %{
    combat_log_file: combat_log_file
  } do
    {:ok, combat_log_file} =
      combat_log_file
      |> Ecto.Changeset.change(head_sha256: nil)
      |> Repo.update()

    public_encounter = insert_public_encounter!(combat_log_file, 3_000)
    dim_encounter = insert_dim_encounter!(combat_log_file, 3_000)

    assert %DimEncounter{id: dim_id} =
             EncounterIdentity.fetch_for_public_encounter(public_encounter, combat_log_file)

    assert dim_id == dim_encounter.id
  end

  defp insert_public_encounter!(%CombatLogFile{} = combat_log_file, start_byte) do
    %EncounterRecord{}
    |> EncounterRecord.changeset(%{
      combat_log_file_id: combat_log_file.id,
      wow_encounter_id: "2887",
      name: "Plexus Sentinel",
      difficulty_id: 16,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "2652",
      start_time: ~U[2026-05-01 20:00:00Z],
      end_time: ~U[2026-05-01 20:05:00Z],
      success: false,
      fight_time_ms: 300_000,
      start_byte: start_byte,
      end_byte: start_byte + 500
    })
    |> Repo.insert!()
  end

  defp insert_dim_encounter!(%CombatLogFile{} = combat_log_file, start_byte) do
    %DimEncounter{}
    |> DimEncounter.changeset(%{
      source_file_path: combat_log_file.file_path,
      source_head_sha256: combat_log_file.head_sha256,
      wow_encounter_id: "2887",
      name: "Plexus Sentinel",
      difficulty_id: 16,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "2652",
      start_time: ~U[2026-05-01 20:00:00Z],
      end_time: ~U[2026-05-01 20:05:00Z],
      success: false,
      fight_time_ms: 300_000,
      start_byte: start_byte,
      end_byte: start_byte + 500
    })
    |> Repo.insert!()
  end
end

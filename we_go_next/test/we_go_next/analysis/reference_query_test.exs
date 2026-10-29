defmodule WeGoNext.Analysis.ReferenceQueryTest do
  use WeGoNext.DataCase, async: false

  alias WeGoNext.{CombatLogFile, Repo}
  alias WeGoNext.Gold.DimEncounter
  alias WeGoNext.Silver.{DamageTaken, Death, PlayerInfo}

  test "snapshot query scopes log 30 and preserves deaths and player-spell hit sums" do
    user = Repo.insert!(%WeGoNext.Accounts.User{name: "reference-fixture"})

    Repo.insert!(%CombatLogFile{
      id: 30,
      user_id: user.id,
      file_path: "/reference-fixture.txt",
      head_sha256: "fixture-hash"
    })

    dim =
      Repo.insert!(%DimEncounter{
        source_head_sha256: "fixture-hash",
        source_encounter_key: "reference-fixture",
        name: "Sszorak",
        wow_encounter_id: "3420",
        start_time: ~U[2026-09-06 15:00:00.000000Z],
        fight_time_ms: 5_000
      })

    Repo.insert!(%DimEncounter{
      source_head_sha256: "other-hash",
      source_encounter_key: "not-reference",
      name: "Sszorak",
      wow_encounter_id: "3420"
    })

    Repo.insert!(%PlayerInfo{
      encounter_dim_id: dim.id,
      player_guid: "Player-A",
      player_name: "A",
      detected_role: "dps"
    })

    Repo.insert!(%Death{
      encounter_dim_id: dim.id,
      target_guid: "Player-A",
      died_at_ms_into_fight: 2_500,
      killing_blow_spell_id: 9,
      damage_recap: [%{"spell_id" => 9, "amount" => 100}]
    })

    for {source, hits, amount} <- [{"Creature-A", 3, 100}, {"Creature-B", 5, 200}] do
      Repo.insert!(%DamageTaken{
        encounter_dim_id: dim.id,
        target_guid: "Player-A",
        source_guid: source,
        spell_id: 9,
        hit_count: hits,
        total_amount: amount
      })
    end

    query =
      __DIR__
      |> Path.join("../../../../scripts/analysis-reference.sql")
      |> File.read!()
      |> String.split(";", trim: true)
      |> Enum.at(1)

    assert %{rows: [[snapshot]]} = Repo.query!(query)
    assert [%{"id" => id, "pull_number" => 1}] = snapshot["pulls"]
    assert id == dim.id
    assert [%{"guid" => "Player-A", "hits" => 8, "amount" => 300}] = snapshot["damage"]
    assert [%{"ms" => 2_500, "spell" => 9}] = snapshot["deaths"]
    assert [%{"name" => "A"}] = snapshot["players"]
  end
end

defmodule WeGoNext.Gold.SchemaTest do
  use ExUnit.Case, async: true

  alias WeGoNext.Criteria.MechanicCriteria
  alias WeGoNext.Encounters.Encounter
  alias WeGoNext.Gold.{DimPlayer, FactFailure}

  test "gold schemas use dedicated schema prefix and expected table names" do
    assert DimPlayer.__schema__(:prefix) == "gold"
    assert DimPlayer.__schema__(:source) == "dim_player"

    assert FactFailure.__schema__(:prefix) == "gold"
    assert FactFailure.__schema__(:source) == "fact_failure"
    assert FactFailure.__schema__(:primary_key) == [:encounter_id, :player_dim_id, :criterion_id]
  end

  test "fact failure associations match gold fact grain" do
    assert FactFailure.__schema__(:association, :encounter).related == Encounter
    assert FactFailure.__schema__(:association, :player).related == DimPlayer
    assert FactFailure.__schema__(:association, :criterion).related == MechanicCriteria
  end

  test "gold changesets accept required fields" do
    dim_player_changeset =
      DimPlayer.changeset(%DimPlayer{}, %{
        player_guid: "Player-1",
        player_name: "Testplayer",
        class_id: 1,
        spec_id: 71
      })

    assert dim_player_changeset.valid?, inspect(dim_player_changeset.errors)

    fact_failure_changeset =
      FactFailure.changeset(%FactFailure{}, %{
        encounter_id: 1,
        player_dim_id: 1,
        criterion_id: 1,
        failure_count: 2,
        total_damage: 12_345
      })

    assert fact_failure_changeset.valid?, inspect(fact_failure_changeset.errors)
  end
end

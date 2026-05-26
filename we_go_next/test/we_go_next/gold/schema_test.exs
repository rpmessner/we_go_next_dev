defmodule WeGoNext.Gold.SchemaTest do
  use ExUnit.Case, async: true

  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer, FactFailure}

  test "gold schemas use dedicated schema prefix and expected table names" do
    assert DimPlayer.__schema__(:prefix) == "gold"
    assert DimPlayer.__schema__(:source) == "dim_player"

    assert DimEncounter.__schema__(:prefix) == "gold"
    assert DimEncounter.__schema__(:source) == "dim_encounter"

    assert DimMechanicCriterion.__schema__(:prefix) == "gold"
    assert DimMechanicCriterion.__schema__(:source) == "dim_mechanic_criterion"

    assert FactFailure.__schema__(:prefix) == "gold"
    assert FactFailure.__schema__(:source) == "fact_failure"

    assert FactFailure.__schema__(:primary_key) == [
             :encounter_dim_id,
             :player_dim_id,
             :criterion_dim_id
           ]
  end

  test "fact failure associations match gold fact grain" do
    assert FactFailure.__schema__(:association, :encounter).related == DimEncounter
    assert FactFailure.__schema__(:association, :player).related == DimPlayer
    assert FactFailure.__schema__(:association, :criterion).related == DimMechanicCriterion
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

    dim_encounter_changeset =
      DimEncounter.changeset(%DimEncounter{}, %{
        wow_encounter_id: "boss-1",
        name: "Test Boss",
        difficulty_id: 16
      })

    assert dim_encounter_changeset.valid?, inspect(dim_encounter_changeset.errors)

    dim_criterion_changeset =
      DimMechanicCriterion.changeset(%DimMechanicCriterion{}, %{
        source_rule_id: 1,
        ruleset_id: 1,
        ruleset_version: 1,
        product: "wow",
        channel: "retail",
        spell_id: 123,
        spell_name: "Bad",
        mechanic_type: "avoidable",
        threshold: %{"max_hits" => 0},
        active: true
      })

    assert dim_criterion_changeset.valid?, inspect(dim_criterion_changeset.errors)

    fact_failure_changeset =
      FactFailure.changeset(%FactFailure{}, %{
        encounter_dim_id: 1,
        player_dim_id: 1,
        criterion_dim_id: 1,
        ruleset_id: 1,
        ruleset_version: 1,
        product: "wow",
        channel: "retail",
        derivation_version: 1,
        rebuilt_at: ~U[2026-05-20 20:00:00Z],
        failure_count: 2,
        total_damage: 12_345
      })

    assert fact_failure_changeset.valid?, inspect(fact_failure_changeset.errors)
  end
end

defmodule WeGoNext.RulesTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Repo
  alias WeGoNext.Rules
  alias WeGoNext.Rules.{MechanicCriterion, Ruleset}
  import Ecto.Query

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "rules schemas live in the rules prefix" do
    assert Ruleset.__schema__(:prefix) == "rules"
    assert Ruleset.__schema__(:source) == "ruleset"

    assert MechanicCriterion.__schema__(:prefix) == "rules"
    assert MechanicCriterion.__schema__(:source) == "mechanic_criterion"
    assert MechanicCriterion.__schema__(:association, :ruleset).related == Ruleset
  end

  test "activating a ruleset archives the previously active ruleset" do
    {:ok, first} = Rules.create_ruleset(%{name: "Season 1", version: 1})
    {:ok, second} = Rules.create_ruleset(%{name: "Season 1 Patch 2", version: 2})

    assert {:ok, active_first} = Rules.activate_ruleset(first)
    assert active_first.status == "active"
    assert active_first.activated_at
    assert active_first.archived_at == nil

    assert {:ok, active_second} = Rules.activate_ruleset(second)
    assert active_second.status == "active"
    assert active_second.activated_at
    assert active_second.archived_at == nil

    archived_first = Rules.get_ruleset!(first.id)
    assert archived_first.status == "archived"
    assert archived_first.archived_at

    assert Rules.get_active_ruleset().id == second.id
  end

  test "database allows only one active ruleset" do
    {:ok, first} = Rules.create_ruleset(%{name: "Active One", status: "active", version: 1})
    assert first.status == "active"

    assert {:error, changeset} =
             Rules.create_ruleset(%{name: "Active Two", status: "active", version: 1})

    assert {"has already been taken", _} = changeset.errors[:status]
  end

  test "creates mechanic criteria as authored rules scoped to a ruleset" do
    {:ok, ruleset} = Rules.create_ruleset(%{name: "Draft Rules"})

    assert {:ok, criterion} =
             Rules.create_mechanic_criterion(%{
               ruleset_id: ruleset.id,
               spell_id: 123,
               spell_name: "Avoid This",
               mechanic_type: "avoidable",
               threshold: %{"max_hits" => 0}
             })

    assert criterion.ruleset_id == ruleset.id
    assert criterion.active == true
    assert Rules.list_mechanic_criteria(ruleset) == [criterion]
  end

  test "mechanic criterion uniqueness treats null boss and difficulty as scoped values" do
    {:ok, ruleset} = Rules.create_ruleset(%{name: "Draft Rules"})

    attrs = %{
      ruleset_id: ruleset.id,
      spell_id: 123,
      spell_name: "Avoid This",
      mechanic_type: "avoidable",
      threshold: %{"max_hits" => 0}
    }

    assert {:ok, _criterion} = Rules.create_mechanic_criterion(attrs)

    assert {:error, changeset} = Rules.create_mechanic_criterion(attrs)

    assert {"has already been taken", _} =
             changeset.errors[:ruleset_id]

    assert {:ok, _boss_specific} =
             attrs
             |> Map.merge(%{
               boss_encounter_id: "boss-one",
               boss_name: "Boss One"
             })
             |> Rules.create_mechanic_criterion()

    assert {:ok, _difficulty_specific} =
             attrs
             |> Map.merge(%{
               boss_encounter_id: "boss-one",
               boss_name: "Boss One",
               difficulty_id: 16
             })
             |> Rules.create_mechanic_criterion()
  end

  test "avoidable thresholds require max_hits as a non-negative integer" do
    {:ok, ruleset} = Rules.create_ruleset(%{name: "Draft Rules"})
    attrs = criterion_attrs(ruleset, %{mechanic_type: "avoidable"})

    assert {:error, changeset} = Rules.create_mechanic_criterion(attrs)

    assert {"must contain only max_hits as a non-negative integer", _} =
             changeset.errors[:threshold]

    assert {:error, changeset} =
             attrs
             |> Map.put(:threshold, %{"max_hits" => -1})
             |> Rules.create_mechanic_criterion()

    assert {"must contain only max_hits as a non-negative integer", _} =
             changeset.errors[:threshold]

    assert {:error, changeset} =
             attrs
             |> Map.put(:threshold, %{"max_hits" => "0"})
             |> Rules.create_mechanic_criterion()

    assert {"must contain only max_hits as a non-negative integer", _} =
             changeset.errors[:threshold]

    assert {:ok, criterion} =
             attrs
             |> Map.put(:threshold, %{"max_hits" => 0})
             |> Rules.create_mechanic_criterion()

    assert criterion.threshold == %{"max_hits" => 0}
  end

  test "interrupt thresholds default must_interrupt to true and require a boolean" do
    {:ok, ruleset} = Rules.create_ruleset(%{name: "Draft Rules"})

    assert {:ok, criterion} =
             ruleset
             |> criterion_attrs(%{mechanic_type: "interrupt", spell_id: 321})
             |> Rules.create_mechanic_criterion()

    assert criterion.threshold == %{"must_interrupt" => true}

    assert {:error, changeset} =
             ruleset
             |> criterion_attrs(%{
               mechanic_type: "interrupt",
               spell_id: 322,
               threshold: %{"must_interrupt" => "true"}
             })
             |> Rules.create_mechanic_criterion()

    assert {"must contain only must_interrupt as a boolean", _} = changeset.errors[:threshold]
  end

  test "mechanic types without fact semantics require an empty threshold" do
    {:ok, ruleset} = Rules.create_ruleset(%{name: "Draft Rules"})

    assert {:ok, criterion} =
             ruleset
             |> criterion_attrs(%{mechanic_type: "soak", spell_id: 456})
             |> Rules.create_mechanic_criterion()

    assert criterion.threshold == %{}

    assert {:error, changeset} =
             ruleset
             |> criterion_attrs(%{
               mechanic_type: "soak",
               spell_id: 457,
               threshold: %{"players" => 3}
             })
             |> Rules.create_mechanic_criterion()

    assert {"must be empty until this mechanic type has fact semantics", _} =
             changeset.errors[:threshold]
  end

  test "seed_rules_from_file idempotently creates and updates rules from static JSON" do
    path = Path.join(System.tmp_dir!(), "wgn-rules-#{System.unique_integer([:positive])}.json")

    payload = %{
      "ruleset" => %{
        "name" => "Seeded Rules",
        "version" => 1,
        "status" => "draft"
      },
      "criteria" => [
        %{
          "spell_id" => 111,
          "spell_name" => "Seeded Avoid",
          "mechanic_type" => "avoidable",
          "threshold" => %{"max_hits" => 0}
        },
        %{
          "spell_id" => 222,
          "spell_name" => "Seeded Interrupt",
          "mechanic_type" => "interrupt"
        }
      ]
    }

    File.write!(path, Jason.encode!(payload))

    on_exit(fn -> File.rm(path) end)

    assert {:ok, %{ruleset: first_ruleset, criteria: first_criteria}} =
             Rules.seed_rules_from_file(path)

    assert length(first_criteria) == 2

    assert Enum.find(first_criteria, &(&1.spell_id == 222)).threshold == %{
             "must_interrupt" => true
           }

    assert {:ok, %{ruleset: second_ruleset, criteria: second_criteria}} =
             Rules.seed_rules_from_file(path)

    assert second_ruleset.id == first_ruleset.id

    assert Enum.map(second_criteria, & &1.id) |> Enum.sort() ==
             Enum.map(first_criteria, & &1.id) |> Enum.sort()

    ruleset_count =
      Ruleset
      |> where([r], r.name == "Seeded Rules" and r.version == 1)
      |> Repo.aggregate(:count)

    criterion_count =
      MechanicCriterion
      |> where([c], c.ruleset_id == ^second_ruleset.id)
      |> Repo.aggregate(:count)

    assert ruleset_count == 1
    assert criterion_count == 2
  end

  defp criterion_attrs(%Ruleset{} = ruleset, overrides) do
    Map.merge(
      %{
        ruleset_id: ruleset.id,
        spell_id: 123,
        spell_name: "Rule Spell",
        mechanic_type: "avoidable",
        threshold: %{}
      },
      overrides
    )
  end
end

defmodule WeGoNext.Mechanics.TaxonomyTest do
  use ExUnit.Case, async: true

  alias WeGoNext.Mechanics.Taxonomy
  alias WeGoNext.Gold.DimMechanicCriterion
  alias WeGoNext.Rules.MechanicCriterion

  test "classifies the standardized mechanic and actionability vocabulary" do
    assert Taxonomy.keys() == [
             :avoidable,
             :interrupt,
             :targeted_cone,
             :soak,
             :spread,
             :stack,
             :tank_mechanic,
             :healer_mechanic,
             :unavoidable_background,
             :irrelevant,
             :unknown
           ]

    assert Taxonomy.fetch!(:avoidable).fact_eligibility == :supported
    assert Taxonomy.fetch!(:interrupt).fact_eligibility == :provisional
    assert Taxonomy.fetch!(:soak).fact_eligibility == :observation_only
    assert Taxonomy.fetch!(:unavoidable_background).fact_eligibility == :suppressed
    assert Taxonomy.fetch!(:irrelevant).fact_eligibility == :suppressed
    assert Taxonomy.fetch!(:unknown).fact_eligibility == :observation_only

    assert Taxonomy.rule_types() == ~w(
             avoidable
             interrupt
             targeted_cone
             soak
             spread
             stack
             tank_mechanic
             healer_mechanic
           )
  end

  test "rule and gold criteria share only the taxonomy's rule-backed types" do
    assert MechanicCriterion.mechanic_types() == Taxonomy.rule_types()
    assert DimMechanicCriterion.mechanic_types() == Taxonomy.rule_types()

    refute "unavoidable_background" in MechanicCriterion.mechanic_types()
    refute "irrelevant" in MechanicCriterion.mechanic_types()
    refute "unknown" in MechanicCriterion.mechanic_types()
  end

  test "declares default thresholds and honest fact eligibility" do
    assert Taxonomy.default_threshold(:avoidable) == %{"max_hits" => 0}
    assert Taxonomy.default_threshold("interrupt") == %{"must_interrupt" => true}
    assert Taxonomy.default_threshold(:soak) == %{}

    assert Taxonomy.fact_eligible?(:avoidable)
    assert Taxonomy.fact_eligible?(:targeted_cone)
    refute Taxonomy.fact_eligible?(:interrupt)
    refute Taxonomy.fact_eligible?(:spread)
  end

  test "reports missing expected evidence without implying a failure" do
    assert Taxonomy.evidence_completeness([:cast, :impact], [:cast]) == %{
             status: :missing,
             observed: [:cast],
             missing: [:impact]
           }

    assert Taxonomy.evidence_completeness([:cast, :impact], [:impact, :cast]) == %{
             status: :complete,
             observed: [:cast, :impact],
             missing: []
           }

    assert Taxonomy.evidence_completeness([], [:damage]) == %{
             status: :not_declared,
             observed: [:damage],
             missing: []
           }
  end
end

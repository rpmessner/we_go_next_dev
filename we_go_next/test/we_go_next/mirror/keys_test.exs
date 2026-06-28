defmodule WeGoNext.Mirror.KeysTest do
  use ExUnit.Case, async: true

  alias WeGoNext.Gold.DimMechanicCriterion
  alias WeGoNext.Gold.FactFailure.Semantics
  alias WeGoNext.Mirror.Keys

  test "source encounter key is deterministic for byte-range source identity" do
    attrs = %{
      source_head_sha256: String.duplicate("a", 64),
      start_byte: 123,
      end_byte: 456,
      wow_encounter_id: "3306",
      start_time: ~U[2026-06-27 20:00:00Z]
    }

    assert Keys.source_encounter_key(attrs) == Keys.source_encounter_key(attrs)

    assert Keys.source_encounter_key(attrs) !=
             Keys.source_encounter_key(%{attrs | end_byte: 457})
  end

  test "source encounter key is absent when required source identity is missing" do
    refute Keys.source_encounter_key(%{
             source_head_sha256: nil,
             start_byte: 123,
             end_byte: 456,
             wow_encounter_id: "3306",
             start_time: ~U[2026-06-27 20:00:00Z]
           })
  end

  test "criterion key changes when threshold changes" do
    base = criterion_attrs(%{"max_hits" => 0})

    assert Keys.criterion_key(base) !=
             Keys.criterion_key(%{base | threshold: %{"max_hits" => 1}})
  end

  test "criterion key changes when semantics version changes" do
    base = criterion_attrs(%{"max_hits" => 0})

    assert Keys.criterion_key(base) !=
             Keys.criterion_key(base, semantics_version: 2)
  end

  test "every mechanic type resolves to a semantics version" do
    for mechanic_type <- DimMechanicCriterion.mechanic_types() do
      assert is_integer(Semantics.version_for!(mechanic_type))
      assert Semantics.version_for!(mechanic_type) > 0
    end
  end

  defp criterion_attrs(threshold) do
    %{
      product: "wow",
      channel: "retail",
      build_key: "11.2.0",
      boss_encounter_id: "3306",
      difficulty_id: 16,
      spell_id: 1_249_017,
      mechanic_type: "avoidable",
      threshold: threshold
    }
  end
end

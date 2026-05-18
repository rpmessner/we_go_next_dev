defmodule WeGoNext.Gold.FactFailure.RuleSelector do
  @moduledoc """
  Selects the effective gold criterion snapshots for a rebuild.

  Rules are scoped by active status, ruleset, boss encounter id, and difficulty.
  When multiple snapshots match the same spell, the most specific match wins.
  """

  @doc """
  CTE that exposes one effective criterion row per spell for the encounter scope.
  """
  def selected_criteria_cte do
    """
    selected_criteria AS (
      SELECT *
      FROM (
        SELECT
          c.*,
          row_number() OVER (
            PARTITION BY c.spell_id
            ORDER BY
              CASE
                WHEN c.boss_encounter_id IS NULL THEN 0
                WHEN c.difficulty_id IS NULL THEN 1
                WHEN c.difficulty_id = 14 THEN 2
                WHEN c.difficulty_id = 15 THEN 3
                WHEN c.difficulty_id = 16 THEN 4
                ELSE 1
              END DESC,
              c.id ASC
          ) AS specificity_rank
        FROM gold.dim_mechanic_criterion c
        JOIN encounter_scope e ON TRUE
        WHERE c.active = TRUE
          AND c.ruleset_id = $2
          AND (
            c.boss_encounter_id IS NULL
            OR (
              c.boss_encounter_id = e.wow_encounter_id
              AND (
                c.difficulty_id IS NULL
                OR c.difficulty_id = ANY(
                  CASE
                    WHEN e.difficulty_id = 14 THEN ARRAY[14]
                    WHEN e.difficulty_id = 15 THEN ARRAY[14, 15]
                    WHEN e.difficulty_id = 16 THEN ARRAY[14, 15, 16]
                    ELSE ARRAY[14, 15, 16]
                  END
                )
              )
            )
          )
      ) ranked_criteria
      WHERE specificity_rank = 1
    )
    """
  end
end

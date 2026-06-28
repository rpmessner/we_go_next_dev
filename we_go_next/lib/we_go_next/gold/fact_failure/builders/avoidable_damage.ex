defmodule WeGoNext.Gold.FactFailure.Builders.AvoidableDamage do
  @moduledoc """
  Emits failure rows for avoidable damage criteria.

  Semantics: observed player damage rows fail when summed hit count exceeds the
  criterion `threshold.max_hits` value. Damage totals are preserved on the fact.
  """

  @semantics_version 1

  def semantics_version, do: @semantics_version

  def cte_name, do: "avoidable_rows"

  def cte(_opts \\ []) do
    """
    #{cte_name()} AS (
      SELECT
        e.encounter_dim_id,
        dp.id AS player_dim_id,
        sc.id AS criterion_dim_id,
        sum(dt.hit_count)::integer AS failure_count,
        sum(dt.total_amount)::bigint AS total_damage
      FROM silver.damage_taken dt
      JOIN encounter_scope e
        ON e.encounter_dim_id = dt.encounter_dim_id
      JOIN silver.player_info pi
        ON pi.encounter_dim_id = dt.encounter_dim_id
       AND pi.player_guid = dt.target_guid
      JOIN gold.dim_player dp
        ON dp.player_guid = pi.player_guid
      JOIN selected_criteria sc
        ON sc.spell_id = dt.spell_id
       AND sc.mechanic_type = 'avoidable'
      GROUP BY e.encounter_dim_id, dp.id, sc.id, sc.threshold
      HAVING sum(dt.hit_count) > CASE
        WHEN COALESCE(sc.threshold->>'max_hits', '') ~ '^[0-9]+$'
          THEN (sc.threshold->>'max_hits')::integer
        ELSE 0
      END
    )
    """
  end
end

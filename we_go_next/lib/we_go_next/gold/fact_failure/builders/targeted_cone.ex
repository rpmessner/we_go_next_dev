defmodule WeGoNext.Gold.FactFailure.Builders.TargetedCone do
  @moduledoc """
  Emits primary failure rows for targeted cone criteria.

  Semantics: a pre-target marker identifies the assigned player. Impact damage
  and linked hit debuffs identify players clipped by the cone. When the observed
  hit/collateral count exceeds the configured safe count, the failure is
  attributed to the assigned player.
  """

  @semantics_version 1

  def semantics_version, do: @semantics_version

  def cte_name, do: "targeted_cone_rows"

  def cte(_opts \\ []) do
    """
    targeted_cone_markers AS (
      SELECT
        marker.encounter_dim_id,
        sc.id AS criterion_dim_id,
        marker.target_guid,
        marker.applied_at_ms_into_fight AS marker_ms,
        COALESCE(
          lead(marker.applied_at_ms_into_fight) OVER (
            PARTITION BY marker.encounter_dim_id, sc.id
            ORDER BY marker.applied_at_ms_into_fight, marker.target_guid
          ),
          marker.applied_at_ms_into_fight + 15000
        ) AS next_marker_ms,
        sc.threshold,
        CASE
          WHEN COALESCE(sc.threshold->>'max_safe_hit_count', '') ~ '^[0-9]+$'
            THEN (sc.threshold->>'max_safe_hit_count')::integer
          ELSE 0
        END AS max_safe_hit_count,
        ARRAY(
          SELECT jsonb_array_elements_text(
            COALESCE(sc.threshold->'allowed_collateral_roles', '[]'::jsonb)
          )
        ) AS allowed_collateral_roles
      FROM silver.debuff_application marker
      JOIN encounter_scope e
        ON e.encounter_dim_id = marker.encounter_dim_id
      JOIN selected_criteria sc
        ON sc.mechanic_type = 'targeted_cone'
       AND marker.spell_id = (sc.threshold->>'target_marker_spell_id')::integer
    ),
    targeted_cone_hit_rows AS (
      SELECT
        marker.encounter_dim_id,
        marker.criterion_dim_id,
        marker.target_guid AS assigned_target_guid,
        marker.marker_ms,
        marker.max_safe_hit_count,
        marker.allowed_collateral_roles,
        hit.target_guid AS hit_target_guid,
        COALESCE(pi.detected_role, 'unknown') AS hit_role,
        hit.amount::bigint AS damage_amount
      FROM targeted_cone_markers marker
      JOIN silver.damage_taken_event hit
        ON hit.encounter_dim_id = marker.encounter_dim_id
       AND hit.spell_id IN (
         SELECT jsonb_array_elements_text(marker.threshold->'impact_spell_ids')::integer
       )
       AND hit.occurred_at_ms_into_fight >= marker.marker_ms
       AND hit.occurred_at_ms_into_fight < marker.next_marker_ms
      LEFT JOIN silver.player_info pi
        ON pi.encounter_dim_id = hit.encounter_dim_id
       AND pi.player_guid = hit.target_guid

      UNION ALL

      SELECT
        marker.encounter_dim_id,
        marker.criterion_dim_id,
        marker.target_guid AS assigned_target_guid,
        marker.marker_ms,
        marker.max_safe_hit_count,
        marker.allowed_collateral_roles,
        debuff.target_guid AS hit_target_guid,
        COALESCE(pi.detected_role, 'unknown') AS hit_role,
        0::bigint AS damage_amount
      FROM targeted_cone_markers marker
      JOIN silver.debuff_application debuff
        ON debuff.encounter_dim_id = marker.encounter_dim_id
       AND debuff.spell_id IN (
         SELECT jsonb_array_elements_text(
           COALESCE(marker.threshold->'hit_debuff_spell_ids', '[]'::jsonb)
         )::integer
       )
       AND debuff.applied_at_ms_into_fight >= marker.marker_ms
       AND debuff.applied_at_ms_into_fight < marker.next_marker_ms
      LEFT JOIN silver.player_info pi
        ON pi.encounter_dim_id = debuff.encounter_dim_id
       AND pi.player_guid = debuff.target_guid
    ),
    targeted_cone_events AS (
      SELECT
        encounter_dim_id,
        criterion_dim_id,
        assigned_target_guid,
        marker_ms,
        max_safe_hit_count,
        count(DISTINCT hit_target_guid)::integer AS hit_count,
        count(DISTINCT hit_target_guid) FILTER (
          WHERE hit_target_guid <> assigned_target_guid
            AND NOT (hit_role = ANY(allowed_collateral_roles))
        )::integer AS collateral_count,
        sum(damage_amount)::bigint AS total_damage
      FROM targeted_cone_hit_rows
      GROUP BY
        encounter_dim_id,
        criterion_dim_id,
        assigned_target_guid,
        marker_ms,
        max_safe_hit_count,
        allowed_collateral_roles
    ),
    #{cte_name()} AS (
      SELECT
        event.encounter_dim_id,
        dp.id AS player_dim_id,
        event.criterion_dim_id,
        count(*)::integer AS failure_count,
        sum(event.total_damage)::bigint AS total_damage
      FROM targeted_cone_events event
      JOIN gold.dim_player dp
        ON dp.player_guid = event.assigned_target_guid
      WHERE GREATEST(event.hit_count, event.collateral_count) > event.max_safe_hit_count
      GROUP BY event.encounter_dim_id, dp.id, event.criterion_dim_id
    )
    """
  end
end

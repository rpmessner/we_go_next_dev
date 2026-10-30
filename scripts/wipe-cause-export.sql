BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SELECT jsonb_build_object('pulls', coalesce(jsonb_agg(p ORDER BY id), '[]'))
FROM (
  SELECT e.id, e.name, e.success, e.fight_time_ms,
         coalesce((SELECT jsonb_agg(to_jsonb(f) ORDER BY f.rank)
                   FROM gold.fact_wipe_cause f WHERE f.encounter_dim_id = e.id), '[]') AS deciding_deaths
  FROM gold.dim_encounter e
  JOIN public.combat_log_files l ON l.head_sha256 = e.source_head_sha256
  WHERE l.id = 30
) p;
ROLLBACK;

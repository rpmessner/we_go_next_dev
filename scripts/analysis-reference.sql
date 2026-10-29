BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
WITH pulls AS (
  SELECT e.*, row_number() OVER (PARTITION BY e.name ORDER BY e.start_time, e.id) AS pull_number
  FROM gold.dim_encounter e
  JOIN public.combat_log_files l ON l.head_sha256 = e.source_head_sha256
  WHERE l.id = 30
), players AS (
  SELECT p.encounter_dim_id AS pull, p.player_guid AS guid, p.player_name AS name,
         p.class_id, p.spec_id, p.detected_role AS role
  FROM silver.player_info p JOIN pulls e ON e.id = p.encounter_dim_id
), deaths AS (
  SELECT d.encounter_dim_id AS pull, d.target_guid AS guid,
         d.died_at_ms_into_fight AS ms, d.killing_blow_spell_id AS spell,
         to_jsonb(d.damage_recap) AS recap
  FROM silver.death d JOIN pulls e ON e.id = d.encounter_dim_id
), damage AS (
  SELECT d.encounter_dim_id AS pull, d.target_guid AS guid, d.spell_id AS spell,
         sum(d.hit_count) AS hits, sum(d.total_amount) AS amount
  FROM silver.damage_taken d JOIN pulls e ON e.id = d.encounter_dim_id
  GROUP BY 1,2,3
), failures AS (
  SELECT f.encounter_dim_id AS pull, p.player_guid AS guid, c.spell_id AS spell,
         c.spell_name, c.mechanic_type, f.failure_count, f.derivation_version
  FROM gold.fact_failure f JOIN pulls e ON e.id = f.encounter_dim_id
  JOIN gold.dim_player p ON p.id = f.player_dim_id
  JOIN gold.dim_mechanic_criterion c ON c.id = f.criterion_dim_id
), criteria AS (
  SELECT c.spell_id AS spell, c.spell_name, c.mechanic_type, c.boss_encounter_id, c.boss_name,
         c.difficulty_id, c.active, c.build_key, c.ruleset_id, r.status AS ruleset_status
  FROM gold.dim_mechanic_criterion c JOIN rules.ruleset r ON r.id = c.ruleset_id
)
SELECT jsonb_build_object(
  'pulls', coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY start_time,id) FROM pulls p), '[]'),
  'players', coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY pull,guid) FROM players p), '[]'),
  'deaths', coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY pull,ms,guid) FROM deaths d), '[]'),
  'damage', coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY pull,guid,spell) FROM damage d), '[]'),
  'failures', coalesce((SELECT jsonb_agg(to_jsonb(f) ORDER BY pull,guid,spell) FROM failures f), '[]'),
  'criteria', coalesce((SELECT jsonb_agg(to_jsonb(c) ORDER BY spell,ruleset_id) FROM criteria c), '[]')
);
ROLLBACK;

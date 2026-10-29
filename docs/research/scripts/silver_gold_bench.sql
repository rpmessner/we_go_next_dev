-- Silver/gold read-path timings for we-c5q.3. Read-only.
--
--   PGOPTIONS='-c default_transaction_read_only=on' \
--     psql -h localhost -U postgres -d we_go_next_dev -X -q \
--     -v enc=268 -f docs/research/scripts/silver_gold_bench.sql
--
-- :enc is a gold.dim_encounter.id. Player/spell parameters are derived from
-- that encounter so the script works on any imported pull. Each query runs
-- under EXPLAIN (ANALYZE, BUFFERS); read "Execution Time" and the scan type.
-- Run twice and use the second (warm) numbers for interactive estimates.

SET default_transaction_read_only = on;

-- Most-hit player and top NPC damage spell in this pull.
SELECT target_guid AS player FROM silver.damage_taken_event
 WHERE encounter_dim_id = :enc GROUP BY 1 ORDER BY count(*) DESC LIMIT 1 \gset
SELECT spell_id AS spell FROM silver.damage_taken_event
 WHERE encounter_dim_id = :enc AND source_is_npc GROUP BY 1 ORDER BY count(*) DESC LIMIT 1 \gset
SELECT source_head_sha256 AS head, source_file_path AS file FROM gold.dim_encounter WHERE id = :enc \gset
\echo enc=:enc player=:player spell=:spell

\echo '### Q1 deaths in one pull (silver.death, incl. recap arrays)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT target_guid, died_at_ms_into_fight, killing_blow_spell_id, damage_recap, window_events
  FROM silver.death WHERE encounter_dim_id = :enc ORDER BY died_at_ms_into_fight;

\echo '### Q2 hits on one player from one spell in a 30s window (silver.damage_taken_event)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT occurred_at_ms_into_fight, event_type, source_name, amount, overkill
  FROM silver.damage_taken_event
 WHERE encounter_dim_id = :enc AND target_guid = :'player' AND spell_id = :spell
   AND occurred_at_ms_into_fight BETWEEN 0 AND 120000
 ORDER BY combat_log_event_index;

\echo '### Q3 all hits from one spell in one pull, per player (damage_taken_event)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT target_guid, count(*), sum(amount)
  FROM silver.damage_taken_event
 WHERE encounter_dim_id = :enc AND spell_id = :spell GROUP BY 1;

\echo '### Q4 damage done leaderboard for one pull (silver.damage_done)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT source_guid, sum(total_amount) FROM silver.damage_done
 WHERE encounter_dim_id = :enc GROUP BY 1 ORDER BY 2 DESC;

\echo '### Q5 debuffs in one pull by spell (silver.debuff_application)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT spell_id, count(*), count(DISTINCT target_guid) FROM silver.debuff_application
 WHERE encounter_dim_id = :enc GROUP BY 1 ORDER BY 2 DESC;

\echo '### Q6 interrupts/casts in one pull (silver.interrupt_opportunity)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT interrupted_spell_id, count(*) FILTER (WHERE success), count(*)
  FROM silver.interrupt_opportunity WHERE encounter_dim_id = :enc GROUP BY 1;

\echo '### Q7 failures in one pull with dims (gold.fact_failure)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT p.player_name, c.spell_name, c.mechanic_type, f.*
  FROM gold.fact_failure f
  JOIN gold.dim_player p ON p.id = f.player_dim_id
  JOIN gold.dim_mechanic_criterion c ON c.id = f.criterion_dim_id
 WHERE f.encounter_dim_id = :enc;

\echo '### Q8 cross-pull: same spell on same boss+difficulty, all pulls (damage_taken_event)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT e.id, e.start_time, count(*) AS hits, count(DISTINCT t.target_guid) AS players
  FROM gold.dim_encounter e
  JOIN silver.damage_taken_event t ON t.encounter_dim_id = e.id AND t.spell_id = :spell
 WHERE e.wow_encounter_id = (SELECT wow_encounter_id FROM gold.dim_encounter WHERE id = :enc)
   AND e.difficulty_id = (SELECT difficulty_id FROM gold.dim_encounter WHERE id = :enc)
 GROUP BY 1, 2 ORDER BY 2;

\echo '### Q9 cross-pull: one player across every pull (no target_guid-leading index)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT encounter_dim_id, count(*), sum(amount) FROM silver.damage_taken_event
 WHERE target_guid = :'player' GROUP BY 1;

\echo '### Q10 cross-pull failures for one player (gold.fact_failure)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT f.encounter_dim_id, c.spell_name, c.mechanic_type, f.*
  FROM gold.fact_failure f
  JOIN gold.dim_player p ON p.id = f.player_dim_id
  JOIN gold.dim_mechanic_criterion c ON c.id = f.criterion_dim_id
 WHERE p.player_guid = :'player';

\echo '### Q11 bronze byte range for this pull (public.encounters via dim identity)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT c.file_path, e.start_byte, e.end_byte, e.start_time
  FROM gold.dim_encounter d
  JOIN public.combat_log_files c ON c.head_sha256 = d.source_head_sha256
  JOIN public.encounters e ON e.combat_log_file_id = c.id AND e.start_byte = d.start_byte
 WHERE d.id = :enc;

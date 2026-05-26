# Medallion Refactor — Second Opinion

Grounded review of the `medallion-refactor` branch, based on reading the docs, session notes, and the code at HEAD (`38f1a2b`).

## 1. What the branch actually does

The medallion-refactor branch is roughly 40 commits and 16K added lines that build a real analytics warehouse alongside the legacy analyzer code. The shape is:

- New Postgres schemas (`silver`, `gold`, `rules`, `source_data`) holding the warehouse, not directory conventions.
- Zig NIF parser keeps owning event normalization. Events are *never* persisted (the April rewrite's commitment is preserved). The Zig parser emits maps, `Silver.Projector` turns those into typed rows, and `Silver.project_and_persist/2` upserts them.
- Gold dimensions (`dim_encounter`, `dim_player`, `dim_mechanic_criterion`) plus one fact, `fact_failure`, rebuilt by composable SQL CTE builders (`AvoidableDamage`, `MissedInterrupt`) joined via `Gold.FactFailure.Query.insert_sql/1`.
- A real rules layer with versioned rulesets (`draft/active/archived`) and an explicit "promote" step that copies authored rules into immutable-ish gold criterion snapshots. Facts reference the snapshot, not the mutable authored row.
- An identity bridge (`Gold.EncounterIdentity`) translating transitional `public.encounters.id` to `gold.dim_encounter.id` by `(head_sha256 || file_path, start_byte)`.
- Operator UI: rules bootstrap/activate/promote, "Rebuild Gold Facts," and "Force Reimport" all on the home page. The legacy `/encounters/:id` analyzer-cache tabs are deleted; a new gold-keyed shell exists.
- DBM source-data ingestion that produces *candidates*, never active rules — quarantined evidence path.
- CI quality gate, feature/unit tests for each new boundary.

The legacy analyzers are quarantined behind `WeGoNext.Analyzers.*` and a `legacy_analyzer_boundary_test`, kept only as a parity reference.

## 2. Mapping to medallion vocabulary

| Tier | Where | Persisted? | Owns |
|---|---|---|---|
| Bronze | `public.combat_log_files` + log files on disk + `WeGoNext.Bronze.*` reconciliation | files yes, events no | Provenance, fingerprinting, archive move detection |
| Silver | `silver` schema, projected by `Silver.Projector` | yes (aggregate + event-like) | Deterministic per-encounter projections keyed by `encounter_dim_id` |
| Gold | `gold` schema, built by `Gold.FactFailure.Rebuilder` | yes | Conformed dimensions + facts |
| Rules | `rules` schema; `gold.dim_mechanic_criterion` is the promoted snapshot | yes | Authored business config + immutable fact-facing snapshots |
| Source data | `source_data` schema | yes | Evidence-only, never auto-promoted |

Notable: events live only in bronze (on disk), regenerated on demand. Rules live both in the authored layer (mutable) and as gold snapshots (immutable-ish). `public.encounters` is a transitional bridge that should eventually disappear.

## 3. What's good

- **Layer boundaries are concrete.** Real Postgres schemas, not folder conventions. A test exists to keep new UI from re-importing analyzer modules.
- **Rules versioning is the right shape on paper.** Author/promote split is genuinely CQRS-flavored. `dim_mechanic_criterion` carries `ruleset_id`, `ruleset_version`, and build scope copied in; `fact_failure` references the snapshot. That's the right mechanism for reproducible historical analysis.
- **The fact builder is already the "projector pattern."** `@builders [AvoidableDamage, MissedInterrupt]`, uniform CTE row shape (`encounter_dim_id, player_dim_id, criterion_dim_id, failure_count, total_damage`), shared base CTEs (`encounter_scope`, `selected_criteria`). Adding a new failure type is "add a module, list it." That's the explicit pattern, already at the SQL layer.
- **Rebuild boundary is single-entry.** `Gold.RebuildEncounter` is the only thing the importer, CLI task, and LiveView controls call. The recompute matrix (rules → rebuild gold; silver → force reimport) is documented and matches real practice.
- **Empty/missing states are honest.** `RebuildEncounter` returns `{:ok, %{skipped: :active_ruleset_not_found}}` rather than producing zero rows or crashing. That's the substrate for the diagnostics UI (#54).
- **Source-data quarantine is correct.** AGPL constraints around WowAnalyzer, the "never auto-promote DBM candidates" rule, the `source_priority` ranking on reference dimensions — this is good discipline for a project that'll inevitably want to ingest external evidence.

## 4. What's underdeveloped or questionable

Direct takes, ranked by how much they bug me:

**a. Silver is opinionated about "opportunity" — and it bit you already.** `Silver.Projector.project_interrupt_opportunities/2` (lib/we_go_next/silver/projector.ex:230) emits one "failed opportunity" row per *every NPC `SPELL_CAST_SUCCESS`*. That's the 4357-on-one-encounter bug the session notes flagged. The silver row's name implies authored intent, but its semantics are "any NPC cast happened." Classification belongs in the builder/rule layer joined against `selected_criteria`. Silver should be `silver.npc_spell_cast` — unopinionated. Same pattern lurks in `silver.damage_taken_event` if you add more rules.

**b. "Immutable" snapshots aren't actually immutable.** `Rules.upsert_gold_mechanic_criterion` (lib/we_go_next/rules.ex:273-306) uses `on_conflict: {:replace, [...]}` keyed by `source_rule_id`. Re-promote → snapshot mutates in place. So a fact built last week pointing at `criterion_dim_id = 17` with `{max_hits: 0}` can silently start meaning `{max_hits: 2}` after a re-promote. The infrastructure (`ruleset_version`, `source_rule_id`) is right there — change the conflict target to `(source_rule_id, ruleset_version)`, bump version on authored change, and snapshots become genuinely immutable. Low effort; closes the biggest hole in your historical-reproducibility story.

**c. Silver's "projector" is not the formalized pattern.** Gold builders have the discipline (one module per builder, uniform shape). Silver has a 510-line single module hand-rolling seven projections with subtly different filter/reduce idioms. No `@behaviour`, no per-projector version, runs sequentially. The inconsistency is real: you've already proven the pattern works for gold; carrying it to silver would let each projection stamp its rows with a version and run concurrently.

**d. No version stamp on derived rows.** Rules carry `ruleset_version`; silver and gold do not. The recompute policy says "force reimport when silver projection logic changed," but no operator can *see* which silver rows came from which projector code. Operator UI #54 will end up flying blind without a `projector_version` column. Adding it is one migration + one module attribute per projector and gives you "12 fact rows by AvoidableDamage v3, current v4 — rebuild" in the UI.

**e. There's no fact for the priority-#2 trend question.** The product stack puts "personal improvement over repeated attempts" second. `Gold.FailureSummary` does cross-encounter rollups by grouping facts at query time, which works for failures. It doesn't help with "am I improving pull-over-pull on Plexus Sentinel?" That needs `fact_player_encounter_performance` (one row per `(encounter_dim_id, player_dim_id)`: damage_taken, damage_done, deaths, mechanic_failures, time_alive_ms). All the inputs are already in silver. Without this, the second-most-important product question has no read model.

**f. Avoidable classification is structurally incomplete.** Real avoidable analysis needs buff/immunity intervals (was the rogue Cloaked, did the lock have Unending Resolve up). You don't have `silver.player_buff_window` — `silver.debuff_application` is debuffs *applied to* players, not their defensive windows. So `Builders.AvoidableDamage` will produce false positives once the rule list grows beyond a few "always avoidable" spells. This is the silver-grain gap the multi-step analysis problem points at.

**g. `silver.damage_taken` blurs the medallion line.** You have both per-hit `silver.damage_taken_event` and per-`(target, source, spell)` aggregate `silver.damage_taken`. The aggregate is gold-flavored (it's a precomputed roll-up that exists to avoid re-aggregation in the avoidable builder). Putting it in silver means changing aggregation semantics requires re-projecting silver instead of rebuilding gold. Defensible for now (fewer round trips, only one consumer), but worth flagging when the next aggregate temptation comes up.

**h. The CTE-glue rebuild is brittle.** `Query.insert_sql/1` welds all builders into one INSERT. Any builder failure halts the entire rebuild for an encounter, telemetry is per-rebuild not per-builder, and adding a builder with a different row shape requires touching the union. For two builders it's fine; bake in observability before adding a fifth.

**i. `EncounterDetail.get/2` is N+1 across roster.** `personal_pull_summary` calls five separate aggregate queries per player. 25-player raid = 125+ round trips per page load. No preload, no single-CTE consolidation. Low-stakes today; pain when the page grows.

**j. M+ is not actually wired in.** `WeGoNext.MythicPlusRun`/`TrashPull` exist as Elixir structs, the dungeon GameData modules are populated, but the Zig parser doesn't emit `CHALLENGE_MODE_*` boundaries and silver/gold know nothing about pulls below `gold.dim_encounter`. The "sessionization deserves a first-class fact" point is correct and *also* completely deferred today. Not a critique of the refactor scope — just a flag that the M+ story is documentation-deep, not code-deep.

## 5. Concrete suggestions, ranked

| # | Move | Impact | Effort | Touches |
|---|---|---|---|---|
| 1 | Rename `silver.interrupt_opportunity` → `silver.npc_spell_cast`, make `MissedInterrupt` builder join casts against `selected_criteria`. Silver stops classifying. | High | Low | `silver/projector.ex:230`, `gold/fact_failure/builders/missed_interrupt.ex` |
| 2 | Make snapshots immutable: change `Rules.upsert_gold_mechanic_criterion` conflict target to `(source_rule_id, ruleset_version)`. Bump `ruleset.version` on every change that should flow to facts. | High | Low | `rules.ex:273`, migration to add new unique index |
| 3 | Add `fact_player_encounter_performance` fact, one row per `(encounter_dim_id, player_dim_id)`, built from silver. Fits the existing `RebuildEncounter` boundary. | High | Medium | New `gold/fact_player_encounter_performance.ex` + builder, `gold/rebuild_encounter.ex` |
| 4 | Add `projector_version` column on every silver table and `builder_version` on `fact_failure`. Modules declare versions as `@version`. Wire into the operator status panel. | Medium | Low | All silver schemas, builder modules, `gold/rebuilds.ex`, Rules Operations panel |
| 5 | Formalize `WeGoNext.Silver.Projector` behaviour, split the 510-line module into one module per silver table, run via `Task.async_stream`. | Medium | Medium | All of `silver/` |
| 6 | Consolidate `EncounterDetail.personal_totals/2` into a single CTE returning the per-player roll-up in one round trip. | Low | Low | `gold/encounter_detail.ex:259-394` |
| 7 | Add `silver.player_buff_window` (defensive cooldowns, immunities, absorbs) so avoidable classification can subtract immunity intervals. Without this, avoidable will keep producing false positives as rules expand. | High | High | New silver projector + table, builder logic |
| 8 | Add `silver.npc_spell_cast` if (1) lands as a rename rather than a new table — same point either way. Volume risk is real; scope by NPC source filtering and to spells in `selected_criteria` for the first pass. | Medium | Medium | Tied to suggestion #1 |
| 9 | Per-builder telemetry on rebuild (`[:wgn, :gold, :builder, :rebuild]` events with row counts and duration), still inside one transaction. Bound builder split as a later move. | Low | Low | `gold/fact_failure/rebuilder.ex` |
| 10 | Defer M+ sessionization and the formal Analyzer behaviour. The legacy analyzers are quarantined; formalizing them is wasted effort. M+ wiring is a separate Zig + warehouse project, post-raid-loop-solid. | — | — | — |

## 6. Pushback on the framing

- **"Formalize an Analyzer behaviour with project/replay/versioning."** Right framing, but the target is `Silver.Projector`, not `Analyzers.*`. Don't put the behaviour on the dying modules.
- **"Should rules be versioned for historical reproducibility?"** They are — but the implementation has the silent-mutation hole flagged in (b). Fix the snapshot identity before chasing more rule semantics.
- **"Thin cross-encounter facts layer."** Yes — and the existing builder/registry pattern already handles it. This isn't "new infrastructure," it's one more builder.

## 7. Summary

The branch is in good shape for what it scoped. The cracks are mostly in three places: silver classifying things that should be data-shaped, snapshot mutability, and the missing trend-fact and buff-window inputs. None require rethinking the architecture; they refine it.

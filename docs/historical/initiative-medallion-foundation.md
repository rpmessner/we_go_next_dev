# Initiative (Completed) — Medallion Foundation

Status: **Complete.** Archived 2026-06-28.

## Summary

The backend medallion foundation and first operator controls that were in place as of the mid-2026 roadmap. Recorded here as a completed initiative; the live architecture detail remains in [`../ARCHITECTURE.md`](../ARCHITECTURE.md).

## Delivered

- Bronze combat-log provenance + live/archive reconciliation (`combat_log_files`).
- Silver encounter-grain projections (damage taken/done, deaths, interrupts, debuffs, player info) keyed on `gold.dim_encounter.id`.
- Gold dimensions + `fact_failure`; `gold.dim_mechanic_criterion` criterion snapshot.
- Rules schema (`rules.ruleset`, `rules.mechanic_criterion`) + criterion promotion.
- Gold rebuild boundary `WeGoNext.Gold.RebuildEncounter`; rules bootstrap/promotion + rebuild/reimport controls.
- Source-data ingestion groundwork (DBM, WowAnalyzer) — evidence only.
- Gold-backed `/failures` and `/encounters/:id` LiveViews.

## Why archived

Foundation work is done; forward work is the four active initiatives (see [`../initiatives/`](../initiatives/README.md)). This doc is the historical record — do not edit except per the session-log correction rules in `AGENTS.md`.

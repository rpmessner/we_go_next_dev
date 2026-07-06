# Initiative 6 — Public Analysis Mirror

Status: **Plumbing built; product gated by Initiative 5.** Linear: existing Public
Gold Mirror project, to be reshaped after the gold detail contract is split.

## Goal

Publish the real encounter analysis page to the hosted public app by uploading
the public-safe gold encounter detail JSON artifacts to Cloudflare.

This initiative should not define mechanic semantics, Wipefest-style
classification, or the local encounter detail read model. It deploys and mirrors
the contract produced by Initiative 5.

## What Already Exists

WE-5 through WE-12 built useful infrastructure:

- parser/public runtime mode;
- Gigalixir deployment;
- runtime config for public mode;
- report slugs under `/r/:slug`;
- ingest endpoint with bearer token auth;
- stable encounter/criterion keys;
- parser-side upload outbox;
- provisional failure-fact public pages.

The existing Phoenix ingest path is legacy plumbing for the provisional
failure-fact preview. The new product path should publish static/versioned JSON
objects to Cloudflare and have the Gigalixir app read those objects.

## Current Limitation

The deployed public site currently mirrors only failure facts and related
dimensions. That is useful as a deploy/ingest proof, but it does not represent
the local encounter detail page.

Do not expand the failure-fact preview into a separate product. Replace it once
the gold encounter detail contract exists.

## Dependencies

| Dependency | Why |
|---|---|
| Initiative 5 — Gold Encounter Detail Read Models | Defines the JSON artifacts public should read and render |
| Initiative 2 avoidable-loop smoke test | Supplies the first useful mechanic/failure section |
| Initiative 4 — Fact semantics expansion | Supplies additional mechanic/failure sections over time |
| Initiative 3 — User classification UI | Supplies user-authored rule changes that affect mirrored facts |
| Cloudflare artifact storage | Stores the public-safe report/encounter JSON files read by Gigalixir |

## Scope

- Upload the full gold encounter detail JSON artifact set, not raw silver and not
  only `gold.fact_failure`.
- Replace public report and encounter JSON objects on each upload without
  exposing mixed-schema reads.
- Keep report scoping by slug.
- Keep schema-version rejection and retryable outbox behavior.
- Render the public-safe subset of the local detail page.
- Add an operator control or Mix task for draining the outbox.
- Surface upload errors locally.
- Keep the Gigalixir public app read-only with respect to encounter analysis
  data; it should fetch/read Cloudflare artifacts rather than accepting medallion
  writes.

## Acceptance

For one real encounter:

1. Local detail renders from medallion-produced JSON artifacts.
2. Parser uploads those artifacts to Cloudflare under the report slug.
3. Public `/r/:slug/encounters/:source_encounter_key` renders the same
   public-safe sections as local.
4. Public does not query silver, parser modules, `Accounts`, rules internals,
   source-data internals, or a public medallion database for encounter detail.

## Related

[`../PUBLIC_MIRROR_GOLD_DETAIL_PLAN.md`](../PUBLIC_MIRROR_GOLD_DETAIL_PLAN.md) · [`../PUBLIC_MIRROR_DEPLOYMENT.md`](../PUBLIC_MIRROR_DEPLOYMENT.md) · [Initiative 5](05-gold-encounter-detail.md)

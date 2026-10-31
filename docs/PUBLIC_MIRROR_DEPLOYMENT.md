# Public mirror deployment (retired)

The mirror app was shut down because of hosting cost. we-g18.2 removes the
Gigalixir deployment job/build hooks, R2 configuration and credentials,
upload outbox and worker, report slugs, public run mode, and `/r/:slug` viewer.
These services are not part of the current app and there is no deployment or
upload smoke task to run.

Publishing may return as a static HTML/JS artifact on a free or cheap host.
Local document generation remains; see
[`ENCOUNTER_DOCUMENTS_DESIGN.md`](ENCOUNTER_DOCUMENTS_DESIGN.md) and
[`OPERATIONS.md`](OPERATIONS.md).

The operator can revoke obsolete hosting/bucket credentials and remove retired
CI secrets in the provider dashboards. No remote resources are modified by the
code-removal migration.

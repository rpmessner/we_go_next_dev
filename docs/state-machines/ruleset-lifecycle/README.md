# Ruleset lifecycle — retired by we-g18.10

The operator replaced draft/active/archived rulesets with one live code-defined
mechanics catalog. There is no activation, archival, replacement or promotion
lifecycle to enforce. `rules.ruleset` and `rules.mechanic_criterion` are dropped;
gold dimension keys and attached facts survive migration and sync.

The old lifecycle model and generated charts have been removed. The remaining
operation is [sync → optional rebuild](../ruleset-flow/README.md).

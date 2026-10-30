# WCL wipe-cause comparison

Lossless projection of the death identity, timestamp and killingBlow fields of
cached WCL v1 report `aW7mTPNrXwLcM2DR` tables/deaths responses, September 6, 2026.
The fights file retains boss fights only and the matching metadata. No credential
or URL query strings are retained. Full upstream caches can be passed to
`scripts/compare_wipe_cause_wcl.py --cache` without conversion.

There are 16 shared pulls; the two sub-10-second Sszorak resets are not boss fights
in WCL. The approved fixed 30-second cutoff is applied independently to both
sides; this is not the fuller WCL resurrection/first-cluster heuristic.

Known differences are deliberately visible: WCL supplies no killing blow for
Felthuzad on gold 440. Synthetic melee is WCL 1 / parser 0. On gold 451 WCL calls
three blows Eternal Venom 1292348, while revision-2 silver evidence calls them
1290480 (also Eternal Venom). The comparison reports these three raw-ID mismatches
rather than inventing a spell alias or changing silver semantics.

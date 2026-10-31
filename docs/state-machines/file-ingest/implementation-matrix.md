| From | Event | Guard | To | Effects |
|---|---|---|---|---|
| idle | import | always | importing | claim |
| idle | sync | always | syncing | claim |
| idle | reimport | always | reimporting | claim |
| failed | import | always | importing | claim |
| failed | sync | always | syncing | claim |
| failed | reimport | always | reimporting | claim |
| importing | advance | always | importing | advance |
| importing | medallion_failed | always | importing | mark_failed |
| importing | medallion_complete | always | importing | mark_complete |
| importing | complete | ready | idle | release |
| importing | complete | always | failed | fail |
| importing | error | always | failed | fail |
| importing | timeout | always | failed | fail |
| syncing | advance | always | syncing | advance |
| syncing | medallion_failed | always | syncing | mark_failed |
| syncing | medallion_complete | always | syncing | mark_complete |
| syncing | complete | ready | idle | release |
| syncing | complete | always | failed | fail |
| syncing | error | always | failed | fail |
| syncing | timeout | always | failed | fail |
| reimporting | advance | always | reimporting | advance |
| reimporting | medallion_failed | always | reimporting | mark_failed |
| reimporting | medallion_complete | always | reimporting | mark_complete |
| reimporting | complete | ready | idle | release |
| reimporting | complete | always | failed | fail |
| reimporting | error | always | failed | fail |
| reimporting | timeout | always | failed | fail |
| idle | advance | always | idle |  |
| idle | medallion_failed | always | idle |  |
| idle | medallion_complete | always | idle |  |
| idle | complete | always | idle |  |
| idle | error | always | idle |  |
| idle | timeout | always | idle |  |
| importing | import | always | importing |  |
| importing | sync | always | importing |  |
| importing | reimport | always | importing |  |
| syncing | import | always | syncing |  |
| syncing | sync | always | syncing |  |
| syncing | reimport | always | syncing |  |
| reimporting | import | always | reimporting |  |
| reimporting | sync | always | reimporting |  |
| reimporting | reimport | always | reimporting |  |
| failed | advance | always | failed |  |
| failed | medallion_failed | always | failed |  |
| failed | medallion_complete | always | failed |  |
| failed | complete | always | failed |  |
| failed | error | always | failed |  |
| failed | timeout | always | failed |  |

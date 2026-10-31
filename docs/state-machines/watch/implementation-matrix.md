| From | Event | Guard | To | Effects |
|---|---|---|---|---|
| tracking | poll | always | tracking | inspect |
| directory | poll | always | directory | inspect |
| idle | directory | always | directory | directory |
| idle_off | directory | always | directory | directory |
| directory | rotate | always | rotating | rotate |
| tracking | sync | always | syncing | sync |
| tracking | rotate | always | rotating | rotate |
| syncing | success | current_result | tracking | complete, reset |
| rotating | success | current_result | tracking | complete, reset |
| syncing | partial_failure | current_result | backoff | complete, fail |
| rotating | partial_failure | current_result | backoff | complete, fail |
| syncing | failure | current | backoff | fail |
| rotating | failure | current | backoff | fail |
| backoff | retry | retry_file | tracking |  |
| backoff | retry | retry_directory | directory |  |
| idle | watch | candidate | tracking | select, reset |
| idle | watch | always | idle |  |
| idle | stop | always | idle_off | disable |
| idle | expire | expired | idle_off | disable |
| idle | expire | always | idle |  |
| idle | sync | always | idle |  |
| idle | rotate | always | idle |  |
| idle | success | always | idle |  |
| idle | failure | always | idle |  |
| idle | partial_failure | always | idle |  |
| idle | retry | always | idle |  |
| idle | poll | always | idle |  |
| directory | watch | candidate | tracking | select, reset |
| directory | watch | always | directory |  |
| directory | stop | always | idle_off | disable |
| directory | expire | expired | idle_off | disable |
| directory | expire | always | directory |  |
| directory | directory | always | directory |  |
| directory | sync | always | directory |  |
| directory | success | always | directory |  |
| directory | failure | always | directory |  |
| directory | partial_failure | always | directory |  |
| directory | retry | always | directory |  |
| tracking | watch | candidate | tracking | select, reset |
| tracking | watch | always | tracking |  |
| tracking | stop | always | idle_off | disable |
| tracking | expire | expired | idle_off | disable |
| tracking | expire | always | tracking |  |
| tracking | directory | always | tracking |  |
| tracking | success | always | tracking |  |
| tracking | failure | always | tracking |  |
| tracking | partial_failure | always | tracking |  |
| tracking | retry | always | tracking |  |
| syncing | watch | candidate | tracking | select, reset |
| syncing | watch | always | syncing |  |
| syncing | stop | always | idle_off | disable |
| syncing | expire | expired | idle_off | disable |
| syncing | expire | always | syncing |  |
| syncing | directory | always | syncing |  |
| syncing | sync | always | syncing |  |
| syncing | rotate | always | syncing |  |
| syncing | success | always | syncing |  |
| syncing | failure | always | syncing |  |
| syncing | partial_failure | always | syncing |  |
| syncing | retry | always | syncing |  |
| syncing | poll | always | syncing |  |
| rotating | watch | candidate | tracking | select, reset |
| rotating | watch | always | rotating |  |
| rotating | stop | always | idle_off | disable |
| rotating | expire | expired | idle_off | disable |
| rotating | expire | always | rotating |  |
| rotating | directory | always | rotating |  |
| rotating | sync | always | rotating |  |
| rotating | rotate | always | rotating |  |
| rotating | success | always | rotating |  |
| rotating | failure | always | rotating |  |
| rotating | partial_failure | always | rotating |  |
| rotating | retry | always | rotating |  |
| rotating | poll | always | rotating |  |
| backoff | watch | candidate | tracking | select, reset |
| backoff | watch | always | backoff |  |
| backoff | stop | always | idle_off | disable |
| backoff | expire | expired | idle_off | disable |
| backoff | expire | always | backoff |  |
| backoff | directory | always | backoff |  |
| backoff | sync | always | backoff |  |
| backoff | rotate | always | backoff |  |
| backoff | success | always | backoff |  |
| backoff | failure | always | backoff |  |
| backoff | partial_failure | always | backoff |  |
| backoff | retry | always | backoff |  |
| backoff | poll | always | backoff |  |
| idle_off | watch | candidate | tracking | select, reset |
| idle_off | watch | always | idle_off |  |
| idle_off | stop | always | idle_off | disable |
| idle_off | expire | expired | idle_off | disable |
| idle_off | expire | always | idle_off |  |
| idle_off | sync | always | idle_off |  |
| idle_off | rotate | always | idle_off |  |
| idle_off | success | always | idle_off |  |
| idle_off | failure | always | idle_off |  |
| idle_off | partial_failure | always | idle_off |  |
| idle_off | retry | always | idle_off |  |
| idle_off | poll | always | idle_off |  |

| From | Event | Guard | To | Effects |
|---|---|---|---|---|
| idle | idle | always | idle | snapshot |
| idle | importing | always | importing | snapshot |
| idle | failed | always | failed | snapshot |
| idle | timed_out | always | timed_out | snapshot |
| idle | progress | always | idle |  |
| importing | idle | always | idle | snapshot |
| importing | importing | always | importing | snapshot |
| importing | failed | always | failed | snapshot |
| importing | timed_out | always | timed_out | snapshot |
| importing | progress | always | importing | progress |
| failed | idle | always | idle | snapshot |
| failed | importing | always | importing | snapshot |
| failed | failed | always | failed | snapshot |
| failed | timed_out | always | timed_out | snapshot |
| failed | progress | always | failed |  |
| timed_out | idle | always | idle | snapshot |
| timed_out | importing | always | importing | snapshot |
| timed_out | failed | always | failed | snapshot |
| timed_out | timed_out | always | timed_out | snapshot |
| timed_out | progress | always | timed_out |  |

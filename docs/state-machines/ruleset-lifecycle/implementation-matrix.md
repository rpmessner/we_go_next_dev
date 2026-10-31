| From | Event | Guard | To | Effects |
|---|---|---|---|---|
| draft | sync | always | draft |  |
| active | sync | always | active |  |
| archived | sync | always | archived |  |
| draft | activate | always | active | activate |
| active | activate | always | active |  |
| archived | activate | always | active | activate |
| draft | archive | always | archived | archive |
| archived | archive | always | archived |  |
| active | replace | replacement | archived | archive |
| draft | reset | always | draft |  |
| draft | replace | always | draft | reject |
| active | archive | always | active | reject |
| active | replace | always | active | reject |
| active | reset | always | active | reject |
| archived | replace | always | archived | reject |
| archived | reset | always | archived | reject |

| From | Event | Guard | To | Effects |
|---|---|---|---|---|
| sync | succeeded | rebuild_requested | rebuild | synced |
| sync | succeeded | always | done | synced |
| rebuild | succeeded | always | done | rebuilt |
| sync | failed | always | failed | record_failure |
| rebuild | failed | always | failed | record_failure |
| done | succeeded | always | done | reject |
| done | failed | always | done | reject |
| failed | succeeded | always | failed | reject |
| failed | failed | always | failed | reject |

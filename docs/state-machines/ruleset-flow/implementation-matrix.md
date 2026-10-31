| From | Event | Guard | To | Effects |
|---|---|---|---|---|
| sync | succeeded | activate_requested | activate | synced |
| sync | succeeded | promote_requested | promote | synced |
| sync | succeeded | always | done | synced |
| activate | succeeded | promote_requested | promote | activated |
| activate | succeeded | always | done | activated |
| promote | succeeded | rebuild_requested | rebuild | promoted |
| promote | succeeded | always | done | promoted |
| rebuild | succeeded | always | done | rebuilt |
| sync | failed | always | failed | record_failure |
| activate | failed | always | failed | record_failure |
| promote | failed | always | failed | record_failure |
| rebuild | failed | always | failed | record_failure |
| done | succeeded | always | done | reject |
| done | failed | always | done | reject |
| failed | succeeded | always | failed | reject |
| failed | failed | always | failed | reject |

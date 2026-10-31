| From | Event | Guard | To | Effects |
|---|---|---|---|---|
| missing | document | missing | missing | load_document |
| missing | document | stale | stale | load_document |
| missing | document | empty | empty | load_document |
| missing | document | always | fresh | load_document |
| missing | params | always | missing | set_tab |
| missing | switch_tab | always | missing | set_tab, patch_tab |
| missing | toggle_untagged_mechanics | always | missing | toggle_untagged |
| missing | toggle_player_debuffs | always | missing | toggle_debuffs |
| missing | toggle_death_heals | always | missing | toggle_heals |
| missing | select_personal_player | always | missing | select_player |
| stale | document | missing | missing | load_document |
| stale | document | stale | stale | load_document |
| stale | document | empty | empty | load_document |
| stale | document | always | fresh | load_document |
| stale | params | always | stale | set_tab |
| stale | switch_tab | always | stale | set_tab, patch_tab |
| stale | toggle_untagged_mechanics | always | stale | toggle_untagged |
| stale | toggle_player_debuffs | always | stale | toggle_debuffs |
| stale | toggle_death_heals | always | stale | toggle_heals |
| stale | select_personal_player | always | stale | select_player |
| empty | document | missing | missing | load_document |
| empty | document | stale | stale | load_document |
| empty | document | empty | empty | load_document |
| empty | document | always | fresh | load_document |
| empty | params | always | empty | set_tab |
| empty | switch_tab | always | empty | set_tab, patch_tab |
| empty | toggle_untagged_mechanics | always | empty | toggle_untagged |
| empty | toggle_player_debuffs | always | empty | toggle_debuffs |
| empty | toggle_death_heals | always | empty | toggle_heals |
| empty | select_personal_player | always | empty | select_player |
| fresh | document | missing | missing | load_document |
| fresh | document | stale | stale | load_document |
| fresh | document | empty | empty | load_document |
| fresh | document | always | fresh | load_document |
| fresh | params | always | fresh | set_tab |
| fresh | switch_tab | always | fresh | set_tab, patch_tab |
| fresh | toggle_untagged_mechanics | always | fresh | toggle_untagged |
| fresh | toggle_player_debuffs | always | fresh | toggle_debuffs |
| fresh | toggle_death_heals | always | fresh | toggle_heals |
| fresh | select_personal_player | always | fresh | select_player |

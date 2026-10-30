| From | Event | Guard | To | Effects |
|---|---|---|---|---|
| draft | ask_builtin | builtin | computing | compute |
| draft | ask_agent | agent | thinking | arm_timer, request_model |
| computing | computed | always | answered | finish_answer |
| thinking | tool_requested | tool_budget | calling_tool | charge, start_tool |
| thinking | over_limit | exhausted | limit_hit | stop_model |
| thinking | answer_started | answer_budget | writing | charge |
| writing | answer_done | always | answered | stop_timer, finish_answer |
| thinking | api_error | always | failed | stop_model |
| writing | api_error | always | failed | stop_model |
| failed | retry | always | thinking | arm_timer, request_model |
| thinking | cancel | always | cancelled | stop_model |
| calling_tool | cancel | always | cancelled | stop_model |
| writing | cancel | always | cancelled | stop_model |
| limit_hit | continue | can_continue | thinking | raise_cap, arm_timer, request_model |
| answered | record_verdict | always | judged | verdict |
| judged | record_verdict | always | judged | verdict |
| draft | tool_returned | in_flight | draft | record_tool |
| draft | tool_returned | always | draft |  |
| draft | timeout | timer | draft | stop_timer, stop_model |
| draft | timeout | always | draft |  |
| draft | ask_builtin | always | draft |  |
| draft | computed | always | draft |  |
| draft | ask_agent | always | draft |  |
| draft | tool_requested | always | draft |  |
| draft | over_limit | always | draft |  |
| draft | answer_started | always | draft |  |
| draft | answer_done | always | draft |  |
| draft | api_error | always | draft |  |
| draft | retry | always | draft |  |
| draft | cancel | always | draft |  |
| draft | continue | always | draft |  |
| draft | record_verdict | always | draft |  |
| draft | done | always | draft |  |
| computing | tool_returned | in_flight | computing | record_tool |
| computing | tool_returned | always | computing |  |
| computing | timeout | timer | computing | stop_timer, stop_model |
| computing | timeout | always | computing |  |
| computing | ask_builtin | always | computing |  |
| computing | ask_agent | always | computing |  |
| computing | tool_requested | always | computing |  |
| computing | over_limit | always | computing |  |
| computing | answer_started | always | computing |  |
| computing | answer_done | always | computing |  |
| computing | api_error | always | computing |  |
| computing | retry | always | computing |  |
| computing | cancel | always | computing |  |
| computing | continue | always | computing |  |
| computing | record_verdict | always | computing |  |
| computing | done | always | computing |  |
| thinking | tool_returned | in_flight | thinking | record_tool |
| thinking | tool_returned | always | thinking |  |
| thinking | timeout | timer | limit_hit | stop_timer, stop_model |
| thinking | timeout | always | thinking |  |
| thinking | ask_builtin | always | thinking |  |
| thinking | computed | always | thinking |  |
| thinking | ask_agent | always | thinking |  |
| thinking | tool_requested | always | thinking |  |
| thinking | over_limit | always | thinking |  |
| thinking | answer_started | always | thinking |  |
| thinking | answer_done | always | thinking |  |
| thinking | retry | always | thinking |  |
| thinking | continue | always | thinking |  |
| thinking | record_verdict | always | thinking |  |
| thinking | done | always | thinking |  |
| calling_tool | tool_returned | in_flight | thinking | record_tool, request_model |
| calling_tool | tool_returned | always | calling_tool |  |
| calling_tool | timeout | timer | limit_hit | stop_timer, stop_model |
| calling_tool | timeout | always | calling_tool |  |
| calling_tool | ask_builtin | always | calling_tool |  |
| calling_tool | computed | always | calling_tool |  |
| calling_tool | ask_agent | always | calling_tool |  |
| calling_tool | tool_requested | always | calling_tool |  |
| calling_tool | over_limit | always | calling_tool |  |
| calling_tool | answer_started | always | calling_tool |  |
| calling_tool | answer_done | always | calling_tool |  |
| calling_tool | api_error | always | calling_tool |  |
| calling_tool | retry | always | calling_tool |  |
| calling_tool | continue | always | calling_tool |  |
| calling_tool | record_verdict | always | calling_tool |  |
| calling_tool | done | always | calling_tool |  |
| writing | tool_returned | in_flight | writing | record_tool |
| writing | tool_returned | always | writing |  |
| writing | timeout | timer | limit_hit | stop_timer, stop_model |
| writing | timeout | always | writing |  |
| writing | ask_builtin | always | writing |  |
| writing | computed | always | writing |  |
| writing | ask_agent | always | writing |  |
| writing | tool_requested | always | writing |  |
| writing | over_limit | always | writing |  |
| writing | answer_started | always | writing |  |
| writing | retry | always | writing |  |
| writing | continue | always | writing |  |
| writing | record_verdict | always | writing |  |
| writing | done | always | writing |  |
| answered | tool_returned | in_flight | answered | record_tool |
| answered | tool_returned | always | answered |  |
| answered | timeout | timer | answered | stop_timer, stop_model |
| answered | timeout | always | answered |  |
| answered | ask_builtin | always | answered |  |
| answered | computed | always | answered |  |
| answered | ask_agent | always | answered |  |
| answered | tool_requested | always | answered |  |
| answered | over_limit | always | answered |  |
| answered | answer_started | always | answered |  |
| answered | answer_done | always | answered |  |
| answered | api_error | always | answered |  |
| answered | retry | always | answered |  |
| answered | cancel | always | answered |  |
| answered | continue | always | answered |  |
| answered | done | always | answered |  |
| judged | tool_returned | in_flight | judged | record_tool |
| judged | tool_returned | always | judged |  |
| judged | timeout | timer | judged | stop_timer, stop_model |
| judged | timeout | always | judged |  |
| judged | ask_builtin | always | judged |  |
| judged | computed | always | judged |  |
| judged | ask_agent | always | judged |  |
| judged | tool_requested | always | judged |  |
| judged | over_limit | always | judged |  |
| judged | answer_started | always | judged |  |
| judged | answer_done | always | judged |  |
| judged | api_error | always | judged |  |
| judged | retry | always | judged |  |
| judged | cancel | always | judged |  |
| judged | continue | always | judged |  |
| judged | done | always | judged |  |
| limit_hit | tool_returned | in_flight | limit_hit | record_tool |
| limit_hit | tool_returned | always | limit_hit |  |
| limit_hit | timeout | timer | limit_hit | stop_timer, stop_model |
| limit_hit | timeout | always | limit_hit |  |
| limit_hit | ask_builtin | always | limit_hit |  |
| limit_hit | computed | always | limit_hit |  |
| limit_hit | ask_agent | always | limit_hit |  |
| limit_hit | tool_requested | always | limit_hit |  |
| limit_hit | over_limit | always | limit_hit |  |
| limit_hit | answer_started | always | limit_hit |  |
| limit_hit | answer_done | always | limit_hit |  |
| limit_hit | api_error | always | limit_hit |  |
| limit_hit | retry | always | limit_hit |  |
| limit_hit | cancel | always | limit_hit |  |
| limit_hit | continue | always | limit_hit |  |
| limit_hit | record_verdict | always | limit_hit |  |
| limit_hit | done | always | limit_hit |  |
| failed | tool_returned | in_flight | failed | record_tool |
| failed | tool_returned | always | failed |  |
| failed | timeout | timer | failed | stop_timer, stop_model |
| failed | timeout | always | failed |  |
| failed | ask_builtin | always | failed |  |
| failed | computed | always | failed |  |
| failed | ask_agent | always | failed |  |
| failed | tool_requested | always | failed |  |
| failed | over_limit | always | failed |  |
| failed | answer_started | always | failed |  |
| failed | answer_done | always | failed |  |
| failed | api_error | always | failed |  |
| failed | cancel | always | failed |  |
| failed | continue | always | failed |  |
| failed | record_verdict | always | failed |  |
| failed | done | always | failed |  |
| cancelled | tool_returned | in_flight | cancelled | record_tool |
| cancelled | tool_returned | always | cancelled |  |
| cancelled | timeout | timer | cancelled | stop_timer, stop_model |
| cancelled | timeout | always | cancelled |  |
| cancelled | ask_builtin | always | cancelled |  |
| cancelled | computed | always | cancelled |  |
| cancelled | ask_agent | always | cancelled |  |
| cancelled | tool_requested | always | cancelled |  |
| cancelled | over_limit | always | cancelled |  |
| cancelled | answer_started | always | cancelled |  |
| cancelled | answer_done | always | cancelled |  |
| cancelled | api_error | always | cancelled |  |
| cancelled | retry | always | cancelled |  |
| cancelled | cancel | always | cancelled |  |
| cancelled | continue | always | cancelled |  |
| cancelled | record_verdict | always | cancelled |  |
| cancelled | done | always | cancelled |  |

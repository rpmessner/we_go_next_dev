| From | Event | Guard | To | Effects |
|---|---|---|---|---|
| idle | load | always | loading | clear_error, load |
| loading | load | always | loading | clear_error, load |
| failed | load | always | loading | clear_error, load |
| idle | loaded | always | idle |  |
| loading | loaded | always | idle | clear_error |
| failed | loaded | always | failed |  |
| idle | failed | always | idle |  |
| loading | failed | always | failed | set_error |
| failed | failed | always | failed |  |

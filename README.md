```
# MARK: TestRunner
# ╓────────────────────────────────────────────────────────────────────────────────────────╖
# ║ ████████ ███████ ███████ ████████ ██████  ██    ██ ███    ██ ███    ██ ███████ ██████  ║
# ║    ██    ██      ██         ██    ██   ██ ██    ██ ████   ██ ████   ██ ██      ██   ██ ║
# ║    ██    █████   ███████    ██    ██████  ██    ██ ██ ██  ██ ██ ██  ██ █████   ██████  ║
# ║    ██    ██           ██    ██    ██   ██ ██    ██ ██  ██ ██ ██  ██ ██ ██      ██   ██ ║
# ║    ██    ███████ ███████    ██    ██   ██  ██████  ██   ████ ██   ████ ███████ ██   ██ ║
# ╙────────────────────────────────────────────────────────────────────────────────────────╜
```

# TestRunner
A framework to run tests, that works as headless editor scripts, a main area gui, and in-game gui.

## Command Server (`TESTS_*`)

When **enetheru.command-server** is enabled, this plugin registers external
commands from `command_server/`:

| Command | Privileged | Role |
|---------|------------|------|
| `TESTS_PING` | no | Smoke registration |
| `TESTS_LIST` | no | List groups/scripts |
| `TESTS_RELOAD` | no | Rescan + refresh UI tree |
| `TESTS_CLEAR` | no | Clear results (UI + service) |
| `TESTS_SET` | no | `verbose` / `debug` flags |
| `TESTS_RUN` | **yes** | Confirm dialog, sequential runs |
| `TESTS_LAST` | no | Last batch JSON |

Logic lives in `test_runner_service.gd` (Node on the plugin). The main panel Tree
stays the UI view; service owns discovery + agent runs + `user://` logs.

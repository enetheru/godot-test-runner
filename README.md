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

When **enetheru.command-server** is enabled, this plugin registers
`CommandServerTool` scripts from `command_server/`. MCP names are
`cs_tests_*` (e.g. `cs_tests_list`). TCP names stay `TESTS_*`.

| Command | Privileged | Role |
|---------|------------|------|
| `TESTS_PING` | no | Smoke registration |
| `TESTS_LIST` | no | List groups/scripts |
| `TESTS_RELOAD` | no | Rescan + refresh UI tree |
| `TESTS_CLEAR` | no | Clear results (UI + service) |
| `TESTS_SET` | no | log level `notice` / `info` / `debug` / `trace` |
| `TESTS_RUN` | **yes** | Confirm dialog, then run |
| `TESTS_LAST` | no | Last batch JSON |

Logic lives in `scripts/test_runner_service.gd` (Node on the plugin). The main panel Tree
stays the UI view; service owns discovery + agent runs + `user://` logs.

Discovery walks each folder in `cases_dirs`. Nested folders show as nested rows.
`group:Parent` runs that folder and descendants.
Scan depth defaults to 32 as a junction/symlink cycle guard (`max_scan_depth`).

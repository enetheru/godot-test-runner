# TestRunner friction report

- **timestamp:** 2026-08-18T21:52:00
- **session_workspace:** `C:\Godot\Projects\Enetheru.gdsbench-project`
- **addon:** `C:\Godot\addons\Enetheru.test-runner`
- **trigger:** `TESTS_RUN` / `cs_tests_run` via Command Server MCP

## What information was needed

Whether a second in-editor `TESTS_RUN` after `@tool` library edits is safe, or
whether leftover suite / script cache state can take the editor down.

## Observed

In Enetheru.gdsbench-project (GDSBench port, `@tool` scripts, `class_name`
`BenchLib` / `BenchmarkReporter` / `BenchmarkRunner`):

1. First `TESTS_RUN all` after an editor start or plugin reload: `ran=4
   passed=4 failed=0`, reply `status=OK`.
2. After structural `@tool` edits (moving `class_name` / inner types, then
   `DIAGNOSE` soft reparse), the **next** `TESTS_RUN all` kills the Godot
   process. MCP reports `Transport send error` on `http://127.0.0.1:18083/mcp`.
3. Pattern repeated: `FunctionBenchmark` move (second run crash),
   `BenchmarkName` move (second run crash). First run after human restart
   is clean again.
4. Suite JSON still writes `retcode: 1` with `status: "OK"` — `RetCode.TEST_OK`
   is `1`, not a Unix failure. Easy to misread as a crash cause; it is not.
5. **2026-08-18 later:** a second `TESTS_RUN` after adding
   `ClearRegisteredBenchmarks` (no `class_name` / inner-type move) **did not
   crash**. Human also **reloaded the TestRunner plugin** before that batch.
   So “second run always dies” is overstated — either the class-layout edit
   or a still-loaded TestRunner (or both) is required. Plugin reload would
   drop leftover `EditorScript` suite refs from batch 1.

Sequential `begin_run` (default). Suites: `res://tests/range/test_range.gd`,
`register/test_find.gd`, `register/test_register.gd`, `run/test_run.gd`. All
extend `@tool` `GDSBenchTestBase` / `TestBase`. `_run_one` uses
`ResourceLoader.CACHE_MODE_REPLACE` then `script.new()`.

## Root cause / why

Not proven. Strong suspects, in order:

1. **Stale `@tool` class_name after a successful first batch.** The first run
   instantiates suites that hold `BenchLib.*` inner-class aliases. Soft
   `DIAGNOSE` / script reload then swaps those types. The second
   `CACHE_MODE_REPLACE` + `script.new()` hits a live editor process whose
   previous `TestBase` instances or cached scripts still point at the old
   inner classes.
2. **Suite instances are `EditorScript` (`RefCounted`).** `_run_one` sets
   `_keep = null` then skips `free()` when `instance is RefCounted`. A
   first-batch `TestBase` can still be alive when the second batch
   `CACHE_MODE_REPLACE`s the same script after a `class_name` / inner-type
   move.
3. Less likely: Command Server confirm-dialog / MCP HTTP worker dying first.
   The editor process is gone (`uptime` resets on next `HEALTH`), so this is
   a hard crash, not a hung `is_running` flag.

Ruled out as the *cause*: test assertion failures (all four suites report
OK on the first run; crash is on the *following* run).

## Impact

- Agent cannot verify a second function-move in one editor lifetime.
- Human must restart Godot after almost every structural GDSBench edit.
- Easy to blame the port change that just landed; the crash is the *second
  run*, not the first.

6. **2026-08-18 later:** wrapping `TESTS_RUN` in a second `OS.add_logger`
   (`capture_logger.gd`, same as `RUN_SCRIPT`) **hard-crashed** the editor
   when the batch finished. A prior attempt also **deadlocked** MCP
   (`get_lines` mutex vs `remove_logger`). Reverted — do not attach a
   second Logger around TestBase/`@tool` batches until this is understood.

## Workaround

- Restart the editor after `@tool` / `class_name` layout edits, then run
  tests **once**.
- Do not treat `retcode: 1` as failure when `status` is `OK`.
- Follow-up: confirm whether `_run_one` always frees the suite instance, and
  whether a second `TESTS_RUN` should `reload` + drop cached `GDScript`
  objects before `script.new()`.

## Product gap

TestRunner should survive a second in-editor batch after scripts were
reparsed. At minimum: free each suite instance after `_run` / `_cleanup`;
reset `is_running` on editor crash is N/A if the process is dead. A
`TESTS_RUN` that detects recently-reloaded `@tool` scripts might refuse
or force a hard script cache flush instead of crashing.

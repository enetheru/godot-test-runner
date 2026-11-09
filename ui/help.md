# Test Runner

This panel runs the test scripts under the tests folder and the case scripts under the cases folder. Those folders are tests_dir and cases_dir in the project settings.

## Run

Runs the selected rows. An empty selection runs every row still on screen.

## Reload Tests

Scans the folders again and rebuilds the list.

## Filter

Matches row names, and it ignores case. A word matches anywhere in the name. `*` matches any stretch of text, and `?` matches one character. A matching folder name shows that folder's rows. Run uses the rows still on screen.

## Counts

The middle of the bar counts folders, results, failures, and passes.

## Tracy

Captures a trace for each run. The switch shows up once this editor has the profiler and the capture tools are set.

## Level

Sets how much a run prints, from Silent through Trace. A failure's log is in its result box. A pass includes its log when the level includes Info.

## Clear Results

Clears the result boxes and the row status.

## Options

Opens the options resource in the Inspector.

## Rows

The button on a row runs that script. A click on a script name selects that file in the FileSystem dock.

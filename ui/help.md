# Test Runner

This panel runs the test scripts under the tests folder and the case scripts under the cases folder. Those folders are tests_dir and cases_dir in the project settings.

## Run

Opens the Run As menu for the selected cases. An empty selection offers every case still on screen.

## Reload Tests

Scans the folders again and rebuilds the list.

## Filter

Matches row names, and it ignores case. A word matches anywhere in the name. `*` matches any stretch of text, and `?` matches one character. A matching folder name shows that folder's rows. Run uses the rows still on screen.

## Counts

The middle of the bar counts folders, results, failures, and passes.

## Level

A failure's log is in its result box. A pass includes its log when the level includes Info.

## Clear Results

Clears the result boxes and the row status.

## Options

Opens the options resource in the Inspector. Level lists every ceiling, from Silent through Trace. Tracy and its pad stay off until the capture executable, Python, and crop scripts are set.

## Rows

The button on a row runs that script. A click on a script name selects that file in the FileSystem dock.

A right-click on a case, or on a heading that contains cases, opens the Run As menu.

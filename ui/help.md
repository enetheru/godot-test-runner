# Test Runner

This panel runs the test scripts under the tests folder and the case scripts under the cases folder. Those folders are tests_dir and cases_dir in the project settings.

## Play

The button reads Play while the list is idle, and it opens the Run As menu. An empty selection uses every row still on screen. A selection uses those rows.

EditorScript runs those rows in this editor, one script at a time, and writes each result into the list. Test scripts and case scripts both run this way. During that walk the button reads Cancel. The script already running finishes, and Cancel drops the later scripts. Once pressed, the button reads Cancelling and stays inactive until the walk ends, then it reads Play again.

The menu's Play item and Headless launch the case scripts as their own run. Outside the editor, the same button starts that walk directly.

## Reload Tests

Scans the folders again and rebuilds the list.

## Filter

Matches row names, and it ignores case. A word matches anywhere in the name. `*` matches any stretch of text, and `?` matches one character. A matching folder name shows that folder's rows. Run uses the rows still on screen.

## Counts

The right side of the bar reads the counts in words: folders, results, failures, and passes. Those colors come from the panel theme. The counts sit beside Clear Results, Options, and Help.

## Level

Each run adds its own card, and earlier cards stay in the list. The status word is the card title, colored from the result theme, with the script name beside it. The log sits in that card, under the title, and it renders the failure markup. ERROR and WARNING labels in that log take their colors from the result theme. A failure line is a link to that script. A failure's log is included. A pass includes its log when the level includes Info. The Result column takes its colors from the panel theme.

## Clear Results

Clears the result boxes and the row status.

## Options

Opens the options resource in the Inspector. Level lists every ceiling, from Silent through Trace. Tracy and its pad stay off until the capture executable, Python, and crop scripts are set.

## Rows

The button on a row runs that script. A click on a script name selects that file in the FileSystem dock.

A right-click on a script, or on a folder, opens the Run As menu. EditorScript runs the scripts under that row. Play and Headless still launch the case scripts.

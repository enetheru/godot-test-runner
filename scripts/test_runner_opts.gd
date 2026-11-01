@tool
class_name TestRunnerOpts
extends Resource

## Run flags for the TestRunner dock.
##
## [code]scripts/settings.gd[/code] projects these fields into ProjectSettings
## under [constant PREFIX].

const PREFIX:String = "plugin/test_runner"

## Print the test log for a run.
@export var verbose:bool = false:
	set(value):
		if verbose == value:
			return
		verbose = value
		emit_changed()

## Print the debug log for a run.
@export var debug:bool = false:
	set(value):
		if debug == value:
			return
		debug = value
		emit_changed()

## Install Tracy capture around each run.
@export var tracy:bool = false:
	set(value):
		if tracy == value:
			return
		tracy = value
		emit_changed()

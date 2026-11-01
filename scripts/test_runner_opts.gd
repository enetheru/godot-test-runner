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

## Path to tracy-capture.exe. Empty falls back to TRACY_CAPTURE, then the built-in candidate.
@export_global_file("*.exe") var tracy_capture:String = "":
	set(value):
		if tracy_capture == value:
			return
		tracy_capture = value
		emit_changed()

## Folder of the strip scripts, trim_tracy_tail.py and shift_tracy_start.py.
@export_global_dir var tracy_scripts:String = "":
	set(value):
		if tracy_scripts == value:
			return
		tracy_scripts = value
		emit_changed()

## Path to python.exe. Empty falls back to TRACY_PYTHON, then the built-in candidate.
@export_global_file("*.exe") var tracy_python:String = "":
	set(value):
		if tracy_python == value:
			return
		tracy_python = value
		emit_changed()

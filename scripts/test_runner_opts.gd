@tool
class_name TestRunnerOpts
extends Resource

## Run flags for the TestRunner dock.
##
## [code]scripts/settings.gd[/code] projects these fields into ProjectSettings
## under [constant PREFIX].

const PREFIX:String = "plugin/test_runner"
const Log = preload( "../logging.gd" )

## Inclusive [constant Log.Level]. Notice is quiet. The numbers are that enum.
@export_enum( "Notice:15", "Info:31", "Debug:63", "Trace:127" ) var lvl:int = Log.Level.DEFAULT:
	set(value):
		if lvl == value:
			return
		lvl = value
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
@export_global_file("*.exe") var python_exe:String = "":
	set(value):
		if python_exe == value:
			return
		python_exe = value
		emit_changed()

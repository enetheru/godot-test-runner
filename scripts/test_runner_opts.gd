@tool
class_name TestRunnerOpts
extends Resource

## Run flags for the TestRunner dock.
##
## [method shared] is [code]res/opts.tres[/code]. The settings helper mirrors
## that resource with ProjectSettings.

const PREFIX:String = "plugin/test_runner"
const DEFAULT_TESTS_DIR:String = "res://tests"
const DEFAULT_CASES_DIR:String = "res://cases"
const _OPTS_PATH:String = "res://addons/enetheru.test-runner/res/opts.tres"
const Log = preload( "../logging.gd" )

static var _shared:TestRunnerOpts


@export_category("Logging")
## Inclusive [constant Log.Level]. Notice is quiet. The numbers are that enum.
@export_enum( "Notice:15", "Info:31", "Debug:63", "Trace:127" ) var lvl:int = Log.Level.DEFAULT:
	set(value):
		if lvl == value:
			return
		lvl = value
		emit_changed()

@export_category("Discovery")
## Folder of TestBase scripts. Empty uses [constant DEFAULT_TESTS_DIR].
@export_dir var tests_dir:String = DEFAULT_TESTS_DIR:
	set(value):
		if tests_dir == value:
			return
		tests_dir = value
		emit_changed()

## Folder of Case scripts. Empty uses [constant DEFAULT_CASES_DIR].
@export_dir var cases_dir:String = DEFAULT_CASES_DIR:
	set(value):
		if cases_dir == value:
			return
		cases_dir = value
		emit_changed()

@export_category("Tracy")
## Install Tracy capture around each run.
@export var tracy:bool = false:
	set(value):
		if tracy == value:
			return
		tracy = value
		emit_changed()

## Path to python.exe. Empty falls back to TRACY_PYTHON, then the built-in candidate.
@export_global_file("*.exe") var python_exe:String = "":
	set(value):
		if python_exe == value:
			return
		python_exe = value
		emit_changed()

@export_group("Capture", "tracy_")
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

@export_subgroup("Pad", "tracy_")
## Seconds added to the declared harness time for the tracy-capture window.
## A finished capture with setup, body, and cleanup replaces this with the measured mean.
@export_range(0.0, 120.0, 0.01, "suffix:s") var tracy_pad_s:float = 1.0:
	set(value):
		if is_equal_approx(tracy_pad_s, value):
			return
		tracy_pad_s = value
		emit_changed()

## How many measured pads are folded into [member tracy_pad_s]. Caps at 32.
@export var tracy_pad_samples:int = 0:
	set(value):
		if tracy_pad_samples == value:
			return
		tracy_pad_samples = value
		emit_changed()

@export_category("Play")
@export_group("Templates", "template_")
## Binary that runs the reused play pack as template_debug. Empty refuses that menu item.
@export_global_file("*.exe") var template_debug:String = "":
	set(value):
		if template_debug == value:
			return
		template_debug = value
		emit_changed()

## Binary that runs the reused play pack as template_release. Empty refuses that menu item.
@export_global_file("*.exe") var template_release:String = "":
	set(value):
		if template_release == value:
			return
		template_release = value
		emit_changed()


static func shared() -> TestRunnerOpts:
	if _shared != null and is_instance_valid( _shared ):
		return _shared
	var loaded:Resource = load( _OPTS_PATH )
	if loaded is TestRunnerOpts:
		_shared = loaded
	else:
		_shared = TestRunnerOpts.new()
		push_error( "TestRunnerOpts.shared: missing %s" % _OPTS_PATH )
	return _shared


static func tests_root() -> String:
	return _clean_dir( shared().tests_dir, DEFAULT_TESTS_DIR )


static func cases_root() -> String:
	return _clean_dir( shared().cases_dir, DEFAULT_CASES_DIR )


static func _clean_dir( raw:String, fallback:String ) -> String:
	var text:String = raw.strip_edges()
	if text.is_empty():
		return fallback
	while text.ends_with( "/" ) and text != "res://":
		text = text.trim_suffix( "/" )
	return text

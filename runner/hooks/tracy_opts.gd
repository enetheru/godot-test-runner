@tool
extends TR_HookOpts

##[codeblock lang=text]
##│ _____                  ___       _
##│|_   _| _ __ _ __ _  _ / _ \ _ __| |_ ___
##│  | || '_/ _` / _| || | (_) | '_ \  _(_-<
##│  |_||_| \__,_\__|\_, |\___/| .__/\__/__/
##│                  |__/      |_|
##╰───────────────────────────────────────────
##[/codeblock]Settings for the Tracy capture hook.
##
## [method shared] is [code]res/tracy_opts.tres[/code]. The settings helper
## mirrors that resource while the hook script is in the options list.

const Self = preload("tracy_opts.gd")

const PREFIX:String = "plugin/test_runner/hooks/tracy"

# Path inside the addon. [method shared] joins it to the plugin folder.
const _OPTS_PATH:String = "res/tracy_opts.tres"

## Bit order of [member categories]. Flag i is this name.
const CATEGORY_NAMES:PackedStringArray = [
	"core", "script", "physics", "render", "render_gpu", "audio",
	"nav", "io", "shader", "editor", "net", "thread", "gdextension",
]

## Bit order of [member features]. Flag i is this name.
## [code]memory[/code] cannot change after startup.
const FEATURE_NAMES:PackedStringArray = [
	"zones", "plots", "messages", "memory", "locks", "gpu",
	"frames", "frame_images", "auto_gdscript", "log",
]

static var _shared:Self


# ██████  ██████   ██████  ██████  ███████ ██████  ████████ ██ ███████ ███████ #
# ██   ██ ██   ██ ██    ██ ██   ██ ██      ██   ██    ██    ██ ██      ██      #
# ██████  ██████  ██    ██ ██████  █████   ██████     ██    ██ █████   ███████ #
# ██      ██   ██ ██    ██ ██      ██      ██   ██    ██    ██ ██           ██ #
# ██      ██   ██  ██████  ██      ███████ ██   ██    ██    ██ ███████ ███████ #
func                        ________PROPERTIES_______              ()->void:pass

@export_category( "Tracy" )
## Run this hook for every case when its script is in the options list.
@export var enabled:bool = false:
	set( value ):
		if enabled == value:
			return
		enabled = value
		emit_changed()


## Path to python.exe. Empty falls back to TRACY_PYTHON.
@export_global_file( "*.exe" ) var python_exe:String = "":
	set( value ):
		if python_exe == value:
			return
		python_exe = value
		emit_changed()


@export_group( "Capture", "capture_" )
## Path to tracy-capture.exe. Empty falls back to TRACY_CAPTURE.
@export_global_file( "*.exe" ) var capture_exe:String = "":
	set( value ):
		if capture_exe == value:
			return
		capture_exe = value
		emit_changed()


## Folder of the strip scripts, trim_tracy_tail.py and shift_tracy_start.py.
@export_global_dir var capture_scripts:String = "":
	set( value ):
		if capture_scripts == value:
			return
		capture_scripts = value
		emit_changed()


@export_subgroup( "Pad", "pad_" )
## Seconds added to the declared budget for the tracy-capture window.
## A finished capture with setup, body, and cleanup replaces this with the measured mean.
@export_range( 0.0, 120.0, 0.01, "suffix:s" ) var pad_s:float = 1.0:
	set( value ):
		if is_equal_approx( pad_s, value ):
			return
		pad_s = value
		emit_changed()


## How many measured pads are folded into [member pad_s]. Caps at 32.
@export var pad_samples:int = 0:
	set( value ):
		if pad_samples == value:
			return
		pad_samples = value
		emit_changed()


@export_group( "Timing" )
## Seconds to wait for tracy-capture to connect.
@export_range( 0.0, 60.0, 0.1, "suffix:s" ) var connect_wait_s:float = 3.0:
	set( value ):
		if is_equal_approx( connect_wait_s, value ):
			return
		connect_wait_s = value
		emit_changed()


## Seconds the capture post waits after the window.
@export_range( 0.0, 120.0, 0.1, "suffix:s" ) var capture_timeout_s:float = 3.0:
	set( value ):
		if is_equal_approx( capture_timeout_s, value ):
			return
		capture_timeout_s = value
		emit_changed()


## Seconds the capture may stay open after the procedure before that slack is excessive.
@export_range( 0.0, 60.0, 0.1, "suffix:s" ) var late_allowance_s:float = 1.0:
	set( value ):
		if is_equal_approx( late_allowance_s, value ):
			return
		late_allowance_s = value
		emit_changed()


@export_group( "Record" )
## Categories recorded for this capture. Every box starts checked.
@export_flags(
	"core", "script", "physics", "render", "render_gpu", "audio",
	"nav", "io", "shader", "editor", "net", "thread", "gdextension",
) var categories:int = 0x1FFF:
	set( value ):
		if categories == value:
			return
		categories = value
		emit_changed()


## Features recorded for this capture. Every box starts checked.
## [code]memory[/code] cannot change after the engine has started.
@export_flags(
	"zones", "plots", "messages", "memory", "locks", "gpu",
	"frames", "frame_images", "auto_gdscript", "log",
) var features:int = 0x3FF:
	set( value ):
		if features == value:
			return
		features = value
		emit_changed()


#         ███    ███ ███████ ████████ ██   ██  ██████  ██████  ███████         #
#         ████  ████ ██         ██    ██   ██ ██    ██ ██   ██ ██              #
#         ██ ████ ██ █████      ██    ███████ ██    ██ ██   ██ ███████         #
#         ██  ██  ██ ██         ██    ██   ██ ██    ██ ██   ██      ██         #
#         ██      ██ ███████    ██    ██   ██  ██████  ██████  ███████         #
func                        _________METHODS_________              ()->void:pass

func settings_prefix() -> String:
	return PREFIX


static func shared() -> TR_HookOpts:
	var loaded:Resource = TR_Opts.load_saved( _shared, _OPTS_PATH, Self )
	if loaded is Self:
		_shared = loaded
	return _shared

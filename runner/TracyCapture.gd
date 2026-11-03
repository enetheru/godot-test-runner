@tool
class_name TracyCapture
extends RunHooks

## Capture installed on [member TestBase.hooks].
##
## [method install] assigns this object. A run with [member TestBase.hooks]
## empty leaves the capture off. [method pre] runs before [method TestBase._setup].
## [method post] runs after the procedure, including a timeout. The trace is
## the test script's name plus [code].tracy[/code], in that script's folder.
## The crop is [code]trim_tracy_tail.py[/code] then [code]shift_tracy_start.py[/code]
## [code]--trim-init[/code]. Another Tracy server already attached refuses
## the connection.

const CAPTURE_SECONDS:int = 2
const CONNECT_WAIT_SEC:int = 3
const CONNECT_WAIT_MSEC:int = 3000
const CAPTURE_TIMEOUT_MSEC:int = 3000
## Every category the singleton accepts.
const _CATEGORIES:PackedStringArray = [
	"core", "script", "physics", "render", "render_gpu", "audio",
	"nav", "io", "shader", "editor", "net", "thread", "gdextension",
]
## Every feature the singleton accepts. [code]memory[/code] cannot change after startup.
const _FEATURES:PackedStringArray = [
	"zones", "plots", "messages", "memory", "locks", "gpu",
	"frames", "frame_images", "auto_gdscript", "log",
]

const _CAPTURE_EXES:PackedStringArray = []
const _PYTHON_EXES:PackedStringArray = []
const _TRACY_SCRIPT_DIRS:PackedStringArray = []
const _SETTINGS_PREFIX:String = "plugin/test_runner"

const Log := TestBase.Log

# ██████  ██████   ██████  ██████  ███████ ██████  ████████ ██ ███████ ███████ #
# ██   ██ ██   ██ ██    ██ ██   ██ ██      ██   ██    ██    ██ ██      ██      #
# ██████  ██████  ██    ██ ██████  █████   ██████     ██    ██ █████   ███████ #
# ██      ██   ██ ██    ██ ██      ██      ██   ██    ██    ██ ██           ██ #
# ██      ██   ██  ██████  ██      ███████ ██   ██    ██    ██ ███████ ███████ #
func                        ________PROPERTIES_______              ()->void:pass

var local_lvl:int = Log.Level.ERROR

var _capture_pid:int = -1

var _trace_path:String = ""

var _capture_connected:bool = false

var _profiler:Object

var _profiler_was_enabled:bool = false

var _arm_profiler:bool = false

## Category name to the value from before this capture. Empty until the handshake.
var _saved_categories:Dictionary = {}

## Feature name to the value from before this capture. Empty until the handshake.
var _saved_features:Dictionary = {}

var _test:TestBase

var capture_started_msec:int

var capture_started_frame:int

var timer:Timer

var _server_already_connected:bool = false


#         ███    ███ ███████ ████████ ██   ██  ██████  ██████  ███████         #
#         ████  ████ ██         ██    ██   ██ ██    ██ ██   ██ ██              #
#         ██ ████ ██ █████      ██    ███████ ██    ██ ██   ██ ███████         #
#         ██  ██  ██ ██         ██    ██   ██ ██    ██ ██   ██      ██         #
#         ██      ██ ███████    ██    ██   ██  ██████  ██████  ███████         #
func                        _________METHODS_________              ()->void:pass

## Assign [member TestBase.hooks] when it is still empty.
static func install( test:Object ) -> void:
	if test == null:
		return
	if test.get(&"hooks") != null:
		return
	var capture := TracyCapture.new()
	capture._test = test
	capture.local_lvl = test.get(&'local_lvl')
	test.set(&"hooks", capture)


## Install when the saved flag is on and this binary registered the Profiler singleton.
static func install_saved( test:Object ) -> void:
	if is_instance_valid(test) \
	and Engine.has_singleton(&'Profiler'):
		var flag:Variant = ProjectSettings.get_setting(_SETTINGS_PREFIX.path_join("tracy"), false)
		if flag is bool and flag:
			install(test)


## Launch the capture and wait until this process accepts it.
func pre() -> Error:
	#Log.trace({}, self)
	if _test == null:
		Log.err("no TestBase")
		return ERR_UNCONFIGURED

	_profiler = Engine.get_singleton(&'Profiler')
	if _profiler == null:
		Log.err("Profiler singleton is missing. This binary has no Tracy client.")
		return ERR_UNAVAILABLE

	var was_v:Variant = _profiler.call(&'is_enabled')
	_profiler_was_enabled = was_v if was_v is bool else false

	# Silence before the handshake. Recording turns on before the test's [method _setup].
	_arm_profiler = true
	_profiler.call(&'set_enabled', false)

	if Profiler.is_server_connected():
		Log.wrn("Tracy server is already connected")
		_capture_connected = true
		if _arm_profiler and _profiler != null:
			_enable_categories()
			_enable_features()
			_profiler.call(&'set_enabled', true)
		_server_already_connected = true
		return OK

	var connected_sig:Signal = Signal(_profiler, &'server_connected')
	if not connected_sig.is_connected(_on_server_connected):
		@warning_ignore("return_value_discarded")
		connected_sig.connect(_on_server_connected)

	# The timer starts after this hook returns. [method TestBase._setup] can still lower the cap.
	var tree:SceneTree = _test.scene_tree
	if tree == null:
		Log.err("no SceneTree")
		return ERR_UNCONFIGURED

	_ensure_timer(tree)

	var exe:String = _capture_exe()
	if exe.is_empty():
		Log.err("tracy-capture was not found")
		return ERR_FILE_NOT_FOUND

	var script_path:String = str(_test.get_script().resource_path)
	Log.lvl(Log.Level.NOTICE, "test script path: %s" % script_path)

	var capture_file:String = script_path.get_basename() + ".tracy"
	Log.lvl(Log.Level.NOTICE, "test capture file: %s" % capture_file)

	_trace_path = ProjectSettings.globalize_path(capture_file)

	_capture_connected = false
	var _capture_cmd := PackedStringArray([
		"-o", _trace_path,
		"-a", "127.0.0.1",
		"-p", str(Profiler.get_port()),
		"-f",
		"-s", str(CAPTURE_SECONDS),
	])
	Log.lvl(Log.Level.NOTICE, "tracy-capture cmd: %s" % _capture_cmd)
	_capture_pid = OS.create_process(exe, _capture_cmd, false)
	Log.lvl(Log.Level.NOTICE, "tracy-capture pid: %d" % _capture_pid)

	if _capture_pid < 0:
		_restore_profiler()
		Log.err("tracy-capture failed to start")
		return ERR_CANT_CREATE

	# wait for connection using a timer, the connection signal handler will
	# trigger this timers timeout. if there is time left on the clock it
	# succeeded
	if _capture_pid >= 0 \
	and OS.is_process_running(_capture_pid):
		timer.start(CONNECT_WAIT_SEC)
		timer.paused = false
		await timer.timeout

	if not timer.time_left:
		_stop_capture()
		Log.err("timed out waiting for tracy-capture to connect on port %d." % Profiler.get_port())
		return ERR_CANT_CONNECT

	if not _capture_connected:
		_stop_capture()
		Log.err("tracy-capture did not connect on port %d." % Profiler.get_port())
		return ERR_CANT_CONNECT

	capture_started_msec = Time.get_ticks_msec()

	# tracy enabled/disabled is deferred until the end of a frame, so if one
	# hasnt passed since we enabled it, we can delay one before moving forward.
	if _scene_tree().get_frame() == capture_started_frame:
		await _scene_tree().physics_frame
	return OK


## Wait until the capture process saves the file, then crop it.
func post() -> Error:
	#Log.trace({}, self)
	if _server_already_connected:
		_restore_categories()
		_restore_features()
		_profiler.call(&'set_enabled', _profiler_was_enabled)
		return OK

	# Silence before the wait. The capture process is still connected, and this thread keeps framing.
	var tree:SceneTree = _scene_tree()
	if tree == null:
		Log.err("no SceneTree")
		_restore_profiler()
		return ERR_UNCONFIGURED

	_arm_profiler = false
	_profiler.call(&'set_enabled', false)
	# tracy enabled/disabled is deferred until the end of a frame, so we need
	# to wait or we end up adding noise to the trace.
	await tree.physics_frame

	_restore_categories()
	_restore_features()

	# [code]-s[/code] ends the process. Killing it would drop the file.
	while _capture_pid >= 0 \
	and OS.is_process_running(_capture_pid) \
	and Time.get_ticks_msec() - capture_started_msec < (CAPTURE_SECONDS * 1000 + CAPTURE_TIMEOUT_MSEC):
		await tree.process_frame

	var still_running:bool = _capture_pid >= 0 \
	and OS.is_process_running(_capture_pid)

	if still_running:
		_stop_capture()
		return ERR_TIMEOUT

	_capture_pid = -1
	_restore_profiler()
	var cropped:Error = _crop_trace()
	if cropped != OK:
		return cropped

	#Log.err("tracy capture " + _trace_path)
	return OK


## Write [param text] into the open capture.
func message(text:String) -> void:
	# [method Profiler.message] is dropped while recording is silenced.
	if _profiler == null:
		return
	_profiler.call(&'message', text)


func _scene_tree() -> SceneTree:
	if _test == null:
		return null
	return _test.scene_tree


#       ██ ███    ██ ████████ ███████ ██████  ███    ██  █████  ██             #
#       ██ ████   ██    ██    ██      ██   ██ ████   ██ ██   ██ ██             #
#       ██ ██ ██  ██    ██    █████   ██████  ██ ██  ██ ███████ ██             #
#       ██ ██  ██ ██    ██    ██      ██   ██ ██  ██ ██ ██   ██ ██             #
#       ██ ██   ████    ██    ███████ ██   ██ ██   ████ ██   ██ ███████        #
func                        ________INTERNAL_________              ()->void:pass

func _ensure_timer( scene_tree:SceneTree ) -> void:
	# Find, or create our timer.
	var old_timer:Node = scene_tree.root.find_child("TracyCaptureTimer", false)
	if old_timer:
		Log.wrn( "Timer was not removed in last run.")
		old_timer.queue_free()

	timer = Timer.new()
	timer.one_shot = true
	timer.name = "TracyCaptureTimer"
	scene_tree.root.add_child(timer)


## [signal Profiler.server_connected]. The capture process is that server.
func _on_server_connected() -> void:
	#Log.trace({}, self)
	# Same mark as the handshake. Unsilence applies in this flush, then the cases run.
	_capture_connected = true
	if _arm_profiler \
	and _profiler != null:
		_enable_categories()
		_enable_features()
		_profiler.call(&'set_enabled', true)
		capture_started_frame = _scene_tree().get_frame()
	timer.paused = true
	timer.timeout.emit()


## First existing [code]tracy-capture[/code], or [code]TRACY_CAPTURE[/code] when that file exists.
func _capture_exe() -> String:
	# A saved path is the one the dock was given. It does not fall through to the guess.
	var configured:String = _setting_text(&"tracy_capture")
	if not configured.is_empty():
		if FileAccess.file_exists(configured):
			return configured
		return ""
	var from_env:String = OS.get_environment("TRACY_CAPTURE")
	if not from_env.is_empty() and FileAccess.file_exists(from_env):
		return from_env
	for candidate:String in _CAPTURE_EXES:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


## Remember each category, then turn them all on. The mask applies to the next zones.
func _enable_categories() -> void:
	# A second handshake must not snapshot the mask this capture already widened.
	if _profiler == null or not _saved_categories.is_empty():
		return
	for name:String in _CATEGORIES:
		var on_v:Variant = _profiler.call(&'is_category_enabled', name)
		var was_on:bool = on_v if on_v is bool else false
		_saved_categories[name] = was_on
		_profiler.call(&'set_category_enabled', name, true)


## Put the categories back. Call this after the silenced mark.
func _restore_categories() -> void:
	# A failed setup never changed them.
	if _profiler == null:
		_saved_categories = {}
		return
	for name:String in _saved_categories:
		var saved:Variant = _saved_categories[name]
		var was_on:bool = saved if saved is bool else false
		_profiler.call(&'set_category_enabled', name, was_on)
	_saved_categories = {}


## Remember each feature, then turn them all on. A silenced profiler keeps this until recording is enabled.
func _enable_features() -> void:
	# A second handshake must not snapshot the mask this capture already widened.
	if _profiler == null or not _saved_features.is_empty():
		return
	for name:String in _FEATURES:
		var on_v:Variant = _profiler.call(&'is_feature_enabled', name)
		var was_on:bool = on_v if on_v is bool else false
		_saved_features[name] = was_on
		_profiler.call(&'set_feature_enabled', name, true)


## Put the features back. Call this while the profiler is still silenced.
func _restore_features() -> void:
	# A failed setup never changed them.
	if _profiler == null:
		_saved_features = {}
		return
	for name:String in _saved_features:
		var saved:Variant = _saved_features[name]
		var was_on:bool = saved if saved is bool else false
		_profiler.call(&'set_feature_enabled', name, was_on)
	_saved_features = {}


## Put the profiler back and drop the connection listener.
func _restore_profiler() -> void:
	# [method pre] silenced the engine. Put the previous enabled state back.
	_arm_profiler = false
	if _profiler != null:
		var connected_sig:Signal = Signal(_profiler, &'server_connected')
		if connected_sig.is_connected(_on_server_connected):
			connected_sig.disconnect(_on_server_connected)
		_restore_categories()
		_restore_features()
		_profiler.call(&'set_enabled', _profiler_was_enabled)
	_profiler = null


## End a capture that will not save.
func _stop_capture() -> void:
	# [method OS.kill] does not flush the trace. Use it only when the process failed to connect.
	if _capture_pid >= 0 \
	and OS.is_process_running(_capture_pid):
		var killed:Error = OS.kill(_capture_pid)
		if killed != OK:
			Log.err("tracy-capture did not die")
	_capture_pid = -1
	_restore_profiler()


## Trim the saved tail, then drop the startup frames. The file at [member _trace_path] is the result.
func _crop_trace() -> Error:
	# Both scripts refuse an output path equal to the input, so the crop lands in temps first.
	if _trace_path.is_empty() or not FileAccess.file_exists(_trace_path):
		Log.err("tracy capture was not saved")
		return ERR_FILE_NOT_FOUND
	var python:String = _python_exe()
	if python.is_empty():
		# Trimming is optional. The raw capture is still a successful result.
		Log.wrn("python was not found. Raw capture left at " + _trace_path)
		return OK
	var scripts:String = _tracy_script_dir()
	if scripts.is_empty():
		Log.wrn("tracy python scripts were not found. Set TRACY_SCRIPTS to that folder.")
		return ERR_FILE_NOT_FOUND

	var trimmed:String = _trace_path + ".tail"
	var tight:String = _trace_path + ".tight"
	var trim_code:Error = _run_tracy_script(python, scripts.path_join("trim_tracy_tail.py"), PackedStringArray([
		_trace_path, "-o", trimmed, "--force",
	]))
	if trim_code != OK:
		_drop_file(trimmed)
		_drop_file(tight)
		return trim_code

	var shift_code:Error = _run_tracy_script(python, scripts.path_join("shift_tracy_start.py"), PackedStringArray([
		trimmed, "--trim-init", "-o", tight, "--force",
	]))
	_drop_file(trimmed)
	if shift_code != OK:
		_drop_file(tight)
		return shift_code

	var installed:Error = _install_cropped(tight)
	if installed != OK:
		_drop_file(tight)
		return installed
	return OK


## Saved [code]python.exe[/code], or [code]TRACY_PYTHON[/code] when that file exists.
func _python_exe() -> String:
	# [method OS.execute] starts the path itself. A bare [code]python[/code] on [code]PATH[/code] is not enough.
	# A saved path is the one the dock was given. It does not fall through to the guess.
	var configured:String = _setting_text(&"tracy_python")
	if not configured.is_empty():
		if FileAccess.file_exists(configured):
			return configured
		return ""
	var from_env:String = OS.get_environment("TRACY_PYTHON")
	if not from_env.is_empty() and FileAccess.file_exists(from_env):
		return from_env
	for candidate:String in _PYTHON_EXES:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


func _setting_text(prop:StringName) -> String:
	var value:Variant = ProjectSettings.get_setting(_SETTINGS_PREFIX.path_join(String(prop)), "")
	if value is String:
		return value
	return ""


## Folder that holds both crop scripts, or [code]TRACY_SCRIPTS[/code] when that folder has them.
func _tracy_script_dir() -> String:
	# trim_tracy_tail.py imports shift_tracy_start from this same folder.
	var configured:String = _setting_text(&"tracy_scripts")
	if not configured.is_empty():
		if _tracy_scripts_present(configured):
			return configured
		return ""
	var from_env:String = OS.get_environment("TRACY_SCRIPTS")
	if _tracy_scripts_present(from_env):
		return from_env
	for candidate:String in _TRACY_SCRIPT_DIRS:
		if _tracy_scripts_present(candidate):
			return candidate
	return ""


## Both crop scripts are in [param folder].
func _tracy_scripts_present(folder:String) -> bool:
	# An env override that names the wrong folder must miss, same as a missing install.
	if folder.is_empty():
		return false
	return FileAccess.file_exists(folder.path_join("trim_tracy_tail.py")) \
		and FileAccess.file_exists(folder.path_join("shift_tracy_start.py"))


## Run one crop script. [param args] follow the script path.
func _run_tracy_script(python:String, script:String, args:PackedStringArray) -> Error:
	# Refusals are printed on stderr. Asking for that stream puts them in the captured text.
	var captured:Array = []
	var command:PackedStringArray = PackedStringArray([script])
	command.append_array(args)
	var code:int = OS.execute(python, command, captured, true)
	var text:String = ""
	for chunk:Variant in captured:
		if chunk is String:
			text += chunk
	text = text.strip_edges()
	if code != 0:
		Log.wrn("tracy script failed (" + str(code) + ") " + script.get_file() + "\n" + text)
		return ERR_SCRIPT_FAILED
	if not text.is_empty():
		Log.wrn(text)
	return OK


## Move [param tight] onto [member _trace_path].
func _install_cropped(tight:String) -> Error:
	# Park the raw capture until the cropped file is in its place.
	var parked:String = _trace_path + ".raw"
	if FileAccess.file_exists(parked):
		var cleared:Error = DirAccess.remove_absolute(parked)
		if cleared != OK:
			Log.wrn("could not clear " + parked)
			return cleared
	var moved:Error = DirAccess.rename_absolute(_trace_path, parked)
	if moved != OK:
		Log.wrn("could not park the raw capture")
		return moved

	var placed:Error = DirAccess.rename_absolute(tight, _trace_path)
	if placed != OK:
		var back:Error = DirAccess.rename_absolute(parked, _trace_path)
		if back != OK:
			Log.wrn("cropped trace is at " + tight + " and the raw capture is at " + parked)
		else:
			Log.wrn("could not install the cropped capture")
		return placed

	var dropped:Error = DirAccess.remove_absolute(parked)
	if dropped != OK:
		Log.wrn("cropped capture is in place. raw copy remains at " + parked)
	return OK


## Remove a crop temp when it is still on disk.
func _drop_file(path:String) -> void:
	# A script that failed before writing leaves no file.
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var removed:Error = DirAccess.remove_absolute(path)
	if removed != OK:
		Log.wrn("could not remove " + path)

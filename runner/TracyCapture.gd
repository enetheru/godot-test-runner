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

const CAPTURE_SECONDS:int = 1
const CONNECT_WAIT_MSEC:int = 8000
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
var _test:Object


## Assign [member TestBase.hooks] when it is still empty.
static func install(test:Object) -> void:
	if test == null:
		return
	if test.get(&"hooks") != null:
		return
	var capture := TracyCapture.new()
	capture._test = test
	# The test's property keeps this RefCounted alive.
	test.set(&"hooks", capture)


## Install when the saved flag is on and this binary registered the Profiler singleton.
static func install_saved(test:Object) -> void:
	if test == null or not Engine.has_singleton(&'Profiler'):
		return
	var flag:Variant = ProjectSettings.get_setting(_SETTINGS_PREFIX.path_join("tracy"), false)
	if not (flag is bool) or not flag:
		return
	install(test)


func _scene_tree() -> SceneTree:
	if _test == null:
		return null
	var tree_v:Variant = _test.get(&"scene_tree")
	if tree_v is SceneTree:
		return tree_v
	return null


func _log(msg:String) -> void:
	if _test != null and _test.has_method(&"logp"):
		_test.call(&"logp", msg)


## Launch the capture and wait until this process accepts it.
func pre() -> Error:
	# The timer starts after this hook returns. [method TestBase._setup] can still lower the cap.
	var tree:SceneTree = _scene_tree()
	if tree == null:
		_log("no SceneTree")
		return ERR_UNCONFIGURED
	_test.set(&"max_runtime_s", 20.0)
	var exe:String = _capture_exe()
	if exe.is_empty():
		_log("tracy-capture was not found")
		return ERR_FILE_NOT_FOUND
	_profiler = Engine.get_singleton(&'Profiler')
	if _profiler == null:
		_log("Profiler singleton is missing. This binary has no Tracy client.")
		return ERR_UNAVAILABLE

	var was_v:Variant = _profiler.call(&'is_enabled')
	_profiler_was_enabled = was_v if was_v is bool else false
	# Silence before the handshake. Recording turns on before the test's [method _setup].
	_arm_profiler = true
	_profiler.call(&'set_enabled', false)
	var connected_sig:Signal = Signal(_profiler, &'server_connected')
	if not connected_sig.is_connected(_on_server_connected):
		@warning_ignore("return_value_discarded")
		connected_sig.connect(_on_server_connected)

	var script:Script = _test.get_script()
	var script_path:String = script.resource_path
	var capture_file:String = script_path.get_file().get_basename() + ".tracy"
	_trace_path = ProjectSettings.globalize_path(script_path.get_base_dir().path_join(capture_file))
	var port:int = _capture_port()
	_capture_connected = false
	_capture_pid = OS.create_process(exe, PackedStringArray([
		"-o", _trace_path,
		"-a", "127.0.0.1",
		"-p", str(port),
		"-f",
		"-s", str(CAPTURE_SECONDS),
	]))
	if _capture_pid < 0:
		_restore_profiler()
		_log("tracy-capture failed to start")
		return ERR_CANT_CREATE

	var started_msec:int = Time.get_ticks_msec()
	while not _capture_connected \
	and Time.get_ticks_msec() - started_msec < CONNECT_WAIT_MSEC:
		if not OS.is_process_running(_capture_pid):
			break
		await tree.process_frame
	if not _capture_connected:
		_stop_capture()
		_log("tracy-capture did not connect on port %d. Another server may already be attached." % port)
		return ERR_CANT_CONNECT

	#STUB [method Profiler.set_enabled] applies on the next frame mark. Cross that mark before the test's [method _setup].
	#STUB await tree.process_frame
	#STUB ^^ I foun this not to be needed
	return OK


## Wait until the capture process saves the file, then crop it.
func post() -> Error:
	# Silence before the wait. The capture process is still connected, and this thread keeps framing.
	var tree:SceneTree = _scene_tree()
	if tree == null:
		_log("no SceneTree")
		_restore_profiler()
		return ERR_UNCONFIGURED
	_arm_profiler = false
	if _profiler != null:
		_profiler.call(&'set_enabled', false)
	# One more frame applies the silence. The masks stay wide through that frame.
	await tree.process_frame
	_restore_categories()
	_restore_features()
	# [code]-s[/code] ends the process. Killing it would drop the file.
	var started_msec:int = Time.get_ticks_msec()
	while _capture_pid >= 0 and OS.is_process_running(_capture_pid) \
	and Time.get_ticks_msec() - started_msec < CONNECT_WAIT_MSEC:
		await tree.process_frame
	var still_running:bool = _capture_pid >= 0 and OS.is_process_running(_capture_pid)
	if still_running:
		_stop_capture()
		return ERR_TIMEOUT
	_capture_pid = -1
	_restore_profiler()
	var cropped:Error = _crop_trace()
	if cropped != OK:
		return cropped
	_log("tracy capture " + _trace_path)
	return OK


## Write [param text] into the open capture.
func message(text:String) -> void:
	# [method Profiler.message] is dropped while recording is silenced.
	if _profiler == null:
		return
	_profiler.call(&'message', text)


## [signal Profiler.server_connected]. The capture process is that server.
func _on_server_connected() -> void:
	# Same mark as the handshake. Unsilence applies in this flush, then the cases run.
	_capture_connected = true
	if _arm_profiler and _profiler != null:
		_enable_categories()
		_enable_features()
		_profiler.call(&'set_enabled', true)


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


## Listen port. The editor's environment wins, otherwise 8086.
func _capture_port() -> int:
	# The client takes the first free port from 8086 when no port was set.
	var names:PackedStringArray = [
		"TRACY_CAPTURE_PORT",
		"GODOT_PROFILER_PORT",
		"GODOT_TRACY_PORT",
		"TRACY_PORT",
	]
	for name:String in names:
		var text:String = OS.get_environment(name)
		if text.is_valid_int():
			return text.to_int()
	return 8086


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
	if _capture_pid >= 0 and OS.is_process_running(_capture_pid):
		var killed:Error = OS.kill(_capture_pid)
		if killed != OK:
			_log("tracy-capture did not die")
	_capture_pid = -1
	_restore_profiler()


## Trim the saved tail, then drop the startup frames. The file at [member _trace_path] is the result.
func _crop_trace() -> Error:
	# Both scripts refuse an output path equal to the input, so the crop lands in temps first.
	if _trace_path.is_empty() or not FileAccess.file_exists(_trace_path):
		_log("tracy capture was not saved")
		return ERR_FILE_NOT_FOUND
	var python:String = _python_exe()
	if python.is_empty():
		# Trimming is optional. The raw capture is still a successful result.
		_log("python was not found. Raw capture left at " + _trace_path)
		return OK
	var scripts:String = _tracy_script_dir()
	if scripts.is_empty():
		_log("tracy python scripts were not found. Set TRACY_SCRIPTS to that folder.")
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
		_log("tracy script failed (" + str(code) + ") " + script.get_file() + "\n" + text)
		return ERR_SCRIPT_FAILED
	if not text.is_empty():
		_log(text)
	return OK


## Move [param tight] onto [member _trace_path].
func _install_cropped(tight:String) -> Error:
	# Park the raw capture until the cropped file is in its place.
	var parked:String = _trace_path + ".raw"
	if FileAccess.file_exists(parked):
		var cleared:Error = DirAccess.remove_absolute(parked)
		if cleared != OK:
			_log("could not clear " + parked)
			return cleared
	var moved:Error = DirAccess.rename_absolute(_trace_path, parked)
	if moved != OK:
		_log("could not park the raw capture")
		return moved

	var placed:Error = DirAccess.rename_absolute(tight, _trace_path)
	if placed != OK:
		var back:Error = DirAccess.rename_absolute(parked, _trace_path)
		if back != OK:
			_log("cropped trace is at " + tight + " and the raw capture is at " + parked)
		else:
			_log("could not install the cropped capture")
		return placed

	var dropped:Error = DirAccess.remove_absolute(parked)
	if dropped != OK:
		_log("cropped capture is in place. raw copy remains at " + parked)
	return OK


## Remove a crop temp when it is still on disk.
func _drop_file(path:String) -> void:
	# A script that failed before writing leaves no file.
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var removed:Error = DirAccess.remove_absolute(path)
	if removed != OK:
		_log("could not remove " + path)

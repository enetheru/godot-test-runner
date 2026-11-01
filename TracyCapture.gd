@tool @abstract
class_name TracyCapture extends TestBase

## Starts [code]tracy-capture[/code] around one [TestBase] case.
##
## [method run_test] arms the capture, calls [method TestBase.run_test], then
## saves and crops. [method _setup], [method _run_test], and [method _cleanup]
## stay the test's. Recording is on before that [code]super[/code] call, so
## the test's setup is in the trace. The trace is the test script's name plus
## [code].tracy[/code], in that script's folder. The crop is
## [code]trim_tracy_tail.py[/code] then [code]shift_tracy_start.py[/code]
## [code]--trim-init[/code]. Another Tracy server already attached refuses
## the connection.

const CAPTURE_SECONDS:int = 1
const CONNECT_WAIT_MSEC:int = 8000
## Left on: [code]script[/code], so the cases stay in the trace. The rest of this frame is the editor.
const _QUIET_CATEGORIES:PackedStringArray = [
	"core", "physics", "render", "render_gpu", "audio",
	"nav", "io", "shader", "editor", "net", "thread",
]

const _CAPTURE_EXES:PackedStringArray = [
	"C:/git/wolfpld/tracy/capture/cmake-build-release-visual-studio/tracy-capture.exe",
]
const _PYTHON_EXES:PackedStringArray = [
	"C:/Users/nicho/AppData/Local/Programs/Python/Python314/python.exe",
]
const _TRACY_SCRIPT_DIRS:PackedStringArray = [
	"C:/Godot/src/godot-private/misc/scripts/tracy",
]

var _capture_pid:int = -1
var _trace_path:String = ""
var _capture_connected:bool = false
var _profiler:Object
var _profiler_was_enabled:bool = false
var _arm_profiler:bool = false
var _quieted:PackedStringArray = PackedStringArray()


## Arm the capture, run the test, then save and crop.
func run_test() -> void:
	# [method _setup] belongs to the test. This wraps the runner that calls it.
	var begun:Error = await _begin_capture()
	if begun != OK:
		runcode = RetCode.TEST_FAILED
		_finish_run()
		return

	await super()
	var ended:Error = await _end_capture()
	if ended != OK and runcode == RetCode.TEST_OK:
		runcode = RetCode.TEST_FAILED


## Launch the capture and wait until this process accepts it.
func _begin_capture() -> Error:
	# The timer starts in [method TestBase.run_test] and covers the test. The save is after that returns.
	var tree_ready:Error = _ensure_scene_tree()
	if tree_ready != OK:
		logp("no SceneTree")
		return tree_ready
	max_runtime_s = 20.0
	var exe:String = _capture_exe()
	if exe.is_empty():
		logp("tracy-capture was not found")
		return ERR_FILE_NOT_FOUND
	_profiler = Engine.get_singleton(&'Profiler')
	if _profiler == null:
		logp("Profiler singleton is missing. This binary has no Tracy client.")
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

	var script:Script = get_script()
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
		logp("tracy-capture failed to start")
		return ERR_CANT_CREATE

	var started_msec:int = Time.get_ticks_msec()
	while not _capture_connected \
	and Time.get_ticks_msec() - started_msec < CONNECT_WAIT_MSEC:
		if not OS.is_process_running(_capture_pid):
			break
		await scene_tree.process_frame
	if not _capture_connected:
		_stop_capture()
		logp("tracy-capture did not connect on port %d. Another server may already be attached." % port)
		return ERR_CANT_CONNECT

	# [method Profiler.set_enabled] applies on the next frame mark. Cross that mark before the test's [method _setup].
	await scene_tree.process_frame
	return OK


## Wait until the capture process saves the file, then crop it.
func _end_capture() -> Error:
	# Silence before the wait. The capture process is still connected, and this thread keeps framing.
	_arm_profiler = false
	if _profiler != null:
		_profiler.call(&'set_enabled', false)
	# One more frame applies the silence. Categories stay off through that frame's work.
	await scene_tree.process_frame
	_restore_categories()
	# [code]-s[/code] ends the process. Killing it would drop the file.
	var started_msec:int = Time.get_ticks_msec()
	while _capture_pid >= 0 and OS.is_process_running(_capture_pid) \
	and Time.get_ticks_msec() - started_msec < CONNECT_WAIT_MSEC:
		await scene_tree.process_frame
	var still_running:bool = _capture_pid >= 0 and OS.is_process_running(_capture_pid)
	if still_running:
		_stop_capture()
		return ERR_TIMEOUT
	_capture_pid = -1
	_restore_profiler()
	var cropped:Error = _crop_trace()
	if cropped != OK:
		return cropped
	logp("tracy capture " + _trace_path)
	return OK


## Write [param text] into the open capture.
func _profiler_message(text:String) -> void:
	# [method Profiler.message] is dropped while recording is silenced.
	if _profiler == null:
		return
	_profiler.call(&'message', text)


## [signal Profiler.server_connected]. The capture process is that server.
func _on_server_connected() -> void:
	# Same mark as the handshake. Unsilence applies in this flush, then the cases run.
	_capture_connected = true
	if _arm_profiler and _profiler != null:
		_quiet_categories()
		_profiler.call(&'set_enabled', true)


## First existing [code]tracy-capture[/code], or [code]TRACY_CAPTURE[/code] when that file exists.
func _capture_exe() -> String:
	# [code]C:/wolfpld/tracy[/code] is the guessed install. The 0.14.1 build is under [code]C:/git/wolfpld/tracy[/code].
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


## Turn off every category except [code]script[/code]. The mask applies to the next zones.
func _quiet_categories() -> void:
	# Remember only the ones that were on, so the restore does not invent flags.
	_quieted = PackedStringArray()
	if _profiler == null:
		return
	for name:String in _QUIET_CATEGORIES:
		var on_v:Variant = _profiler.call(&'is_category_enabled', name)
		if on_v is bool and on_v:
			var added:bool = _quieted.append(name)
			if added:
				_profiler.call(&'set_category_enabled', name, false)


## Put the categories back. Call this after the silenced mark.
func _restore_categories() -> void:
	# A failed setup never quieted them.
	if _profiler == null:
		_quieted = PackedStringArray()
		return
	for name:String in _quieted:
		_profiler.call(&'set_category_enabled', name, true)
	_quieted = PackedStringArray()


## Put the profiler back and drop the connection listener.
func _restore_profiler() -> void:
	# [method _begin_capture] silenced the engine. Put the previous enabled state back.
	_arm_profiler = false
	if _profiler != null:
		var connected_sig:Signal = Signal(_profiler, &'server_connected')
		if connected_sig.is_connected(_on_server_connected):
			connected_sig.disconnect(_on_server_connected)
		_profiler.call(&'set_enabled', _profiler_was_enabled)
	_profiler = null


## End a capture that will not save.
func _stop_capture() -> void:
	# [method OS.kill] does not flush the trace. Use it only when the process failed to connect.
	if _capture_pid >= 0 and OS.is_process_running(_capture_pid):
		var killed:Error = OS.kill(_capture_pid)
		if killed != OK:
			logp("tracy-capture did not die")
	_capture_pid = -1
	_restore_profiler()


## Trim the saved tail, then drop the startup frames. The file at [member _trace_path] is the result.
func _crop_trace() -> Error:
	# Both scripts refuse an output path equal to the input, so the crop lands in temps first.
	if _trace_path.is_empty() or not FileAccess.file_exists(_trace_path):
		logp("tracy capture was not saved")
		return ERR_FILE_NOT_FOUND
	var python:String = _python_exe()
	if python.is_empty():
		logp("python was not found. Set TRACY_PYTHON to python.exe.")
		return ERR_FILE_NOT_FOUND
	var scripts:String = _tracy_script_dir()
	if scripts.is_empty():
		logp("tracy python scripts were not found. Set TRACY_SCRIPTS to that folder.")
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


## First existing [code]python.exe[/code], or [code]TRACY_PYTHON[/code] when that file exists.
func _python_exe() -> String:
	# [method OS.execute] starts the path itself. A bare [code]python[/code] on [code]PATH[/code] is not enough.
	var from_env:String = OS.get_environment("TRACY_PYTHON")
	if not from_env.is_empty() and FileAccess.file_exists(from_env):
		return from_env
	for candidate:String in _PYTHON_EXES:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


## Folder that holds both crop scripts, or [code]TRACY_SCRIPTS[/code] when that folder has them.
func _tracy_script_dir() -> String:
	# The scripts import each other from this folder. The process working directory does not matter.
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
		logp("tracy script failed (" + str(code) + ") " + script.get_file() + "\n" + text)
		return ERR_SCRIPT_FAILED
	if not text.is_empty():
		logp(text)
	return OK


## Move [param tight] onto [member _trace_path].
func _install_cropped(tight:String) -> Error:
	# Park the raw capture until the cropped file is in its place.
	var parked:String = _trace_path + ".raw"
	if FileAccess.file_exists(parked):
		var cleared:Error = DirAccess.remove_absolute(parked)
		if cleared != OK:
			logp("could not clear " + parked)
			return cleared
	var moved:Error = DirAccess.rename_absolute(_trace_path, parked)
	if moved != OK:
		logp("could not park the raw capture")
		return moved

	var placed:Error = DirAccess.rename_absolute(tight, _trace_path)
	if placed != OK:
		var back:Error = DirAccess.rename_absolute(parked, _trace_path)
		if back != OK:
			logp("cropped trace is at " + tight + " and the raw capture is at " + parked)
		else:
			logp("could not install the cropped capture")
		return placed

	var dropped:Error = DirAccess.remove_absolute(parked)
	if dropped != OK:
		logp("cropped capture is in place. raw copy remains at " + parked)
	return OK


## Remove a crop temp when it is still on disk.
func _drop_file(path:String) -> void:
	# A script that failed before writing leaves no file.
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var removed:Error = DirAccess.remove_absolute(path)
	if removed != OK:
		logp("could not remove " + path)

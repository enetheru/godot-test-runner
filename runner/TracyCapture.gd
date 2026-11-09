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
## the connection. [signal Profiler.server_disconnected] is watched until the
## capture process exits. A disconnect during the procedure warns and names a
## higher budget. One second open after the procedure is allowed. Past that,
## a lower budget is named when the window would shrink and still leave that second.

const CONNECT_WAIT_SEC:int = 3
const CONNECT_WAIT_MSEC:int = 3000
const CAPTURE_TIMEOUT_MSEC:int = 3000
## How long the capture may stay open after the procedure before that slack is excessive.
const _LATE_ALLOWANCE_S:float = 1.0
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

## [TestBase] or [CaseSession]. The capture reads either object's fields.
var _test:Object

var capture_started_msec:int

## Milliseconds when [code]tracy-capture[/code] was launched, and when it exited.
var capture_launched_msec:int = 0
var capture_ended_msec:int = 0

## How long [method post] waits for [code]-s[/code] to close the file.
var _capture_budget_msec:int = 0

var capture_started_frame:int

var timer:Timer

var _server_already_connected:bool = false

## Milliseconds when the Tracy server left. Zero until that is known.
var _disconnect_msec:int = 0

## Milliseconds when the procedure returned and [method post] began.
var _procedure_end_msec:int = 0

## Whole seconds passed to [code]-s[/code]. Zero when this capture did not launch one.
var _window_sec:int = 0

var _gap_reported:bool = false


#         ███    ███ ███████ ████████ ██   ██  ██████  ██████  ███████         #
#         ████  ████ ██         ██    ██   ██ ██    ██ ██   ██ ██              #
#         ██ ████ ██ █████      ██    ███████ ██    ██ ██   ██ ███████         #
#         ██  ██  ██ ██         ██    ██   ██ ██    ██ ██   ██      ██         #
#         ██      ██ ███████    ██    ██   ██  ██████  ██████  ███████         #
func                        _________METHODS_________              ()->void:pass

## Assign [member hooks] when it is still empty.
## [TestBase] and [CaseSession] both carry that property.
static func install( test:Object ) -> void:
	if test == null:
		return
	if test.get(&"hooks") != null:
		return
	var capture := TracyCapture.new()
	capture._test = test
	var lvl:Variant = test.get(&'local_lvl')
	if lvl is int:
		var level:int = lvl
		capture.local_lvl = level
	test.set(&"hooks", capture)


## Install when the saved flag is on and this binary registered the Profiler singleton.
static func install_saved( test:Object ) -> void:
	if is_instance_valid(test) \
	and Engine.has_singleton(&'Profiler'):
		if TestRunnerOpts.shared().tracy:
			install(test)


## Launch the capture and wait until this process accepts it.
func pre() -> Error:
	if _test == null:
		_log_err("no owner")
		return ERR_UNCONFIGURED

	_profiler = Engine.get_singleton(&'Profiler')
	if _profiler == null:
		_log_err("Profiler singleton is missing. This binary has no Tracy client.")
		return ERR_UNAVAILABLE

	var was_v:Variant = _profiler.call(&'is_enabled')
	_profiler_was_enabled = was_v if was_v is bool else false

	# Silence before the handshake. Recording turns on before the test's [method _setup].
	_arm_profiler = true
	_profiler.call(&'set_enabled', false)

	if Profiler.is_server_connected():
		_log_wrn("Tracy server is already connected")
		_capture_connected = true
		if _arm_profiler and _profiler != null:
			_enable_categories()
			_enable_features()
			_profiler.call(&'set_enabled', true)
		_server_already_connected = true
		_listen_server_disconnected()
		return OK

	var connected_sig:Signal = Signal(_profiler, &'server_connected')
	if not connected_sig.is_connected(_on_server_connected):
		@warning_ignore("return_value_discarded")
		connected_sig.connect(_on_server_connected)

	var tree:SceneTree = _scene_tree()
	if tree == null:
		_log_err("no SceneTree")
		return ERR_UNCONFIGURED

	_ensure_timer(tree)

	var exe:String = _capture_exe()
	if exe.is_empty():
		_log_err("tracy-capture was not found")
		return ERR_FILE_NOT_FOUND

	var script_path:String = _script_path()
	var capture_file:String = script_path.get_basename() + ".tracy"
	_trace_path = ProjectSettings.globalize_path(capture_file)
	_log_note("script %s" % script_path)

	_capture_connected = false
	var window_sec:int = _capture_window_sec()
	_window_sec = window_sec
	_capture_budget_msec = window_sec * 1000 + CAPTURE_TIMEOUT_MSEC
	var _capture_cmd := PackedStringArray([
		"-o", _trace_path,
		"-a", "127.0.0.1",
		"-p", str(Profiler.get_port()),
		"-f",
		"-s", str(window_sec),
	])
	Log.lvl(Log.Level.DEBUG, "tracy-capture " + " ".join(_capture_cmd), _test)
	capture_launched_msec = Time.get_ticks_msec()
	_capture_pid = OS.create_process(exe, _capture_cmd, false)
	if _capture_pid < 0:
		_restore_profiler()
		_log_err("tracy-capture failed to start")
		return ERR_CANT_CREATE
	_log_note("capture %s pid=%d port=%d window=%ds" % [
		capture_file, _capture_pid, Profiler.get_port(), window_sec,
	])

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
		_log_err("timed out waiting for tracy-capture to connect on port %d." % Profiler.get_port())
		return ERR_CANT_CONNECT

	if not _capture_connected:
		_stop_capture()
		_log_err("tracy-capture did not connect on port %d." % Profiler.get_port())
		return ERR_CANT_CONNECT

	capture_started_msec = Time.get_ticks_msec()

	# tracy enabled/disabled is deferred until the end of a frame, so if one
	# hasnt passed since we enabled it, we can delay one before moving forward.
	if _scene_tree().get_frame() == capture_started_frame:
		await _scene_tree().physics_frame
	_listen_server_disconnected()
	return OK


## Wait until the capture process saves the file, then crop it.
func post() -> Error:
	# The procedure has returned. An early disconnect can be reported now.
	# The listener stays up so a disconnect during the capture wait is timed too.
	_mark_procedure_end()
	if _server_already_connected:
		_drop_server_disconnected()
		_restore_categories()
		_restore_features()
		_profiler.call(&'set_enabled', _profiler_was_enabled)
		return OK

	# Silence before the wait. The capture process is still connected, and this thread keeps framing.
	var tree:SceneTree = _scene_tree()
	if tree == null:
		_log_err("no SceneTree")
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
	and Time.get_ticks_msec() - capture_launched_msec < _capture_budget_msec:
		await tree.process_frame

	var still_running:bool = _capture_pid >= 0 \
	and OS.is_process_running(_capture_pid)

	if still_running:
		_stop_capture()
		return ERR_TIMEOUT

	capture_ended_msec = Time.get_ticks_msec()
	if _disconnect_msec <= 0:
		_disconnect_msec = capture_ended_msec
	_report_gap()
	_remember_pad()
	_capture_pid = -1
	_restore_profiler()
	var cropped:Error = _crop_trace()
	if cropped != OK:
		return cropped

	return OK


func _log_err(content:Variant) -> void:
	Log.err(content, _test)


func _log_wrn(content:Variant) -> void:
	Log.wrn(content, _test)


func _log_note(content:Variant) -> void:
	Log.lvl(Log.Level.NOTICE, content, _test)


## Write [param text] into the open capture.
func message(text:String) -> void:
	# [method Profiler.message] is dropped while recording is silenced.
	if _profiler == null:
		return
	_profiler.call(&'message', text)


func _scene_tree() -> SceneTree:
	if _test == null:
		return null
	var found:Variant = _test.get(&'scene_tree')
	if found == null:
		found = _test.get(&'tree')
	if found is SceneTree:
		var tree:SceneTree = found
		return tree
	return null


## Case script path when the owner has one. Otherwise the owner's own script.
func _script_path() -> String:
	if _test == null:
		return ""
	var named:Variant = _test.get(&'path')
	if named is String:
		var path:String = named
		if path.ends_with(".gd"):
			return path
	var scr:Script = _test.get_script()
	if scr == null:
		return ""
	return scr.resource_path


func _budget_s() -> float:
	if _test == null:
		return 1.0
	var found:Variant = _test.get(&'harness_time_s')
	if found == null:
		found = _test.get(&'budget_s')
	if found is float:
		var number:float = found
		return maxf(number, 0.0)
	if found is int:
		var counted:int = found
		return maxf(float(counted), 0.0)
	return 1.0


func _seconds( key:StringName ) -> float:
	if _test == null:
		return -1.0
	var found:Variant = _test.get(key)
	if found is float:
		var number:float = found
		return number
	if found is int:
		var counted:int = found
		return float(counted)
	return -1.0


func _msec( key:StringName ) -> int:
	if _test == null:
		return 0
	var found:Variant = _test.get(key)
	if found is int:
		var counted:int = found
		return counted
	return 0


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
		_log_wrn( "Timer was not removed in last run.")
		old_timer.queue_free()

	timer = Timer.new()
	timer.one_shot = true
	timer.name = "TracyCaptureTimer"
	scene_tree.root.add_child(timer)


## [signal Profiler.server_connected]. The capture process is that server.
func _on_server_connected() -> void:
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


## Listen for [signal Profiler.server_disconnected] until the capture wait ends.
func _listen_server_disconnected() -> void:
	if _profiler == null:
		return
	var disconnected_sig:Signal = Signal(_profiler, &'server_disconnected')
	if disconnected_sig.is_connected(_on_server_disconnected):
		return
	@warning_ignore("return_value_discarded")
	disconnected_sig.connect(_on_server_disconnected)


## Drop the disconnect watch.
func _drop_server_disconnected() -> void:
	if _profiler == null:
		return
	var disconnected_sig:Signal = Signal(_profiler, &'server_disconnected')
	if disconnected_sig.is_connected(_on_server_disconnected):
		disconnected_sig.disconnect(_on_server_disconnected)


## [signal Profiler.server_disconnected]. Stamp the time and report once the procedure has ended.
func _on_server_disconnected() -> void:
	if _disconnect_msec > 0:
		return
	_disconnect_msec = Time.get_ticks_msec()
	if _procedure_end_msec > 0:
		_report_gap()


## Record the procedure end. A server that has already left is stamped from the handshake.
func _mark_procedure_end() -> void:
	_procedure_end_msec = Time.get_ticks_msec()
	if _disconnect_msec > 0 or _profiler == null:
		_report_gap()
		return
	var connected_v:Variant = _profiler.call(&'is_server_connected')
	var connected:bool = connected_v if connected_v is bool else false
	if connected:
		return
	_disconnect_msec = _estimate_disconnect_msec()
	_report_gap()


## [code]-s[/code] deadline when the frame mark has not emitted the signal yet.
func _estimate_disconnect_msec() -> int:
	var now:int = Time.get_ticks_msec()
	if capture_started_msec <= 0 or _window_sec <= 0:
		return now
	var deadline:int = capture_started_msec + _window_sec * 1000
	if deadline > 0 and deadline < now:
		return deadline
	return now


## Warn with the gap, and a budget change when the window would move.
func _report_gap() -> void:
	if _gap_reported or _procedure_end_msec <= 0 or _disconnect_msec <= 0:
		return
	_gap_reported = true
	var where:String = _script_path()
	if where.is_empty():
		where = "unknown test"
	var early_ms:int = _procedure_end_msec - _disconnect_msec
	if early_ms > 0:
		_report_early(where, early_ms)
		return
	_report_late(where, -early_ms)


## The capture ended while the procedure was still running.
func _report_early( where:String, early_ms:int ) -> void:
	var early_s:float = early_ms / 1000.0
	var suggestion:String = _early_suggestion()
	if suggestion.is_empty():
		_log_wrn("Tracy server disconnected %.3fs before the test finished: %s" % [early_s, where])
		return
	_log_wrn("Tracy server disconnected %.3fs before the test finished: %s. %s" % [early_s, where, suggestion])


## The capture stayed open after the procedure. One second of slack is allowed.
func _report_late( where:String, slack_ms:int ) -> void:
	if slack_ms <= 0 or _test == null or _window_sec <= 0 or capture_started_msec <= 0:
		return
	var slack_s:float = slack_ms / 1000.0
	if slack_s <= _LATE_ALLOWANCE_S:
		return
	var used_s:float = (_procedure_end_msec - capture_started_msec) / 1000.0
	var needed:int = maxi(1, ceili(used_s + _LATE_ALLOWANCE_S))
	if needed >= _window_sec:
		return
	var pad:float = _pad_s()
	var suggested:float = _harness_for_window(needed, pad, _observed_procedure_s())
	if _window_for(suggested, pad) >= _window_sec:
		return
	if suggested >= _budget_s() - 0.0005:
		return
	_log_wrn("Tracy capture stayed open %.3fs after the test finished: %s. Lower %s from %.3f to %.3f." % [
		slack_s, where, _budget_label(), _budget_s(), suggested,
	])


## Raise the budget far enough that [code]-s[/code] still covers the procedure.
func _early_suggestion() -> String:
	if _test == null or _window_sec <= 0 or capture_started_msec <= 0:
		return ""
	var used_s:float = (_procedure_end_msec - capture_started_msec) / 1000.0
	var needed:int = maxi(_window_sec + 1, ceili(used_s))
	var suggested:float = _harness_for_window(needed, _pad_s(), _observed_procedure_s())
	return "Raise %s from %.3f to %.3f." % [_budget_label(), _budget_s(), suggested]


## Setup, the body, and cleanup, or the span from the harness mark when a phase did not finish.
func _observed_procedure_s() -> float:
	if _test == null:
		return 0.0
	var setup_s:float = _seconds(&'setup_s')
	var run_s:float = _seconds(&'run_s')
	var cleanup_s:float = _seconds(&'cleanup_s')
	if setup_s >= 0.0 and run_s >= 0.0 and cleanup_s >= 0.0:
		return setup_s + run_s + cleanup_s
	var mark:int = _msec(&'harness_mark_msec')
	if mark > 0 and _procedure_end_msec > mark:
		return (_procedure_end_msec - mark) / 1000.0
	return 0.0


## Smallest budget whose capture window is at least [param needed_window] seconds.
func _harness_for_window( needed_window:int, pad:float, floor_s:float ) -> float:
	var suggested:float = maxf(floor_s, float(needed_window) - pad)
	if suggested < 0.0:
		suggested = 0.0
	if ceili(suggested + pad) < needed_window:
		suggested = maxf(floor_s, float(needed_window - 1) + 0.001 - pad)
	return suggested


## Whole-second capture window for one budget and pad.
func _window_for( harness:float, pad:float ) -> int:
	return maxi(1, ceili(harness + pad))


## [member TestBase.harness_time_s] or [member CaseSession.budget_s].
func _budget_label() -> String:
	if _test != null and _test.get(&'harness_time_s') != null:
		return "harness_time_s"
	return "budget_s"


## Capture executable, Python, and both crop scripts all resolve to files.
static func is_configured() -> bool:
	return not _capture_exe().is_empty() \
		and not _python_exe().is_empty() \
		and not _tracy_script_dir().is_empty()


## First existing [code]tracy-capture[/code], or [code]TRACY_CAPTURE[/code] when that file exists.
static func _capture_exe() -> String:
	# A saved path is the one the dock was given. It does not fall through to the guess.
	var configured:String = TestRunnerOpts.shared().tracy_capture
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


## Put the profiler back and drop the connection listeners.
func _restore_profiler() -> void:
	# [method pre] silenced the engine. Put the previous enabled state back.
	_drop_server_disconnected()
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
			_log_err("tracy-capture did not die")
	_capture_pid = -1
	_restore_profiler()


## Trim the saved tail, then drop the startup frames. The file at [member _trace_path] is the result.
func _crop_trace() -> Error:
	# Both scripts refuse an output path equal to the input, so the crop lands in temps first.
	if _trace_path.is_empty() or not FileAccess.file_exists(_trace_path):
		_log_err("tracy capture was not saved")
		return ERR_FILE_NOT_FOUND
	var python:String = _python_exe()
	if python.is_empty():
		# Trimming is optional. The raw capture is still a successful result.
		_log_wrn("python was not found. Raw capture left at " + _trace_path)
		return OK
	var scripts:String = _tracy_script_dir()
	if scripts.is_empty():
		_log_wrn("tracy python scripts were not found. Set TRACY_SCRIPTS to that folder.")
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
static func _python_exe() -> String:
	# [method OS.execute] starts the path itself. A bare [code]python[/code] on [code]PATH[/code] is not enough.
	# A saved path is the one the dock was given. It does not fall through to the guess.
	var configured:String = TestRunnerOpts.shared().python_exe
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


## [code]-s[/code] is the declared harness time plus the stored pad, in whole seconds.
func _capture_window_sec() -> int:
	return maxi(1, ceili(_budget_s() + _pad_s()))


## Stored pad. One second until a measured run replaces it.
static func _pad_s() -> float:
	return maxf(TestRunnerOpts.shared().tracy_pad_s, 0.0)


static func _pad_samples() -> int:
	return maxi(TestRunnerOpts.shared().tracy_pad_samples, 0)


## Fold one measured pad into the setting. The mean keeps the last 32 samples.
static func _store_pad(sample:float) -> void:
	var n:int = _pad_samples()
	var avg:float = _pad_s()
	var next:float = maxf(sample, 0.0)
	var next_n:int = 1
	if n > 0:
		var weight:int = mini(n, 31)
		next = (avg * float(weight) + sample) / float(weight + 1)
		next_n = mini(n + 1, 32)
	var opts := TestRunnerOpts.shared()
	opts.tracy_pad_s = next
	opts.tracy_pad_samples = next_n


func _remember_pad() -> void:
	if _test == null \
	or capture_launched_msec <= 0 \
	or capture_ended_msec <= 0:
		return
	var setup_s:float = _seconds(&'setup_s')
	var run_s:float = _seconds(&'run_s')
	var cleanup_s:float = _seconds(&'cleanup_s')
	if setup_s < 0.0 \
	or run_s < 0.0 \
	or cleanup_s < 0.0:
		_log_note("capture ended with phases incomplete")
		Log.lvl(Log.Level.DEBUG, "capture start=%d end=%d" % [
			capture_launched_msec, capture_ended_msec,
		], _test)
		return
	var wall:float = (capture_ended_msec - capture_launched_msec) / 1000.0
	var harness:float = setup_s + run_s + cleanup_s
	# Time from launch until setup. Folding wall-minus-harness would grow every run,
	# because [code]-s[/code] holds the process open for the whole window.
	var sample:float = 0.0
	var mark:int = _msec(&'harness_mark_msec')
	if mark > capture_launched_msec:
		sample = (mark - capture_launched_msec) / 1000.0
	_log_note("capture wall=%.3f harness=%.3f pad=%.3f start=%d end=%d" % [
		wall, harness, sample, capture_launched_msec, capture_ended_msec,
	])
	_store_pad(sample)


## Folder that holds both crop scripts, or [code]TRACY_SCRIPTS[/code] when that folder has them.
static func _tracy_script_dir() -> String:
	# trim_tracy_tail.py imports shift_tracy_start from this same folder.
	var configured:String = TestRunnerOpts.shared().tracy_scripts
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
static func _tracy_scripts_present(folder:String) -> bool:
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
		_log_wrn("tracy script failed (" + str(code) + ") " + script.get_file() + "\n" + _crop_note(text))
		return ERR_SCRIPT_FAILED
	if not text.is_empty():
		_log_note(_crop_note(text))
	return OK


## Success text from a crop script. Drops the project root and keeps the file name.
func _crop_note(text:String) -> String:
	var root:String = ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")
	var note:String = ""
	for raw:String in text.split("\n"):
		var line:String = raw.replace("\\", "/")
		if not root.is_empty():
			line = line.replace(root + "/", "")
		if not note.is_empty():
			note += "\n"
		note += _wrote_file(line)
	return note


func _wrote_file(line:String) -> String:
	var mark:String = "wrote "
	if not line.begins_with(mark):
		return line
	var rest:String = line.substr(mark.length())
	var colon:int = rest.find(": ")
	if colon < 0:
		return line
	return mark + rest.substr(0, colon).get_file() + rest.substr(colon)


## Move [param tight] onto [member _trace_path].
func _install_cropped(tight:String) -> Error:
	# Park the raw capture until the cropped file is in its place.
	var parked:String = _trace_path + ".raw"
	if FileAccess.file_exists(parked):
		var cleared:Error = DirAccess.remove_absolute(parked)
		if cleared != OK:
			_log_wrn("could not clear " + parked)
			return cleared
	var moved:Error = DirAccess.rename_absolute(_trace_path, parked)
	if moved != OK:
		_log_wrn("could not park the raw capture")
		return moved

	var placed:Error = DirAccess.rename_absolute(tight, _trace_path)
	if placed != OK:
		var back:Error = DirAccess.rename_absolute(parked, _trace_path)
		if back != OK:
			_log_wrn("cropped trace is at " + tight + " and the raw capture is at " + parked)
		else:
			_log_wrn("could not install the cropped capture")
		return placed

	var dropped:Error = DirAccess.remove_absolute(parked)
	if dropped != OK:
		_log_wrn("cropped capture is in place. raw copy remains at " + parked)
	return OK


## Remove a crop temp when it is still on disk.
func _drop_file(path:String) -> void:
	# A script that failed before writing leaves no file.
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var removed:Error = DirAccess.remove_absolute(path)
	if removed != OK:
		_log_wrn("could not remove " + path)

@tool
extends TR_Hook

## Capture hook. The runner loads this script and waits on [signal TR_Hook.settled].
##
## [method _pre] runs before setup. [method _post] runs after the procedure,
## including a timeout. Paths, the budget, and the phase times come from
## [member session]. The executable, Python, and pad come from this hook's
## options. The trace is the script's name, the run kind, and [code].tracy[/code],
## in that script's folder.
## The crop is [code]trim_tracy_tail.py[/code] then [code]shift_tracy_start.py[/code]
## [code]--trim-init[/code]. Another Tracy server already attached refuses
## the connection. [signal Profiler.server_disconnected] is watched until the
## capture process exits. A disconnect during the procedure warns and names a
## higher budget. One second open after the procedure is allowed. Past that,
## a lower budget is named when the window would shrink and still leave that second.

const Log = preload( "uid://br7jtx5cntuan" )
const TracyOpts = preload( "tracy_opts.gd" )

# ██████  ██████   ██████  ██████  ███████ ██████  ████████ ██ ███████ ███████ #
# ██   ██ ██   ██ ██    ██ ██   ██ ██      ██   ██    ██    ██ ██      ██      #
# ██████  ██████  ██    ██ ██████  █████   ██████     ██    ██ █████   ███████ #
# ██      ██   ██ ██    ██ ██      ██      ██   ██    ██    ██ ██           ██ #
# ██      ██   ██  ██████  ██      ███████ ██   ██    ██    ██ ███████ ███████ #
func                        ________PROPERTIES_______              ()->void:pass

# tracy-capture process id. -1 until launch.
var _capture_pid:int = -1

# Trace file this capture writes.
var _trace_path:String = ""

# Profiler singleton, and whether it was already enabled.
var _profiler:Object
var _profiler_was_enabled:bool = false

# True when this capture turned the profiler on and must restore it.
var _arm_profiler:bool = false

# Category name to the value from before this capture. Empty until the handshake.
var _saved_categories:Dictionary = {}

# Feature name to the value from before this capture. Empty until the handshake.
var _saved_features:Dictionary = {}

# True when another Tracy server was already attached.
var _server_already_connected:bool = false

# Whole seconds passed to -s. Zero when this capture did not launch one.
var _window_sec:int = 0

# Clock stamps. Launch, the first connected frame, and exit.
var _capture_launched_msec:int = 0
var _capture_started_msec:int
var _capture_started_frame:int
var _capture_ended_msec:int = 0

# Connect wait. Created on the scene tree for this capture.
var _timer:Timer

# How long post waits for -s to close the file.
var _capture_budget_msec:int = 0

# True once the capture process has connected.
var _capture_connected:bool = false

# Milliseconds when the Tracy server left. Zero until that is known.
var _disconnect_msec:int = 0

# Milliseconds when the procedure returned and post began.
var _procedure_end_msec:int = 0

# True after the budget gap has been reported for this capture.
var _gap_reported:bool = false


#          ██████  ██    ██ ███████ ██████  ██████  ██ ██████  ███████         #
#         ██    ██ ██    ██ ██      ██   ██ ██   ██ ██ ██   ██ ██              #
#         ██    ██ ██    ██ █████   ██████  ██████  ██ ██   ██ █████           #
#         ██    ██  ██  ██  ██      ██   ██ ██   ██ ██ ██   ██ ██              #
#          ██████    ████   ███████ ██   ██ ██   ██ ██ ██████  ███████         #
func                        ________OVERRIDE_________              ()->void:pass

static func _hook_opts() -> GDScript:
	return TracyOpts


## Options-list gate. A case constant still runs this script.
func _accept() -> bool:
	var opts:TracyOpts = _opts()
	var on:bool = opts != null and opts.enabled
	return on and is_configured() and Engine.has_singleton( &"Profiler" )


## Launch the capture and wait until this process accepts it.
func _pre() -> Error:
	if session == null:
		Log.err( "no owner" )
		return ERR_UNCONFIGURED

	_profiler = Engine.get_singleton(&'Profiler')
	if _profiler == null:
		session.log( Log.Level.ERROR, "Profiler singleton is missing. This binary has no Tracy client.")
		return ERR_UNAVAILABLE

	var was_v:Variant = _profiler.call(&'is_enabled')
	_profiler_was_enabled = was_v if was_v is bool else false

	# Silence before the handshake. Recording turns on before the test's [method _setup].
	_arm_profiler = true
	_profiler.call(&'set_enabled', false)

	if Profiler.is_server_connected():
		session.log( Log.Level.WARNING, "Tracy server is already connected")
		_capture_connected = true
		_arm_recording()
		_server_already_connected = true
		_listen_server_disconnected()
		return OK

	var connected_sig:Signal = Signal(_profiler, &'server_connected')
	if not connected_sig.is_connected(_on_server_connected):
		@warning_ignore("return_value_discarded")
		connected_sig.connect(_on_server_connected)

	var tree:SceneTree = _scene_tree()
	if tree == null:
		session.log( Log.Level.ERROR, "no SceneTree")
		return ERR_UNCONFIGURED

	_ensure_timer(tree)

	var exe:String = _capture_exe()
	if exe.is_empty():
		_drop_timer()
		session.log( Log.Level.ERROR, "tracy-capture was not found")
		return ERR_FILE_NOT_FOUND

	var script_path:String = _script_path()
	var capture_file:String = _capture_res_path( script_path )
	_trace_path = _absolute_trace( capture_file )
	session.log( Log.Level.NOTICE, "script %s" % script_path)

	_capture_connected = false
	var window_sec:int = _capture_window_sec()
	_window_sec = window_sec
	_capture_budget_msec = window_sec * 1000 + roundi( _capture_timeout_s() * 1000.0 )
	var _capture_cmd := PackedStringArray([
		"-o", _trace_path,
		"-a", "127.0.0.1",
		"-p", str(Profiler.get_port()),
		"-f",
		"-s", str(window_sec),
	])
	session.log( Log.Level.DEBUG, "tracy-capture " + " ".join( _capture_cmd ) )
	_capture_launched_msec = Time.get_ticks_msec()
	_capture_pid = OS.create_process(exe, _capture_cmd, false)
	if _capture_pid < 0:
		_restore_profiler()
		session.log( Log.Level.ERROR, "tracy-capture failed to start")
		return ERR_CANT_CREATE
	session.log( Log.Level.NOTICE, "capture %s pid=%d port=%d window=%ds" % [
		capture_file, _capture_pid, Profiler.get_port(), window_sec,
	])

	# wait for connection using a timer, the connection signal handler will
	# trigger this timers timeout. if there is time left on the clock it
	# succeeded
	var time_left:float = 0.0
	if _capture_pid >= 0 \
	and OS.is_process_running(_capture_pid):
		_timer.start( _connect_wait_s() )
		_timer.paused = false
		await _timer.timeout
		time_left = _timer.time_left

	var connected:bool = _capture_connected
	_drop_timer()

	if not time_left:
		_stop_capture()
		session.log( Log.Level.ERROR, "timed out waiting for tracy-capture to connect on port %d." % Profiler.get_port())
		return ERR_CANT_CONNECT

	if not connected:
		_stop_capture()
		session.log( Log.Level.ERROR, "tracy-capture did not connect on port %d." % Profiler.get_port())
		return ERR_CANT_CONNECT

	_capture_started_msec = Time.get_ticks_msec()

	# tracy enabled/disabled is deferred until the end of a frame, so if one
	# hasnt passed since we enabled it, we can delay one before moving forward.
	if _scene_tree().get_frame() == _capture_started_frame:
		await _scene_tree().physics_frame
	_listen_server_disconnected()
	return OK


## Wait until the capture process saves the file, then crop it.
func _post() -> Error:
	# The procedure has returned. An early disconnect can be reported now.
	# The listener stays up so a disconnect during the capture wait is timed too.
	_mark_procedure_end()
	if _server_already_connected:
		_drop_server_disconnected()
		_restore_masks()
		_profiler.call(&'set_enabled', _profiler_was_enabled)
		return OK

	# Silence before the wait. The capture process is still connected, and this thread keeps framing.
	var tree:SceneTree = _scene_tree()
	if tree == null:
		session.log( Log.Level.ERROR, "no SceneTree")
		_restore_profiler()
		return ERR_UNCONFIGURED

	_arm_profiler = false
	_profiler.call(&'set_enabled', false)
	# tracy enabled/disabled is deferred until the end of a frame, so we need
	# to wait or we end up adding noise to the trace.
	await tree.physics_frame

	_restore_masks()

	# [code]-s[/code] ends the process. Killing it would drop the file.
	while _capture_pid >= 0 \
	and OS.is_process_running(_capture_pid) \
	and Time.get_ticks_msec() - _capture_launched_msec < _capture_budget_msec:
		await tree.process_frame

	var still_running:bool = _capture_pid >= 0 \
	and OS.is_process_running(_capture_pid)

	if still_running:
		_stop_capture()
		return ERR_TIMEOUT

	_capture_ended_msec = Time.get_ticks_msec()
	if _disconnect_msec <= 0:
		_disconnect_msec = _capture_ended_msec
	_report_gap()
	_remember_pad()
	_capture_pid = -1
	_restore_profiler()
	var cropped:Error = _crop_trace()
	return cropped


## Write [param text] into the open capture.
func _message( text:String ) -> void:
	# [method Profiler.message] is dropped while recording is silenced.
	if _profiler == null:
		return
	_profiler.call( &'message', text )


#       ██ ███    ██ ████████ ███████ ██████  ███    ██  █████  ██             #
#       ██ ████   ██    ██    ██      ██   ██ ████   ██ ██   ██ ██             #
#       ██ ██ ██  ██    ██    █████   ██████  ██ ██  ██ ███████ ██             #
#       ██ ██  ██ ██    ██    ██      ██   ██ ██  ██ ██ ██   ██ ██             #
#       ██ ██   ████    ██    ███████ ██   ██ ██   ████ ██   ██ ███████        #
func                        ________INTERNAL_________              ()->void:pass

#region Session - Case session fields and the trace path.
#MARK: Session
func                        __Session________________              ()->void:pass
# │ ___            _
# │/ __| ___ _____(_)___ _ _
# │\__ \/ -_|_-<_-< / _ \ ' \
# │|___/\___/__/__/_\___/_||_|
# ╰────────────────────────────

static func _opts() -> TracyOpts:
	return TracyOpts.shared() as TracyOpts


func _owner() -> Object:
	return session


func _scene_tree() -> SceneTree:
	if session == null:
		return null
	return session.tree


## [code]res://[/code] trace path. The run kind keeps each launch's file.
func _capture_res_path( script_path:String ) -> String:
	return "%s.%s.tracy" % [ script_path.get_basename(), _run_kind() ]


## editorscript when the owner does not name a launch.
func _run_kind() -> String:
	if session == null or session.run_kind.is_empty():
		return "editorscript"
	return session.run_kind


## Native path beside the script. A pack has no project directory, so [code]CASE_PROJECT[/code] supplies it.
func _absolute_trace( res_path:String ) -> String:
	var native:String = ProjectSettings.globalize_path( res_path )
	if native.is_absolute_path():
		return native
	var root:String = OS.get_environment( "CASE_PROJECT" )
	if root.is_empty():
		return native
	return root.path_join( native )


## TR_Case script path when the owner has one. Otherwise the owner's own script.
func _script_path() -> String:
	if session == null or not session.case_path.ends_with( ".gd" ):
		return ""
	return session.case_path


func _budget_s() -> float:
	if session == null:
		return 1.0
	return maxf( session.budget_s, 0.0 )


#endregion Session

#region Connect - Timer and the Tracy server handshake.
#MARK: Connect
func                        __Connect________________              ()->void:pass
# │  ___                      _
# │ / __|___ _ _  _ _  ___ __| |_
# │| (__/ _ \ ' \| ' \/ -_) _|  _|
# │ \___\___/_||_|_||_\___\__|\__|
# ╰────────────────────────────────

func _drop_timer() -> void:
	if _timer == null:
		return

	if is_instance_valid( _timer ):
		_timer.queue_free()

	_timer = null


func _ensure_timer( scene_tree:SceneTree ) -> void:
	_drop_timer()
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.name = "TracyCaptureTimer"
	scene_tree.root.add_child( _timer )


## Apply the selected categories and features, then enable the profiler.
## The profiler stays a singleton call.
func _arm_recording() -> void:
	if not _arm_profiler or _profiler == null:
		return

	var opts:TracyOpts = _opts()
	if opts == null:
		return

	_apply_mask( TracyOpts.CATEGORY_NAMES, opts.categories, _saved_categories, &"is_category_enabled", &"set_category_enabled" )
	_apply_mask( TracyOpts.FEATURE_NAMES, opts.features, _saved_features, &"is_feature_enabled", &"set_feature_enabled" )
	_profiler.call( &'set_enabled', true )


## [signal Profiler.server_connected]. The capture process is that server.
func _on_server_connected() -> void:
	# Same mark as the handshake. Unsilence applies in this flush, then the cases run.
	_capture_connected = true
	_arm_recording()
	if _arm_profiler and _profiler != null:
		_capture_started_frame = _scene_tree().get_frame()

	_timer.paused = true
	_timer.timeout.emit()


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


#endregion Connect

#region Gap - Disconnect against the procedure.
#MARK: Gap
func                        __Gap____________________              ()->void:pass
# │  ___
# │ / __|__ _ _ __
# │| (_ / _` | '_ \
# │ \___\__,_| .__/
# ╰──────────|_|────

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
	if _capture_started_msec <= 0 or _window_sec <= 0:
		return now
	var deadline:int = _capture_started_msec + _window_sec * 1000
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
		session.log( Log.Level.WARNING, "Tracy server disconnected %.3fs before the test finished: %s" % [early_s, where])
		return
	session.log( Log.Level.WARNING, "Tracy server disconnected %.3fs before the test finished: %s. %s" % [early_s, where, suggestion])


## The capture stayed open after the procedure. Slack within [member TracyOpts.late_allowance_s] is allowed.
func _report_late( where:String, slack_ms:int ) -> void:
	if slack_ms <= 0 or _owner() == null or _window_sec <= 0 or _capture_started_msec <= 0:
		return
	var slack_s:float = slack_ms / 1000.0
	var allowance:float = _late_allowance_s()
	if slack_s <= allowance:
		return
	var used_s:float = (_procedure_end_msec - _capture_started_msec) / 1000.0
	var needed:int = maxi( 1, ceili( used_s + allowance ) )
	if needed >= _window_sec:
		return
	var pad:float = _pad_s()
	var suggested:float = _harness_for_window(needed, pad, _observed_procedure_s())
	if _window_for(suggested, pad) >= _window_sec:
		return
	if suggested >= _budget_s() - 0.0005:
		return
	session.log( Log.Level.WARNING, "Tracy capture stayed open %.3fs after the test finished: %s. Lower %s from %.3f to %.3f." % [
		slack_s, where, _budget_label(), _budget_s(), suggested,
	])


## Raise the budget far enough that [code]-s[/code] still covers the procedure.
func _early_suggestion() -> String:
	if _owner() == null or _window_sec <= 0 or _capture_started_msec <= 0:
		return ""
	var used_s:float = (_procedure_end_msec - _capture_started_msec) / 1000.0
	var needed:int = maxi(_window_sec + 1, ceili(used_s))
	var suggested:float = _harness_for_window(needed, _pad_s(), _observed_procedure_s())
	return "Raise %s from %.3f to %.3f." % [_budget_label(), _budget_s(), suggested]


## Setup, the body, and cleanup, or the span from the harness mark when a phase did not finish.
func _observed_procedure_s() -> float:
	if session == null:
		return 0.0

	if session.setup_s >= 0.0 and session.run_s >= 0.0 and session.cleanup_s >= 0.0:
		return session.setup_s + session.run_s + session.cleanup_s

	if session.harness_mark_msec > 0 and _procedure_end_msec > session.harness_mark_msec:
		return ( _procedure_end_msec - session.harness_mark_msec ) / 1000.0

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


## [member TR_CaseSession.budget_s].
func _budget_label() -> String:
	return "budget_s"


#endregion Gap

#region Tools - Capture executable, Python, and the crop scripts.
#MARK: Tools
func                        __Tools__________________              ()->void:pass
# │ _____         _
# │|_   _|__  ___| |___
# │  | |/ _ \/ _ \ (_-<
# │  |_|\___/\___/_/__/
# ╰─────────────────────

## Capture executable, Python, and both crop scripts all resolve to files.
static func is_configured() -> bool:
	return not _capture_exe().is_empty() \
		and not _python_exe().is_empty() \
		and not _tracy_script_dir().is_empty()


## Saved file, or [code]TRACY_CAPTURE[/code] when the saved path is empty.
static func _capture_exe() -> String:
	var opts:TracyOpts = _opts()
	var configured:String = ""
	if opts != null:
		configured = opts.capture_exe

	return _saved_or_env( configured, "TRACY_CAPTURE", false )


## Saved [code]python.exe[/code], or [code]TRACY_PYTHON[/code] when the saved path is empty.
static func _python_exe() -> String:
	# [method OS.execute] starts the path itself. A bare [code]python[/code] on [code]PATH[/code] is not enough.
	var opts:TracyOpts = _opts()
	var configured:String = ""
	if opts != null:
		configured = opts.python_exe

	return _saved_or_env( configured, "TRACY_PYTHON", false )


## Folder of both crop scripts, or [code]TRACY_SCRIPTS[/code] when the saved path is empty.
static func _tracy_script_dir() -> String:
	var opts:TracyOpts = _opts()
	var configured:String = ""
	if opts != null:
		configured = opts.capture_scripts

	return _saved_or_env( configured, "TRACY_SCRIPTS", true )


## A non-empty [param configured] path does not fall through to [param env_name].
static func _saved_or_env( configured:String, env_name:String, directory:bool ) -> String:
	if not configured.is_empty():
		if _path_ok( configured, directory ):
			return configured

		return ""

	var from_env:String = OS.get_environment( env_name )
	if _path_ok( from_env, directory ):
		return from_env

	return ""


static func _path_ok( path:String, directory:bool ) -> bool:
	if path.is_empty():
		return false

	if directory:
		return _tracy_scripts_present( path )

	return FileAccess.file_exists( path )


#endregion Tools

#region Profiler - Category and feature masks.
#MARK: Profiler
func                        __Profiler_______________              ()->void:pass
# │ ___          __ _ _
# │| _ \_ _ ___ / _(_) |___ _ _
# │|  _/ '_/ _ \  _| | / -_) '_|
# │|_| |_| \___/_| |_|_\___|_|
# ╰──────────────────────────────

## Snapshot [param names], then write each bit of [param mask]. A second call keeps the first snapshot.
func _apply_mask( names:PackedStringArray, mask:int, saved:Dictionary, read_name:StringName, write_name:StringName ) -> void:
	if _profiler == null or not saved.is_empty():
		return

	for index:int in names.size():
		var entry:String = names[ index ]
		var on_v:Variant = _profiler.call( read_name, entry )
		var was_on:bool = on_v if on_v is bool else false
		saved[ entry ] = was_on
		var want:bool = ( mask & ( 1 << index ) ) != 0
		_profiler.call( write_name, entry, want )


## Write [param saved] back, then clear it.
func _restore_mask( saved:Dictionary, write_name:StringName ) -> void:
	if _profiler == null:
		saved.clear()
		return

	for entry:String in saved:
		var stored:Variant = saved[entry]
		var was_on:bool = stored if stored is bool else false
		_profiler.call( write_name, entry, was_on )

	saved.clear()


func _restore_masks() -> void:
	_restore_mask( _saved_categories, &"set_category_enabled" )
	_restore_mask( _saved_features, &"set_feature_enabled" )


## Put the profiler back and drop the connection listeners.
func _restore_profiler() -> void:
	# [method _pre] silenced the engine. Put the previous enabled state back.
	_drop_timer()
	_drop_server_disconnected()
	_arm_profiler = false
	if _profiler != null:
		var connected_sig:Signal = Signal(_profiler, &'server_connected')
		if connected_sig.is_connected(_on_server_connected):
			connected_sig.disconnect(_on_server_connected)
		_restore_masks()
		_profiler.call(&'set_enabled', _profiler_was_enabled)
	_profiler = null


## End a capture that will not save.
func _stop_capture() -> void:
	# [method OS.kill] does not flush the trace. Use it only when the process failed to connect.
	if _capture_pid >= 0 \
	and OS.is_process_running(_capture_pid):
		var killed:Error = OS.kill(_capture_pid)
		if killed != OK:
			session.log( Log.Level.ERROR, "tracy-capture did not die")
	_capture_pid = -1
	_restore_profiler()


#endregion Profiler

#region Window - Declared window and the measured pad.
#MARK: Window
func                        __Window_________________              ()->void:pass
# │__      ___         _
# │\ \    / (_)_ _  __| |_____ __ __
# │ \ \/\/ /| | ' \/ _` / _ \ V  V /
# │  \_/\_/ |_|_||_\__,_\___/\_/\_/
# ╰──────────────────────────────────

## [code]-s[/code] is the declared harness time plus the stored pad, in whole seconds.
func _capture_window_sec() -> int:
	return maxi(1, ceili(_budget_s() + _pad_s()))


static func _connect_wait_s() -> float:
	var opts:TracyOpts = _opts()
	if opts == null:
		return 3.0
	return maxf( opts.connect_wait_s, 0.0 )



static func _capture_timeout_s() -> float:
	var opts:TracyOpts = _opts()
	if opts == null:
		return 3.0
	return maxf( opts.capture_timeout_s, 0.0 )


static func _late_allowance_s() -> float:
	var opts:TracyOpts = _opts()
	if opts == null:
		return 1.0
	return maxf( opts.late_allowance_s, 0.0 )



## Stored pad. One second until a measured run replaces it.
static func _pad_s() -> float:
	var opts:TracyOpts = _opts()
	if opts == null:
		return 0.0
	return maxf( opts.pad_s, 0.0 )


static func _pad_samples() -> int:
	var opts:TracyOpts = _opts()
	if opts == null:
		return 0
	return maxi( opts.pad_samples, 0 )


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
	var opts:TracyOpts = _opts()
	if opts == null:
		return
	opts.pad_s = next
	opts.pad_samples = next_n


func _remember_pad() -> void:
	if session == null \
	or _capture_launched_msec <= 0 \
	or _capture_ended_msec <= 0:
		return
	var setup_s:float = session.setup_s
	var run_s:float = session.run_s
	var cleanup_s:float = session.cleanup_s
	if setup_s < 0.0 \
	or run_s < 0.0 \
	or cleanup_s < 0.0:
		session.log( Log.Level.NOTICE, "capture ended with phases incomplete")
		session.log( Log.Level.DEBUG, "capture start=%d end=%d" % [
			_capture_launched_msec, _capture_ended_msec,
		] )
	var wall:float = (_capture_ended_msec - _capture_launched_msec) / 1000.0
	var harness:float = setup_s + run_s + cleanup_s
	# Time from launch until setup. Folding wall-minus-harness would grow every run,
	# because [code]-s[/code] holds the process open for the whole window.
	var sample:float = 0.0
	var mark:int = session.harness_mark_msec
	if mark > _capture_launched_msec:
		sample = (mark - _capture_launched_msec) / 1000.0
	session.log( Log.Level.NOTICE, "capture wall=%.3f harness=%.3f pad=%.3f start=%d end=%d" % [
		wall, harness, sample, _capture_launched_msec, _capture_ended_msec,
	])
	_store_pad(sample)


#endregion Window

#region Crop - Trim the tail and shift the start.
#MARK: Crop
func                        __Crop___________________              ()->void:pass
# │  ___
# │ / __|_ _ ___ _ __
# │| (__| '_/ _ \ '_ \
# │ \___|_| \___/ .__/
# ╰─────────────|_|────

## Trim the saved tail, then drop the startup frames. The file at [member _trace_path] is the result.
func _crop_trace() -> Error:
	# Both scripts refuse an output path equal to the input, so the crop lands in temps first.
	if _trace_path.is_empty() or not FileAccess.file_exists(_trace_path):
		session.log( Log.Level.ERROR, "tracy capture was not saved")
		return ERR_FILE_NOT_FOUND
	var python:String = _python_exe()
	if python.is_empty():
		# Trimming is optional. The raw capture is still a successful result.
		session.log( Log.Level.WARNING, "python was not found. Raw capture left at " + _trace_path)
		return OK
	var scripts:String = _tracy_script_dir()
	if scripts.is_empty():
		session.log( Log.Level.WARNING, "tracy python scripts were not found. Set TRACY_SCRIPTS to that folder.")
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
	var exit_code:int = OS.execute(python, command, captured, true)
	var text:String = ""
	for chunk:Variant in captured:
		if chunk is String:
			text += chunk
	text = text.strip_edges()
	if exit_code != 0:
		session.log( Log.Level.WARNING, "tracy script failed (" + str(exit_code) + ") " + script.get_file() + "\n" + _crop_note(text))
		return ERR_SCRIPT_FAILED
	if not text.is_empty():
		session.log( Log.Level.NOTICE, _crop_note(text))
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
			session.log( Log.Level.WARNING, "could not clear " + parked)
			return cleared
	var moved:Error = DirAccess.rename_absolute(_trace_path, parked)
	if moved != OK:
		session.log( Log.Level.WARNING, "could not park the raw capture")
		return moved

	var placed:Error = DirAccess.rename_absolute(tight, _trace_path)
	if placed != OK:
		var back:Error = DirAccess.rename_absolute(parked, _trace_path)
		if back != OK:
			session.log( Log.Level.WARNING, "cropped trace is at " + tight + " and the raw capture is at " + parked)
		else:
			session.log( Log.Level.WARNING, "could not install the cropped capture")
		return placed

	var dropped:Error = DirAccess.remove_absolute(parked)
	if dropped != OK:
		session.log( Log.Level.WARNING, "cropped capture is in place. raw copy remains at " + parked)
	return OK


## Remove a crop temp when it is still on disk.
func _drop_file(path:String) -> void:
	# A script that failed before writing leaves no file.
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var removed:Error = DirAccess.remove_absolute(path)
	if removed != OK:
		session.log( Log.Level.WARNING, "could not remove " + path)

#endregion Crop

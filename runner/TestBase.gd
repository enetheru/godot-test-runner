@tool @abstract
class_name TR_Base extends EditorScript

const TR_Opts = preload( "uid://c3rwpcm55iy6r" )
const TR_Gate = preload( "uid://c8rungatehold1" )
const TracyHooks = preload( "uid://c38qii7m273x0" )
const Log = preload( "uid://br7jtx5cntuan" )

## Failure is 0 because a crash returns the default int.
enum RetCode {
	## A crash, an assert, or a body that returned failure.
	TEST_FAILED = 0,

	## The body returned success.
	TEST_OK = 1,
}


#██████  ███████ ███████ ██ ███    ██ ██ ████████ ██  ██████  ███    ██ ███████#
#██   ██ ██      ██      ██ ████   ██ ██    ██    ██ ██    ██ ████   ██ ██     #
#██   ██ █████   █████   ██ ██ ██  ██ ██    ██    ██ ██    ██ ██ ██  ██ ███████#
#██   ██ ██      ██      ██ ██  ██ ██ ██    ██    ██ ██    ██ ██  ██ ██      ██#
#██████  ███████ ██      ██ ██   ████ ██    ██    ██  ██████  ██   ████ ███████#
func                        _______DEFINITIONS_______              ()->void:pass

## Handy Constants
const u32: int = 2083138172				#= |**|
const u32_: int = 2084585596				#= |@@|
const u64: int = 8947009970309311100		#= |******|
const u64_: int = 8953226703912583292	#= |@@@@@@|

## Character Strings that represent the builtin operator values.
static var op_string:PackedStringArray = [
	'==', #  0: OP_EQUAL - Equality operator (==).
	'!=', #  1: OP_NOT_EQUAL - Inequality operator (!=).
	'<',  #  2: OP_LESS - Less than operator (<).
	'<=', #  3: OP_LESS_EQUAL - Less than or equal operator (<=).
	'>',  #  4: OP_GREATER - Greater than operator (>).
	'>=', #  5: OP_GREATER_EQUAL - Greater than or equal operator (>=).
	'+',  #  6: OP_ADD - Addition operator (+).
	'-',  #  7: OP_SUBTRACT - Subtraction operator (-).
	'*',  #  8: OP_MULTIPLY - Multiplication operator (*).
	'/',  #  9: OP_DIVIDE - Division operator (/).
	'-',  # 10: OP_NEGATE - Unary negation operator (-).
	'+',  # 11: OP_POSITIVE - Unary plus operator (+).
	'%',  # 12: OP_MODULE - Remainder/modulo operator (%).
	'**', # 13: OP_POWER - Power operator (**).
	'<<', # 14: OP_SHIFT_LEFT - Left shift operator (<<).
	'>>', # 15: OP_SHIFT_RIGHT - Right shift operator (>>).
	'&',  # 16: OP_BIT_AND - Bitwise AND operator (&).
	'|',  # 17: OP_BIT_OR - Bitwise OR operator (|).
	'^',  # 18: OP_BIT_XOR - Bitwise XOR operator (^).
	'~',  # 19: OP_BIT_NEGATE - Bitwise NOT operator (~).
	'&&', # 20: OP_AND - Logical AND operator (and or &&).
	'||', # 21: OP_OR - Logical OR operator (or or ||).
	'',   # 22: OP_XOR - Logical XOR operator (not implemented in GDScript).
	'!',  # 23: OP_NOT - Logical NOT operator (not or !).
	'in', # 24: OP_IN - Logical IN operator (in).
]

# ██████  ██████   ██████  ██████  ███████ ██████  ████████ ██ ███████ ███████ #
# ██   ██ ██   ██ ██    ██ ██   ██ ██      ██   ██    ██    ██ ██      ██      #
# ██████  ██████  ██    ██ ██████  █████   ██████     ██    ██ █████   ███████ #
# ██      ██   ██ ██    ██ ██      ██      ██   ██    ██    ██ ██           ██ #
# ██      ██   ██  ██████  ██      ███████ ██   ██    ██    ██ ███████ ███████ #
func                        ________PROPERTIES_______              ()->void:pass

# Defaults. A test replaces the budget in [method _configure].

## Filename and path, so two scripts do not share a name.
var test_name:String = str(get_script().resource_path).validate_node_name()

## Inclusive [constant Log.Level]. Notice is quiet. Info and debug raise it.
var local_lvl:int = Log.Level.ERROR

## Budget for setup, the body, and cleanup. Set it in [method _configure].
## The abort timer starts when setup starts. Tracy adds [code]tracy_pad_s[/code].
var harness_time_s:float = 1.0

## Command batch. -1 follows the host. 0 skips capture. 1 installs it for this run.
var capture_request:int = -1

# Read in [method _init] when something set it first. Nothing in this project does.
var _opts:TR_Opts

# [method TR_Gate.enter] hold for this run. Created with the instance. [method _release_pin] drops it.
var _run_hold:TR_Gate.Hold = TR_Gate.create_hold()

# The host assigns these before the body.

## Host assigns this before runs. [method run_test] calls it with this instance
## when [member hooks] is still empty, after the scene tree is ready and before [method _setup].
static var prepare_run:Callable = Callable()

## Editor SceneTree, or a runtime SceneTree, depending on the test.
var scene_tree:SceneTree

## Installed around the procedure. Null skips it. The test keeps this alive.
## TODO, turn hooks into an array
var hooks:TR_Hook

# Written while the run is in progress.

## Milliseconds when setup was about to start. Capture uses this against its launch.
var harness_mark_msec:int = 0

## Measured phase lengths in seconds. Negative means that phase did not finish.
var setup_s:float = -1.0
var run_s:float = -1.0
var cleanup_s:float = -1.0

# Keeps this instance alive for the awaits inside [method _run].
var _cycleref: EditorScript

# Timeout timer. Created for the run and freed after it.
var _timer:Timer

# True after test_finished for this run, timeout or normal complete.
# Makes run_test return on max-runtime even if _run_test is stuck.
var _finished_emitted:bool = false

# Max-runtime timer won the race. A late _run_test completion is ignored.
var _timed_out:bool = false

# True when this run installed Tracy. _apply_opts sets it.
var _test_tracy:bool = false

# Phase flags. Set when that phase returns.
var _setup_done:bool = false
var _setup_error:Error = OK
var _cleanup_done:bool = false
var _cleanup_error:Error = OK

# Result.

## A code used for test output
var runcode:int = RetCode.TEST_OK

## The test output text
var output:Array = []

#            ███████ ██  ██████  ███    ██  █████  ██      ███████             #
#            ██      ██ ██       ████   ██ ██   ██ ██      ██                  #
#            ███████ ██ ██   ███ ██ ██  ██ ███████ ██      ███████             #
#                 ██ ██ ██    ██ ██  ██ ██ ██   ██ ██           ██             #
#            ███████ ██  ██████  ██   ████ ██   ██ ███████ ███████             #
func                        _________SIGNALS_________              ()->void:pass

## triggered immediately after the return of _run_test
signal test_finished

## Triggered at the end of the run_harness function
signal harness_finished


#             ███████ ██    ██ ███████ ███    ██ ████████ ███████              #
#             ██      ██    ██ ██      ████   ██    ██    ██                   #
#             █████   ██    ██ █████   ██ ██  ██    ██    ███████              #
#             ██       ██  ██  ██      ██  ██ ██    ██         ██              #
#             ███████   ████   ███████ ██   ████    ██    ███████              #
func                        __________EVENTS_________              ()->void:pass

## Connected to the timeout timer.
func _on_timer_timeout() -> void:
	_timed_out = true
	runcode = RetCode.TEST_FAILED
	Log.err("Timeout was reached", self)
	test_finished.emit()


#            ██    ██ ██ ██████  ████████ ██    ██  █████  ██                  #
#            ██    ██ ██ ██   ██    ██    ██    ██ ██   ██ ██                  #
#            ██    ██ ██ ██████     ██    ██    ██ ███████ ██                  #
#             ██  ██  ██ ██   ██    ██    ██    ██ ██   ██ ██                  #
#              ████   ██ ██   ██    ██     ██████  ██   ██ ███████             #
func                        _________VIRTUAL_________              ()->void:pass

## Assign [member harness_time_s] here. Runs before capture starts. No await.
func _configure() -> void:
	pass


## Override this function to perform setup prior to testing.
func _setup() -> Error:
	return OK


## Override this function to perform cleanup post testing.
func _cleanup() -> Error:
	return OK


## This is the function to override in derived test functions.
@abstract
func _run_test() -> RetCode


#      ██████  ██    ██ ███████ ██████  ██████  ██ ██████  ███████ ███████     #
#     ██    ██ ██    ██ ██      ██   ██ ██   ██ ██ ██   ██ ██      ██          #
#     ██    ██ ██    ██ █████   ██████  ██████  ██ ██   ██ █████   ███████     #
#     ██    ██  ██  ██  ██      ██   ██ ██   ██ ██ ██   ██ ██           ██     #
#      ██████    ████   ███████ ██   ██ ██   ██ ██ ██████  ███████ ███████     #
func                        ________OVERRIDES________              ()->void:pass

func _init() -> void:
	if _opts != null:
		_apply_opts()


## Calling as an editor script
## this function is intended only to call run_test()
func _run() -> void:
	# NOTE: Maintain a reference to ourself, because no-one else will.
	# Without this, we will be cleaned up before we have had time to do any
	# asynchronous work.
	# As this function itself is a void coroutine, without the self pin it is
	# yielded and immediately cleaned up by the engine.
	_cycleref = self

	Log.lvl(Log.Level.NOTICE, "_run() as editorscript - Started", self)
	run_harness()
	await harness_finished
	_cycleref = null


#         ███    ███ ███████ ████████ ██   ██  ██████  ██████  ███████         #
#         ████  ████ ██         ██    ██   ██ ██    ██ ██   ██ ██              #
#         ██ ████ ██ █████      ██    ███████ ██    ██ ██   ██ ███████         #
#         ██  ██  ██ ██         ██    ██   ██ ██    ██ ██   ██      ██         #
#         ██      ██ ███████    ██    ██   ██  ██████  ██████  ███████         #
func                        _________METHODS_________              ()->void:pass

## The real entry point into the test run, is initially run synchronously,
## but will yield
func run_harness() -> void:
	assert( Thread.is_main_thread(),
		"A run_test() must not be called in a threaded context.\n" + \
		"TR_Base relies on the 'await' keyword and functionality which is." + \
		"not usable in a threaded context.\n")

	_run_hold.open()

	_finished_emitted = false
	_timed_out = false
	_setup_done = false
	_cleanup_done = false
	_setup_error = OK
	_cleanup_error = OK
	setup_s = -1.0
	run_s = -1.0
	cleanup_s = -1.0
	harness_mark_msec = 0

	# Format Dictionary
	var tree_ready:Error = _ensure_scene_tree()
	if tree_ready != OK:
		runcode = RetCode.TEST_FAILED
		Log.err("_run() - no SceneTree", self)
		_cleanup_harness()
		return

	_ensure_timer()
	_configure()

	# Outside the procedure. A host can install capture here, or assign [member hooks] itself.
	# prepare_run is cleared when this script reparses. The saved flag still installs.
	# capture_request is the command override. The panel leaves it at -1.
	if capture_request == 1 and hooks == null:
		TracyHooks.install(self)
	elif capture_request != 0 and hooks == null \
	and not prepare_run.is_valid():
		TracyHooks.install_saved(self)
	elif capture_request != 0 and hooks == null \
	and prepare_run.is_valid():
		prepare_run.call(self)

	@warning_ignore("redundant_await")
	if hooks != null \
	and await hooks.pre() != OK:
		runcode = RetCode.TEST_FAILED
		Log.err("hooks.pre() failed", self)
		_cleanup_harness()
		harness_finished.emit()
		return

	# The budget covers setup, the body, and cleanup. A stuck setup has to lose.
	harness_mark_msec = Time.get_ticks_msec()
	_timer.start(maxf(harness_time_s, 0.001))

	_run_setup()
	if not _setup_done \
	and not _timed_out:
		await test_finished

	if _timed_out:
		await _finish_hooks()
		return

	if not _setup_done \
	or _setup_error != OK:
		runcode = RetCode.TEST_FAILED
		Log.err("_setup() failed", self)
		await _finish_hooks()
		return

	# call_deferred runs inside a message-queue flush, and EditorProgress
	# refuses to open a task there.
	run_test()

	if not _finished_emitted \
	and not _timed_out:
		await test_finished

	if _timed_out:
		await _finish_hooks()
		return

	_run_cleanup()
	if not _cleanup_done \
	and not _timed_out:
		await test_finished

	if is_instance_valid(_timer) \
	and not _timer.is_stopped():
		_timer.stop()

	if not _timed_out \
	and _cleanup_error != OK:
		Log.err("_cleanup() failed", self)
		if runcode == RetCode.TEST_OK:
			runcode = RetCode.TEST_FAILED

	await _finish_hooks()


func _run_setup() -> void:
	var t0:int = Time.get_ticks_msec()
	@warning_ignore("redundant_await")
	_setup_error = await _setup()
	setup_s = (Time.get_ticks_msec() - t0) / 1000.0
	_setup_done = true
	if _timed_out:
		return
	test_finished.emit()


func _run_cleanup() -> void:
	var t0:int = Time.get_ticks_msec()
	@warning_ignore("redundant_await")
	_cleanup_error = await _cleanup()
	cleanup_s = (Time.get_ticks_msec() - t0) / 1000.0
	_cleanup_done = true
	if _timed_out:
		return
	test_finished.emit()


# Reaches `_run_test` outside a message-queue flush.
func run_test() -> void:
	# A sibling coroutine so a stuck `_run_test` still ends on the timer.
	var t0:int = Time.get_ticks_msec()
	@warning_ignore('redundant_await')
	runcode = await _run_test()
	run_s = (Time.get_ticks_msec() - t0) / 1000.0
	_finished_emitted = true
	if _timed_out:
		return
	test_finished.emit()


func _finish_hooks() -> void:
	@warning_ignore("redundant_await")
	if hooks != null \
	and await hooks.post() != OK \
	and runcode == RetCode.TEST_OK:
		runcode = RetCode.TEST_FAILED
		Log.err("hooks.post() failed", self)
	_log_phases()
	_cleanup_harness()
	harness_finished.emit()


func _log_phases() -> void:
	var line:String = "phases setup=%s run=%s cleanup=%s" % [
		_phase_label(setup_s), _phase_label(run_s), _phase_label(cleanup_s),
	]
	Log.lvl(Log.Level.NOTICE, line, self)


func _phase_label(seconds:float) -> String:
	if seconds < 0.0:
		return "skipped"
	return "%.3fs" % seconds


## This binary registered the Profiler singleton. Stock Godot has no such name.
func _tracy_supported() -> bool:
	return Engine.has_singleton(&'Profiler')


## Copy the options onto the log ceiling and the Tracy flag.
func _apply_opts() -> void:
	if _opts != null:
		local_lvl = _opts.lvl
		_test_tracy = _opts.tracy and _tracy_supported() and TracyHooks.is_configured()


# Assign [member scene_tree] from the editor base, or from the main loop.
func _ensure_scene_tree() -> Error:
	# The editor base is the tree while a tool script runs. Otherwise use the main loop.
	if scene_tree != null:
		return OK

	if Engine.is_editor_hint() \
	and DisplayServer.get_name().to_lower() != "headless":
		var base:Object = EditorInterface.get_base_control()
		if base:
			scene_tree = base.call(&'get_tree')

	if scene_tree == null:
		var loop:MainLoop = Engine.get_main_loop()
		if loop is SceneTree:
			scene_tree = loop
	if scene_tree == null:
		return ERR_UNCONFIGURED
	return OK


func _ensure_timer() -> void:
	# Find or create the timeout timer.
	var old_timer:Node = scene_tree.root.find_child(test_name, false)
	if old_timer:
		logd( "Error: Timer was not removed in last run.")
		old_timer.queue_free()

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.name = test_name
	scene_tree.root.add_child(_timer)
	@warning_ignore('return_value_discarded')
	_timer.timeout.connect( _on_timer_timeout )


func _cleanup_harness() -> void:
	if is_instance_valid(_timer):
		_timer.queue_free()
		_timer = null


# Forward [param text] when [member hooks] is installed.
func _profiler_message(text:String) -> void:
	if hooks == null:
		return
	hooks.message(text)


func _note_fail( msg:String ) -> void:
	var block := msg if msg.ends_with( "\n" ) else msg + "\n"
	output.append.call( block )
	_emit_rich( block )


func _emit_rich( msg:Variant ) -> void:
	if not Log.allows( local_lvl, Log.Level.INFO ):
		return
	Log.rich( Log.Level.INFO, msg, self )


## Join output rows. An empty accumulator starts the text.
static func reducer_to_lines( accum:String = "", value:Variant = null ) -> String:
	if accum:
		return accum + "\n" + str( value )
	return str( value )


## [param args] is formatted only when the debug bit is open.
func logd( msg:Variant = "", args:Array = [] ) -> void:
	if not Log.allows( local_lvl, Log.Level.DEBUG ):
		return
	if not args.is_empty():
		msg = msg % args
	elif msg is Array:
		var array:Array = msg
		msg = array.reduce( reducer_to_lines )
	Log.lvl( Log.Level.DEBUG, msg, self )


static func sbytes( bytes:PackedByteArray, cols:int = 8 ) -> String:
	if bytes.is_empty(): return "Empty"
	var retval:Array = ["size: %d" % bytes.size()]
	var position := 0
	while true:
		var slice:PackedByteArray = bytes.slice(position, position + cols)
		if not slice.size(): break

		# new line
		var line:String = ""
		# Position
		line += "%08X: " % position
		# bytes as hex pairs
		for v in slice: line += "%02X " % v
		# pad to width
		line = line.rpad( 10 + cols*3, ' ')
		# ascii
		for v in slice: line += char(v) if v > 32 else '.'

		retval.append(line)
		position += cols
		if slice.size() < cols: break

	return '\n'.join( retval )


static func bytes_view( bytes:PackedByteArray, cols:int = 8 ) -> String:
	return sbytes(bytes, cols)

#                  ████████ ███████ ███████ ████████ ███████                   #
#                     ██    ██      ██         ██    ██                        #
#                     ██    █████   ███████    ██    ███████                   #
#                     ██    ██           ██    ██         ██                   #
#                     ██    ███████ ███████    ██    ███████                   #
func                        __________TESTS__________              ()->void:pass

## Bbcode link to the stack frame at [param depth].
static func _call_site( depth:int = 1 ) -> String:
	var stack:Array = get_stack()
	var frame:Dictionary = stack[mini( stack.size(), depth )]
	return "[url='{source}:{line}']{source}:{line}:{function}()[/url]".format( frame )


# test is abstracted so that exceptions trigger a fail.
func _test_eq( want_v:Variant, got_v:Variant, desc:String = "" ) -> bool:
	if want_v == got_v: return true
	var msg:String = '\n'.join([
		"[b][color=salmon]%s: '%s'[/color][/b]" % [_call_site( 3 ), desc],
		"\twanted: '%s' == got: '%s'" % [want_v, got_v ]])
	# TODO add the call_site to the error message.
	_note_fail( msg )
	return false


## Returns [enum RetCode] 0(TEST_FAILED) on failure, and 1(TEST_OK) on Success.
func TEST_EQ_RET( want_v:Variant, got_v:Variant, desc:String = "" ) -> RetCode:
	logd("TEST_EQ_RET(want:'%s' == got:'%s'): %s", [want_v, got_v, desc])
	if _test_eq(want_v, got_v, desc): return RetCode.TEST_OK
	runcode &= RetCode.TEST_FAILED
	return RetCode.TEST_FAILED


func TEST_EQ( want_v:Variant, got_v:Variant, desc:String = "") -> void:
	logd("TEST_EQ(want:'%s' == got:'%s'): %s", [want_v, got_v, desc])
	if _test_eq(want_v, got_v, desc): return
	runcode &= RetCode.TEST_FAILED


func _test_approx( want_v:float, got_v:float, desc:String = "" ) -> bool:
	if is_equal_approx(want_v, got_v): return true
	var msg:String = '\n'.join([
		"[b][color=salmon]%s: '%s'[/color][/b]" % [_call_site( 3 ), desc],
		"\twanted: '%s' ~= got: '%s'" % [want_v, got_v ]])
	_note_fail( msg )
	return false


## Returns [enum RetCode] 0(TEST_FAILED) on failure, and 1(TEST_OK) on Success.
func TEST_APPROX_RET( want_v:float, got_v:float, desc:String = "" ) -> RetCode:
	logd("TEST_APPROX_RET(want:'%s' ~= got:'%s'): %s", [want_v, got_v, desc])
	if _test_approx(want_v, got_v, desc ): return RetCode.TEST_OK
	runcode &= RetCode.TEST_FAILED
	return RetCode.TEST_FAILED


func TEST_APPROX( want_v:float, got_v:float, desc:String = "" ) -> void:
	logd("TEST_APPROX(want:'%s' ~= got:'%s'): %s", [want_v, got_v, desc])
	if _test_approx(want_v, got_v, desc ): return
	runcode &= RetCode.TEST_FAILED


func _test_true( value:Variant, desc:String = "" ) -> bool:
	if value: return true
	var msg:String = '\n'.join([
		"[b][color=salmon]%s: '%s'[/color][/b]" % [_call_site( 3 ), desc],
		"\twanted: true | value != (0 & null)",
		"\tgot: '%s'" % value])
	_note_fail( msg )
	return false


## Returns [enum RetCode] 0(TEST_FAILED) on failure, and 1(TEST_OK) on Success.
func TEST_TRUE_RET( value:Variant, desc:String = "" ) -> RetCode:
	logd("TEST_TRUE_RET('%s'): %s", [value, desc])
	if _test_true( value, desc ): return RetCode.TEST_OK
	runcode &= RetCode.TEST_FAILED
	return RetCode.TEST_FAILED


func TEST_TRUE( value:Variant, desc:String = "" ) -> void:
	logd("TEST_TRUE('%s'): %s", [value, desc])
	if _test_true( value, desc ): return
	runcode &= RetCode.TEST_FAILED


func _test_false( value:Variant, desc:String = "" ) -> bool:
	if not value: return true
	var msg:String = '\n'.join([
		"[b][color=salmon]%s: '%s'[/color][/b]" % [_call_site( 3 ), desc],
		"\twanted: false | value == (0 & null)",
		"\tgot: '%s'" % value])
	_note_fail( msg )
	return false


## Returns [enum RetCode] 0(TEST_FAILED) on failure, and 1(TEST_OK) on Success.
func TEST_FALSE_RET( value:Variant, desc:String = "" ) -> RetCode:
	logd("TEST_FALSE_RET('%s'): %s", [value, desc])
	if _test_false( value, desc ): return RetCode.TEST_OK
	runcode &= RetCode.TEST_FAILED
	return RetCode.TEST_FAILED


func TEST_FALSE( value:Variant, desc:String = "" ) -> void:
	logd("TEST_FALSE('%s'): %s", [value, desc])
	if _test_false( value, desc ): return
	runcode &= RetCode.TEST_FAILED


func _test_op( val1:Variant, op:int, val2:Variant, desc:String = ""  ) -> bool:
	var op_result:bool = false
	match op:
		OP_EQUAL: op_result = val1 == val2
		OP_NOT_EQUAL: op_result = val1 != val2
		OP_GREATER_EQUAL: op_result = val1 >= val2
		OP_GREATER: op_result = val1 > val2
		OP_LESS_EQUAL: op_result = val1 <= val2
		OP_LESS: op_result = val1 < val2
	if op_result: return true

	var msg:String = '\n'.join([
		"[b][color=salmon]%s: '%s'[/color][/b]" % [_call_site( 3 ), desc],
		"\tOp: ('%s' %s '%s') is false" % [val1, op_string[op], val2]])
	_note_fail( msg )
	return false


## Returns [enum RetCode] 0(TEST_FAILED) on failure, and 1(TEST_OK) on Success.
func TEST_OP_RET( val1:Variant, op:int, val2:Variant, desc:String = ""  ) -> RetCode:
	logd("TEST_OP_RET('%s', %s, '%s'): %s", [val1, op_string[op], val2, desc])
	if _test_op(val1, op, val2, desc): return RetCode.TEST_OK
	runcode &= RetCode.TEST_FAILED
	return RetCode.TEST_FAILED


func TEST_OP( val1:Variant, op:int, val2:Variant, desc:String = ""  ) -> void:
	logd("TEST_OP('%s', %s, '%s'): %s", [val1, op_string[op], val2, desc])
	if _test_op(val1, op, val2, desc): return
	runcode &= RetCode.TEST_FAILED

@tool
class_name TR_CaseSession
extends RefCounted

##[codeblock lang=text]
##│  ___              ___            _
##│ / __|__ _ ___ ___/ __| ___ _____(_)___ _ _
##│| (__/ _` (_-</ -_)__ \/ -_|_-<_-< / _ \ ' \
##│ \___\__,_/__/\___|___/\___/__/__/_\___/_||_|
##╰───────────────────────────────────────────────
##[/codeblock]The run record shared by every host.
##
## Pass is 1 and fail is 0. A missing return
## stays a failure. This record owns the hooks. It loads the scripts named
## by the options list and by the case constants [code]HOOK[/code] and
## [code]HOOKS[/code], then calls [method TR_Hook.pre] and waits on
## [signal TR_Hook.settled]. [method TR_Case._configure] runs after that
## load and may append another hook. The clock starts after _pre, using
## [member budget_s]. [method check] and the [code]TEST_[/code] functions
## record a miss on this run.

const TreeClockScript = preload( "uid://d1tkhkfbyirfq" )
const LoopClockScript = preload( "uid://jiyhdb8bmsbq" )
const Log = preload( "uid://br7jtx5cntuan" )

const TEST_FAILED:int = 0
const TEST_OK:int = 1

## Names for [enum Variant.Operator]. [method TEST_OP] reads the comparison rows.
const op_string:PackedStringArray = [
	"==", #  0: OP_EQUAL
	"!=", #  1: OP_NOT_EQUAL
	"<",  #  2: OP_LESS
	"<=", #  3: OP_LESS_EQUAL
	">",  #  4: OP_GREATER
	">=", #  5: OP_GREATER_EQUAL
	"+",  #  6: OP_ADD
	"-",  #  7: OP_SUBTRACT
	"*",  #  8: OP_MULTIPLY
	"/",  #  9: OP_DIVIDE
	"-",  # 10: OP_NEGATE
	"+",  # 11: OP_POSITIVE
	"%",  # 12: OP_MODULE
	"**", # 13: OP_POWER
	"<<", # 14: OP_SHIFT_LEFT
	">>", # 15: OP_SHIFT_RIGHT
	"&",  # 16: OP_BIT_AND
	"|",  # 17: OP_BIT_OR
	"^",  # 18: OP_BIT_XOR
	"~",  # 19: OP_BIT_NEGATE
	"&&", # 20: OP_AND
	"||", # 21: OP_OR
	"",   # 22: OP_XOR
	"!",  # 23: OP_NOT
	"in", # 24: OP_IN
]

## Set by the editor menu before Play. The shell passes paths after `--` instead.
const PATH_ENV:String = "CASE_PATHS"
const REPORT_ENV:String = "CASE_REPORT"
## Absolute project root. A packed run has no [code]res://[/code] directory of its own.
const PROJECT_ENV:String = "CASE_PROJECT"

## Default case folder. Discovery reads [method TR_Opts.cases_roots].
const CASE_ROOT:String = TR_Opts.DEFAULT_CASES_DIR

enum Host {
	EDITOR,
	PLAY,
	SCRIPT,
}

## Menu row and launch id. [enum Host] is the process that row starts.
enum Launch {
	EDITORSCRIPT,
	PLAY_EDITOR,
	PLAY_DEBUG,
	PLAY_RELEASE,
	HEADLESS,
}


# ██████  ██████   ██████  ██████  ███████ ██████  ████████ ██ ███████ ███████ #
# ██   ██ ██   ██ ██    ██ ██   ██ ██      ██   ██    ██    ██ ██      ██      #
# ██████  ██████  ██    ██ ██████  █████   ██████     ██    ██ █████   ███████ #
# ██      ██   ██ ██    ██ ██      ██      ██   ██    ██    ██ ██           ██ #
# ██      ██   ██  ██████  ██      ███████ ██   ██    ██    ██ ███████ ███████ #
func                        ________PROPERTIES_______              ()->void:pass

# >==================================< Host >==================================<

## Process running this record. [enum Host.EDITOR] until the host replaces it.
var host:Host = Host.EDITOR

## Scene tree for a tree host. Null on the tick clock.
var tree:SceneTree

## TR_Clock the host installed.
var clock:TR_Clock

## True when this run started the main scene and must stop it afterwards.
var main_scene_started:bool = false

# >================================< Prepare >=================================<

## [code]editor[/code], [code]template_debug[/code], or [code]template_release[/code].
var flavour:String = ""

## [method Engine.is_editor_hint] at prepare time.
var hint:bool = false

## TR_Case script path.
var case_path:String = ""

## Trace filename token: editorscript, play_editor, play_debug, play_release, or headless.
var run_kind:String = ""

# >=================================< Hooks >==================================<

## Seconds covering setup, the body, and cleanup. [code]BUDGET_S[/code] fills
## this before [method TR_Case._configure]. That step may replace it.
var budget_s:float = 5.0

## Hooks for this run. Empty skips [method TR_Hook.pre] and [method TR_Hook.post].
## The options list and the case constants fill it. [method TR_Case._configure] may append.
var hooks:Array[TR_Hook] = []

## Extra hook scripts for this run, beside the options list and the case constants.
var hook_paths:PackedStringArray = PackedStringArray()

## Options-list scripts left out of this run.
var hook_skip:PackedStringArray = PackedStringArray()

# Hooks whose pre returned [constant OK]. Post walks this in reverse.
var _live:Array[TR_Hook] = []

# >=================================< Timing >=================================<

## Milliseconds when the clock starts. The capture reads this for its pad.
var harness_mark_msec:int = 0

## Phase lengths in seconds. Negative until that phase returns.
var setup_s:float = -1.0
var run_s:float = -1.0
var cleanup_s:float = -1.0

# >=================================< Result >=================================<

## Pass is [constant TEST_OK]. A missing return stays [constant TEST_FAILED].
var runcode:int = TEST_FAILED

## Short result word: pass, fail, timeout, or refused.
var status:String = ""

## Why a refused run did not start. Empty once a run has started.
var reason:String = ""

## Lines [method _note] stored for the report.
var output:PackedStringArray = PackedStringArray()


#             ███████ ██    ██ ███████ ███    ██ ████████ ███████              #
#             ██      ██    ██ ██      ████   ██    ██    ██                   #
#             █████   ██    ██ █████   ██ ██  ██    ██    ███████              #
#             ██       ██  ██  ██      ██  ██ ██    ██         ██              #
#             ███████   ████   ███████ ██   ████    ██    ███████              #
func                        __________EVENTS_________              ()->void:pass

func _on_clock() -> void:
	if status != "":
		return
	status = "timeout"
	runcode = TEST_FAILED
	_note( "timeout" )


#         ███    ███ ███████ ████████ ██   ██  ██████  ██████  ███████         #
#         ████  ████ ██         ██    ██   ██ ██    ██ ██   ██ ██              #
#         ██ ████ ██ █████      ██    ███████ ██    ██ ██   ██ ███████         #
#         ██  ██  ██ ██         ██    ██   ██ ██    ██ ██   ██      ██         #
#         ██      ██ ███████    ██    ██   ██  ██████  ██████  ███████         #
func                        _________METHODS_________              ()->void:pass

#region Host - The host installs the clock and builds the case.
#MARK: Host
func                        __Host___________________              ()->void:pass
# │ _  _        _
# │| || |___ __| |_
# │| __ / _ (_-<  _|
# │|_||_\___/__/\__|
# ╰──────────────────

func attach_tree( scene_tree:SceneTree ) -> void:
	tree = scene_tree
	var made := TreeClockScript.new()
	made.bind( scene_tree )
	clock = made
	_note_main_scene()


func attach_loop() -> void:
	tree = null
	main_scene_started = false
	clock = LoopClockScript.new()


func instantiate( scr:Script ) -> TR_Case:
	var native_name:String = str( script_const( scr, "NATIVE", "" ) )
	if native_name != "":
		if not ClassDB.class_exists( native_name ):
			return null

		var native:Object = ClassDB.instantiate( native_name )
		if native is TR_Case:
			return native

		return null

	if not scr is GDScript:
		return null

	var gd:GDScript = scr
	if not gd.can_instantiate():
		return null

	var made:Variant = gd.new()
	if made is TR_Case:
		return made

	return null

#endregion Host

#region Checks - A miss fails the run and stores a line.
#MARK: Checks
func                        __Checks_________________              ()->void:pass
# │  ___ _           _
# │ / __| |_  ___ __| |__ ___
# │| (__| ' \/ -_) _| / /(_-<
# │ \___|_||_\___\__|_\_\/__/
# ╰───────────────────────────

## A false [param ok] fails the run. [param label] is the stored line.
func check( ok:bool, label:String ) -> void:
	if ok:
		return

	runcode = TEST_FAILED
	_note( label )


## True when [param want_v] and [param got_v] match. A miss fails the run.
## Returns [constant TEST_OK] or [constant TEST_FAILED].
func TEST_EQ_RET( want_v:Variant, got_v:Variant, desc:String = "" ) -> int:
	_logd( "TEST_EQ_RET(want:'%s' == got:'%s'): %s", [want_v, got_v, desc] )
	if _test_eq( want_v, got_v, desc ):
		return TEST_OK

	_fail()
	return TEST_FAILED


## True when [param want_v] and [param got_v] match. A miss fails the run.
func TEST_EQ( want_v:Variant, got_v:Variant, desc:String = "" ) -> void:
	_logd( "TEST_EQ(want:'%s' == got:'%s'): %s", [want_v, got_v, desc] )
	if _test_eq( want_v, got_v, desc ):
		return

	_fail()


## True when [param want_v] and [param got_v] are approximately equal.
## Returns [constant TEST_OK] or [constant TEST_FAILED].
func TEST_APPROX_RET( want_v:float, got_v:float, desc:String = "" ) -> int:
	_logd( "TEST_APPROX_RET(want:'%s' ~= got:'%s'): %s", [want_v, got_v, desc] )
	if _test_approx( want_v, got_v, desc ):
		return TEST_OK

	_fail()
	return TEST_FAILED


## True when [param want_v] and [param got_v] are approximately equal.
func TEST_APPROX( want_v:float, got_v:float, desc:String = "" ) -> void:
	_logd( "TEST_APPROX(want:'%s' ~= got:'%s'): %s", [want_v, got_v, desc] )
	if _test_approx( want_v, got_v, desc ):
		return

	_fail()


## True when [param value] is truthy. A miss fails the run.
## Returns [constant TEST_OK] or [constant TEST_FAILED].
func TEST_TRUE_RET( value:Variant, desc:String = "" ) -> int:
	_logd( "TEST_TRUE_RET('%s'): %s", [value, desc] )
	if _test_true( value, desc ):
		return TEST_OK

	_fail()
	return TEST_FAILED


## True when [param value] is truthy. A miss fails the run.
func TEST_TRUE( value:Variant, desc:String = "" ) -> void:
	_logd( "TEST_TRUE('%s'): %s", [value, desc] )
	if _test_true( value, desc ):
		return

	_fail()


## True when [param value] is falsy. A miss fails the run.
## Returns [constant TEST_OK] or [constant TEST_FAILED].
func TEST_FALSE_RET( value:Variant, desc:String = "" ) -> int:
	_logd( "TEST_FALSE_RET('%s'): %s", [value, desc] )
	if _test_false( value, desc ):
		return TEST_OK

	_fail()
	return TEST_FAILED


## True when [param value] is falsy. A miss fails the run.
func TEST_FALSE( value:Variant, desc:String = "" ) -> void:
	_logd( "TEST_FALSE('%s'): %s", [value, desc] )
	if _test_false( value, desc ):
		return

	_fail()


## True when [param val1] [param op] [param val2] holds. [param op] is a [enum Variant.Operator].
## Returns [constant TEST_OK] or [constant TEST_FAILED].
func TEST_OP_RET( val1:Variant, op:int, val2:Variant, desc:String = "" ) -> int:
	_logd( "TEST_OP_RET('%s', %s, '%s'): %s", [val1, op_string[op], val2, desc] )
	if _test_op( val1, op, val2, desc ):
		return TEST_OK

	_fail()
	return TEST_FAILED


## True when [param val1] [param op] [param val2] holds. [param op] is a [enum Variant.Operator].
func TEST_OP( val1:Variant, op:int, val2:Variant, desc:String = "" ) -> void:
	_logd( "TEST_OP('%s', %s, '%s'): %s", [val1, op_string[op], val2, desc] )
	if _test_op( val1, op, val2, desc ):
		return

	_fail()


func _fail() -> void:
	runcode = TEST_FAILED


func _note_fail( msg:String ) -> void:
	_note( msg )


func _logd( msg:String, args:Array = [] ) -> void:
	var text:String = msg if args.is_empty() else msg % args
	self.log( Log.Level.DEBUG, text )


func _test_eq( want_v:Variant, got_v:Variant, desc:String = "" ) -> bool:
	if want_v == got_v:
		return true

	var msg:String = "\n".join( [
		"[b][color=salmon]%s: '%s'[/color][/b]" % [Log.call_site( 3 ), desc],
		"\twanted: '%s' == got: '%s'" % [want_v, got_v],
	] )
	_note_fail( msg )
	return false


func _test_approx( want_v:float, got_v:float, desc:String = "" ) -> bool:
	if is_equal_approx( want_v, got_v ):
		return true

	var msg:String = "\n".join( [
		"[b][color=salmon]%s: '%s'[/color][/b]" % [Log.call_site( 3 ), desc],
		"\twanted: '%s' ~= got: '%s'" % [want_v, got_v],
	] )
	_note_fail( msg )
	return false


func _test_true( value:Variant, desc:String = "" ) -> bool:
	if value:
		return true

	var msg:String = "\n".join( [
		"[b][color=salmon]%s: '%s'[/color][/b]" % [Log.call_site( 3 ), desc],
		"\twanted: true | value != (0 & null)",
		"\tgot: '%s'" % value,
	] )
	_note_fail( msg )
	return false


func _test_false( value:Variant, desc:String = "" ) -> bool:
	if not value:
		return true

	var msg:String = "\n".join( [
		"[b][color=salmon]%s: '%s'[/color][/b]" % [Log.call_site( 3 ), desc],
		"\twanted: false | value == (0 & null)",
		"\tgot: '%s'" % value,
	] )
	_note_fail( msg )
	return false


func _test_op( val1:Variant, op:int, val2:Variant, desc:String = "" ) -> bool:
	var op_result:bool = false
	match op:
		OP_EQUAL:
			op_result = val1 == val2
		OP_NOT_EQUAL:
			op_result = val1 != val2
		OP_GREATER_EQUAL:
			op_result = val1 >= val2
		OP_GREATER:
			op_result = val1 > val2
		OP_LESS_EQUAL:
			op_result = val1 <= val2
		OP_LESS:
			op_result = val1 < val2

	if op_result:
		return true

	var msg:String = "\n".join( [
		"[b][color=salmon]%s: '%s'[/color][/b]" % [Log.call_site( 3 ), desc],
		"\tOp: ('%s' %s '%s') is false" % [val1, op_string[op], val2],
	] )
	_note_fail( msg )
	return false

#endregion Checks

#region Run - Run the case. A sync host refuses an await.
#MARK: Run
func                        __Run____________________              ()->void:pass
# │ ___
# │| _ \_  _ _ _
# │|   / || | ' \
# │|_|_\\_,_|_||_|
# ╰────────────────

func refuse( why:String, script_path:String = "" ) -> void:
	_prepare( script_path )

	status = "refused"
	reason = why
	runcode = TEST_FAILED
	_close()


func run_sync( case:TR_Case ) -> void:
	if not _open( case ):
		return

	if not _install_hooks( case ):
		return

	_configure_case( case )
	_bind_hooks()

	if not _pre_sync():
		return

	harness_mark_msec = Time.get_ticks_msec()
	_arm()
	var setup_t:int = Time.get_ticks_msec()
	var setup_v:Variant = case._setup()
	setup_s = _elapsed( setup_t )
	if typeof( setup_v ) != TYPE_INT:
		_awaited()
		_finish_sync()
		return

	if whole( setup_v ) != OK:
		status = "setup failed"
		runcode = TEST_FAILED
		_finish_sync()
		return

	runcode = TEST_OK
	var body_t:int = Time.get_ticks_msec()
	var body_v:Variant = case._run_test()
	run_s = _elapsed( body_t )
	if typeof( body_v ) != TYPE_INT:
		_awaited()
		_finish_sync()
		return

	if runcode == TEST_OK:
		runcode = whole( body_v )
	status = "pass" if runcode == TEST_OK else "fail"

	var cleanup_t:int = Time.get_ticks_msec()
	var cleanup_v:Variant = case._cleanup()
	cleanup_s = _elapsed( cleanup_t )
	if typeof( cleanup_v ) != TYPE_INT:
		_awaited()
		_finish_sync()
		return

	if whole( cleanup_v ) != OK and status == "pass":
		status = "cleanup failed"
		runcode = TEST_FAILED
	_finish_sync()


func run_await( case:TR_Case ) -> void:
	if not _open( case ):
		return

	if not _install_hooks( case ):
		return

	_configure_case( case )
	_bind_hooks()

	var opened:bool = await _pre_await()
	if not opened:
		return

	harness_mark_msec = Time.get_ticks_msec()
	_arm()
	# Timed in _timed. A stamp kept in this function is an Object after the next await.
	var setup_pack:Array = await _timed( case._setup )
	setup_s = setup_pack[0]
	var setup_err:Error = setup_pack[1]
	if status == "timeout":
		await _finish_await()
		return

	if setup_err != OK:
		status = "setup failed"
		runcode = TEST_FAILED
		await _finish_await()
		return

	runcode = TEST_OK
	var body_pack:Array = await _timed( case._run_test )
	run_s = body_pack[0]
	var returned:int = body_pack[1]
	if status == "timeout":
		await _finish_await()
		return

	if runcode == TEST_OK:
		runcode = returned
	status = "pass" if runcode == TEST_OK else "fail"

	var cleanup_pack:Array = await _timed( case._cleanup )
	cleanup_s = cleanup_pack[0]
	var cleanup_err:Error = cleanup_pack[1]
	if status != "timeout" and cleanup_err != OK and status == "pass":
		status = "cleanup failed"
		runcode = TEST_FAILED
	await _finish_await()


func line() -> String:
	var text:String = "case status=%s runcode=%d host=%s flavour=%s hint=%s" % [
		status, runcode, _host_name(), flavour, hint,
	]
	if reason != "":
		text += " reason=%s" % reason

	if case_path != "":
		text += " path=%s" % case_path

	for entry:String in output:
		text += "\n" + entry

	return text

#endregion Run

#region Scripts - Find case scripts and read the constants they declare.
#MARK: Scripts
func                        __Scripts________________              ()->void:pass
# │ ___         _      _
# │/ __| __ _ _(_)_ __| |_ ___
# │\__ \/ _| '_| | '_ \  _(_-<
# │|___/\__|_| |_| .__/\__/__/
# ╰──────────────|_|───────────

## [param scr] extends [TR_Case] and is not [TR_Case] itself.
static func is_case_script( scr:Script ) -> bool:
	if scr == null or scr.get_global_name() == &"TR_Case":
		return false

	var current:Script = scr.get_base_script()
	while current != null:
		if current.get_global_name() == &"TR_Case":
			return true

		current = current.get_base_script()
	return false


## [param script_path] loads as a case script.
static func is_case_path( script_path:String ) -> bool:
	if not script_path.ends_with( ".gd" ) or not ResourceLoader.exists( script_path ):
		return false

	var loaded:Resource = load( script_path )
	if not loaded is Script:
		return false

	var scr:Script = loaded
	return is_case_script( scr )


## TR_Case script file names directly inside [param folder].
static func case_files( folder:String ) -> Array[String]:
	var out:Array[String] = []
	for file_name:String in DirAccess.get_files_at( folder ):
		if file_name.ends_with( ".gd" ) and is_case_path( folder.path_join( file_name ) ):
			out.append( file_name )
	return out


static func case_paths() -> PackedStringArray:
	var paths:PackedStringArray = _script_paths( OS.get_cmdline_user_args() )
	if not paths.is_empty():
		return paths

	var from_env:String = OS.get_environment( PATH_ENV )
	if from_env == "":
		return paths
	return _script_paths( from_env.split( ";" ) )


static func script_const( scr:Script, key:String, fallback:Variant ) -> Variant:
	var current:Script = scr
	while current != null:
		var found:Dictionary = current.get_script_constant_map()
		if found.has( key ):
			return found[ key ]

		current = current.get_base_script()
	return fallback


static func script_flag( scr:Script, key:String ) -> bool:
	var found:Variant = script_const( scr, key, false )
	if found is bool:
		var flag:bool = found
		return flag

	return false


static func script_seconds( scr:Script, key:String, fallback:float ) -> float:
	var found:Variant = script_const( scr, key, fallback )
	if found is float:
		var number:float = found
		return number

	if found is int:
		var counted:int = found
		return float( counted )

	return fallback

static func whole( value:Variant ) -> int:
	if value is int:
		var number:int = value
		return number

	return TEST_FAILED

#endregion Scripts

#region Report - Which process a menu row starts, and the report the panel reads back.
#MARK: Report
func                        __Report_________________              ()->void:pass
# │ ___                   _
# │| _ \___ _ __  ___ _ _| |_
# │|   / -_) '_ \/ _ \ '_|  _|
# │|_|_\___| .__/\___/_|  \__|
# ╰────────|_|─────────────────

## The process [param id] starts. The three play rows are all [constant Host.PLAY].
static func launch_host( id:Launch ) -> Host:
	match id:
		Launch.HEADLESS:
			return Host.SCRIPT

		Launch.EDITORSCRIPT:
			return Host.EDITOR

		_:
			return Host.PLAY


static func report_file() -> String:
	return ProjectSettings.globalize_path( "user://case_report.txt" )


static func clear_report() -> void:
	var report_path:String = report_file()
	if not FileAccess.file_exists( report_path ):
		return

	var err:Error = DirAccess.remove_absolute( report_path )
	if err != OK:
		push_error( "TR_CaseSession.clear_report: %s" % error_string( err ) )


## Print [param text] and append it to the report. The panel builds a card from it.
static func report( text:String ) -> void:
	print( text )

	var report_path:String = OS.get_environment( REPORT_ENV )
	if report_path == "":
		return

	var prior:String = ""
	if FileAccess.file_exists( report_path ):
		prior = FileAccess.get_file_as_string( report_path )
	var file:FileAccess = FileAccess.open( report_path, FileAccess.WRITE )
	if file == null:
		return

	if prior != "" and not file.store_string( prior ):
		return

	if prior != "" and not prior.ends_with( "\n" ) and not file.store_string( "\n" ):
		return

	if not file.store_string( text ):
		push_error( "TR_CaseSession.report: write failed" )
		return

	if not text.ends_with( "\n" ) and not file.store_string( "\n" ):
		push_error( "TR_CaseSession.report: write failed" )

#endregion Report

#       ██ ███    ██ ████████ ███████ ██████  ███    ██  █████  ██             #
#       ██ ████   ██    ██    ██      ██   ██ ████   ██ ██   ██ ██             #
#       ██ ██ ██  ██    ██    █████   ██████  ██ ██  ██ ███████ ██             #
#       ██ ██  ██ ██    ██    ██      ██   ██ ██  ██ ██ ██   ██ ██             #
#       ██ ██   ████    ██    ███████ ██   ██ ██   ████ ██   ██ ███████        #
func                        ________INTERNAL_________              ()->void:pass

#region Open - Accept the case, then configure it and start the clock.
#MARK: Open
func                        __Open___________________              ()->void:pass
# │  ___
# │ / _ \ _ __  ___ _ _
# │| (_) | '_ \/ -_) ' \
# │ \___/| .__/\___|_||_|
# ╰──────|_|──────────────

func _open( case:TR_Case ) -> bool:
	var scr:Script = _case_script( case )
	var script_path:String = ""
	if scr != null:
		script_path = scr.resource_path
	_prepare( script_path )
	case.session = self
	if scr == null:
		return _deny( "not a script" )

	if clock == null:
		return _deny( "no clock" )

	if script_flag( scr, "EDITOR_ONLY" ) and host != Host.EDITOR:
		return _deny( "editor_only" )

	if script_flag( scr, "NEEDS_MAIN_SCENE" ) and not main_scene_started:
		return _deny( "needs_main_scene" )

	if script_flag( scr, "NEEDS_TREE" ) and tree == null:
		return _deny( "needs_tree" )

	budget_s = script_seconds( scr, "BUDGET_S", 5.0 )
	return true


func _deny( why:String ) -> bool:
	refuse( why )
	return false


func _prepare( script_path:String = "" ) -> void:
	if flavour == "":
		flavour = _read_flavour()
	hint = Engine.is_editor_hint()
	if script_path != "":
		case_path = script_path
	run_kind = _kind_name()


func _configure_case( case:TR_Case ) -> void:
	# Void, and not awaited. An override that awaits is outside this step.
	case._configure()


func _install_hooks( case:TR_Case ) -> bool:
	var forced:PackedStringArray = hook_paths.duplicate()
	for path:String in TR_Hook.const_paths( _case_script( case ) ):
		if forced.has( path ):
			continue
		if forced.append( path ):
			push_error( "TR_CaseSession._install_hooks: append failed" )
			break

	var optional:PackedStringArray = TR_Opts.hook_paths()
	var seen:Dictionary = {}
	for hook:TR_Hook in hooks:
		var scr:Script = hook.get_script()
		if scr != null and not scr.resource_path.is_empty():
			seen[ scr.resource_path ] = true

	var err:String = _load_hook_paths( seen, forced, true )
	if err.is_empty():
		err = _load_hook_paths( seen, optional, false )
	if not err.is_empty():
		status = "fail"
		runcode = TEST_FAILED
		_note( "hook failed to load %s" % err )
		_close()
		_release_hooks()
		return false

	return true


## Load [param script_path]. An empty string means the hook declined.
## Any other string is why it failed. A [TR_Hook] is the instance.
func _spawn_hook( script_path:String, forced:bool ) -> Variant:
	if script_path.is_empty():
		return "missing"

	var gd:GDScript = TR_Opts.script_for( script_path )
	if gd != null:
		return _hook_from_script( gd, forced )
	if not forced:
		return "missing"
	return _spawn_outside( script_path )


## A case constant names a script the scan did not keep.
func _spawn_outside( script_path:String ) -> Variant:
	if not ResourceLoader.exists( script_path ):
		return "missing"

	var loaded:Resource = load( script_path )
	if not loaded is GDScript:
		return "not a script"

	var gd:GDScript = loaded
	if not gd.can_instantiate():
		return "cannot instantiate"
	return _hook_from_script( gd, true )


func _hook_from_script( gd:GDScript, forced:bool ) -> Variant:
	var made:Variant = gd.new()
	if not made is TR_Hook:
		return "not a hook"

	var hook:TR_Hook = made
	if not forced \
	and not hook._accept():
		return ""
	return hook


func _load_hook_paths( seen:Dictionary, paths:PackedStringArray, forced:bool ) -> String:
	for path:String in paths:
		if path.is_empty() \
		or seen.has( path ):
			continue
		if not forced \
		and hook_skip.has( path ):
			continue

		var made:Variant = _spawn_hook( path, forced )
		if made is String:
			var why:String = made
			if why.is_empty():
				seen[ path ] = true
				continue
			if forced:
				return "%s (%s)" % [ path, why ]
			push_error( "TR_CaseSession: %s (%s)" % [ path, why ] )
			continue

		var hook:TR_Hook = made
		hooks.append( hook )
		seen[ path ] = true
		var scr:Script = hook.get_script()
		if scr != null and not scr.resource_path.is_empty():
			seen[ scr.resource_path ] = true
	return ""


func _bind_hooks() -> void:
	for hook:TR_Hook in hooks:
		hook.bind_host( self )


func _arm() -> void:
	if not clock.fired.is_connected( _on_clock ):
		var err:int = clock.fired.connect( _on_clock )
		if err != OK:
			push_error( "TR_CaseSession._arm: connect failed (%s)" % error_string( err ) )

	clock.start( budget_s )

#endregion Open

#region Phases - The tree host awaits inside _timed.
#MARK: Phases
func                        __Phases_________________              ()->void:pass
# │ ___ _
# │| _ \ |_  __ _ ___ ___ ___
# │|  _/ ' \/ _` (_-</ -_|_-<
# │|_| |_||_\__,_/__/\___/__/
# ╰───────────────────────────

func _pre_sync() -> bool:
	_live = []
	for hook:TR_Hook in hooks:
		# pre awaits inside. This wait is [signal TR_Hook.settled].
		@warning_ignore( "missing_await" )
		hook.pre()
		if not hook.is_finished():
			refuse( "awaited without a tree" )
			hook.drop_wait()
			_release_hooks()
			return false

		if hook.get_retcode() != OK:
			status = "fail"
			runcode = TEST_FAILED
			_note( "hooks._pre() failed" )
			_close()
			_release_hooks()
			return false

		_live.append( hook )

	return true


func _pre_await() -> bool:
	_live = []
	for hook:TR_Hook in hooks:
		# pre awaits inside. This wait is [signal TR_Hook.settled].
		@warning_ignore( "missing_await" )
		hook.pre()
		if not hook.is_finished():
			await hook.settled
		if hook.get_retcode() != OK:
			status = "fail"
			runcode = TEST_FAILED
			_note( "hooks._pre() failed" )
			_close()
			_release_hooks()
			return false

		_live.append( hook )
	return true


func _awaited() -> void:
	status = "refused"
	reason = "awaited without a tree"
	runcode = TEST_FAILED


func _post_sync() -> void:
	var index:int = _live.size()
	while index > 0:
		index -= 1
		var hook:TR_Hook = _live[ index ]
		# post awaits inside. This wait is [signal TR_Hook.settled].
		@warning_ignore( "missing_await" )
		hook.post()
		if not hook.is_finished():
			if status != "refused":
				_awaited()
			hook.drop_wait()
			return

		if hook.get_retcode() != OK and runcode == TEST_OK:
			status = "fail"
			runcode = TEST_FAILED
			_note( "hooks._post() failed" )


# One await, then the length. run_await cannot hold the stamp itself.
func _timed( work:Callable ) -> Array:
	var started:int = Time.get_ticks_msec()
	@warning_ignore( "redundant_await" )
	var result:Variant = await work.call()

	return [ _elapsed( started ), result ]


func _elapsed( started:int ) -> float:
	return ( Time.get_ticks_msec() - started ) / 1000.0


func _finish_sync() -> void:
	_close()

	_post_sync()

	_release_hooks()


func _finish_await() -> void:
	_close()

	var index:int = _live.size()
	while index > 0:
		index -= 1
		var hook:TR_Hook = _live[ index ]
		# post awaits inside. This wait is [signal TR_Hook.settled].
		@warning_ignore( "missing_await" )
		hook.post()
		if not hook.is_finished():
			await hook.settled
		if hook.get_retcode() != OK and runcode == TEST_OK:
			status = "fail"
			runcode = TEST_FAILED
			_note( "hooks._post() failed" )

	_release_hooks()

func _release_hooks() -> void:
	# A hook may hold this session. Dropping both sides breaks that cycle.
	for hook:TR_Hook in hooks:
		hook.release()
	hooks = []
	_live = []

#endregion Phases

#region Record - Lines, flavour, and stopping the clock.
#MARK: Record
func                        __Record_________________              ()->void:pass
# │ ___                   _
# │| _ \___ __ ___ _ _ __| |
# │|   / -_) _/ _ \ '_/ _` |
# │|_|_\___\__\___/_| \__,_|
# ╰──────────────────────────

## Write [param text] when [param level] is inside the options ceiling.
## The line is collected on [member output].
func log( level:int, text:String ) -> void:
	var opts:TR_Opts = TR_Opts.shared() as TR_Opts
	var mask:int = opts.lvl if opts != null else Log.Level.NOTICE
	if not Log.allows( mask, level ):
		return

	Log.lvl( level, text, self )

	if output.append( text ):
		push_error( "TR_CaseSession.log: append failed" )


func _note( text:String ) -> void:
	# append returns the Error. OK is 0, so false means the line was stored.
	if output.append( text ):
		push_error( "TR_CaseSession._note: append failed" )

	for hook:TR_Hook in hooks:
		hook._message( text )


func _close() -> void:
	if clock == null:
		return

	clock.stop()


func _note_main_scene() -> void:
	main_scene_started = false
	if tree == null \
	or tree.current_scene == null:
		return

	var started:String = str( ProjectSettings.get_setting( "application/run/main_scene", "" ) )
	if started.begins_with( "uid://" ):
		var id:int = ResourceUID.text_to_id( started )
		if ResourceUID.has_id( id ):
			started = ResourceUID.uid_to_path( started )

	main_scene_started = tree.current_scene.scene_file_path == started


func _case_script( case:TR_Case ) -> Script:
	var found:Variant = case.get_script()
	if found is Script:
		var scr:Script = found
		return scr

	return null


func _read_flavour() -> String:
	if OS.has_feature( "template_release" ):
		return "template_release"

	if OS.has_feature( "template_debug" ):
		return "template_debug"

	if OS.has_feature( "editor" ):
		return "editor"

	return "unknown"


func _host_name() -> String:
	match host:
		Host.PLAY:
			return "play"

		Host.SCRIPT:
			return "script"

		_:
			return "editor"


## Token stored in the trace filename. [member flavour] splits the three play rows.
func _kind_name() -> String:
	match host:
		Host.SCRIPT:
			return "headless"

		Host.PLAY:
			if flavour == "template_debug":
				return "play_debug"

			if flavour == "template_release":
				return "play_release"

			return "play_editor"

		_:
			return "editorscript"

#endregion Record

#region Paths - Paths from the command line or from CASE_PATHS.
#MARK: Paths
func                        __Paths__________________              ()->void:pass
# │ ___      _   _
# │| _ \__ _| |_| |_  ___
# │|  _/ _` |  _| ' \(_-<
# │|_| \__,_|\__|_||_/__/
# ╰───────────────────────

static func _script_paths( items:PackedStringArray ) -> PackedStringArray:
	var paths:PackedStringArray = PackedStringArray()
	for item:String in items:
		if item.begins_with( "res://" ) and item.ends_with( ".gd" ):
			paths = _take( paths, item )
	return paths


static func _take( paths:PackedStringArray, item:String ) -> PackedStringArray:
	# append returns the Error. OK is 0, so false means the path was stored.
	if paths.append( item ):
		push_error( "TR_CaseSession._take: append failed" )
	return paths

#endregion Paths

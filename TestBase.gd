@tool @abstract
class_name TestBase extends EditorScript
var cycleref: EditorScript


#           ████ ███    ███ ██████   ██████  ██████  ████████ ███████          #
#            ██  ████  ████ ██   ██ ██    ██ ██   ██    ██    ██               #
#            ██  ██ ████ ██ ██████  ██    ██ ██████     ██    ███████          #
#            ██  ██  ██  ██ ██      ██    ██ ██   ██    ██         ██          #
#           ████ ██      ██ ██       ██████  ██   ██    ██    ███████          #
func                        _________IMPORTS_________              ()->void:pass

const Shared = preload('scripts/shared.gd')
const TestResult = Shared.TestResult

## NOTE: Dont forget, OK is 1, FAIL is 0. Which is backwards for the standard
## case for reasons.
const RetCode = Shared.RetCode


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

var scene_tree:SceneTree

var _verbose:bool = true
var _debug:bool = false
var runcode:int = RetCode.TEST_OK
var output:Array = []
var max_runtime_s:float = 3
var timer:Timer

#            ███████ ██  ██████  ███    ██  █████  ██      ███████             #
#            ██      ██ ██       ████   ██ ██   ██ ██      ██                  #
#            ███████ ██ ██   ███ ██ ██  ██ ███████ ██      ███████             #
#                 ██ ██ ██    ██ ██  ██ ██ ██   ██ ██           ██             #
#            ███████ ██  ██████  ██   ████ ██   ██ ███████ ███████             #
func                        _________SIGNALS_________              ()->void:pass

signal test_finished

func _on_timer_timeout() -> void:
	runcode = RetCode.TEST_FAILED
	logp("[color=salmon]Error: Timeout was reached.[/color]")
	test_finished.emit()


#      ██████  ██    ██ ███████ ██████  ██████  ██ ██████  ███████ ███████     #
#     ██    ██ ██    ██ ██      ██   ██ ██   ██ ██ ██   ██ ██      ██          #
#     ██    ██ ██    ██ █████   ██████  ██████  ██ ██   ██ █████   ███████     #
#     ██    ██  ██  ██  ██      ██   ██ ██   ██ ██ ██   ██ ██           ██     #
#      ██████    ████   ███████ ██   ██ ██   ██ ██ ██████  ███████ ███████     #
func                        ________OVERRIDES________              ()->void:pass

## Override this function to perform setup prior to testing.
func _setup() -> Error:
	return OK


func _cleanup() -> Error:
	return OK


## This is the function to override in derived test functions.
@abstract
func _run_test() -> RetCode


## Calling as an editor script
func _run() -> void:
	# NOTE: Maintain a reference to ourself, because no-one else will.
	# Without this, we will be cleaned up before we have had time to do any
	# asynchronous work.
	cycleref = self

	logp("_run() as editorscript - Started")
	assert( OS.get_thread_caller_id() == OS.get_main_thread_id(),
		"A _run() must not be called in a threaded context.\n" + \
		"TestBase relies on the 'await' keyword and functionality which is." + \
		"not usable in a threaded context.\n")

	# NOTE: We run asynchronously so that a crash doesnt prevent reporting
	# the retults
	run_test.call_deferred()
	await test_finished

	cycleref = null


#         ███    ███ ███████ ████████ ██   ██  ██████  ██████  ███████         #
#         ████  ████ ██         ██    ██   ██ ██    ██ ██   ██ ██              #
#         ██ ████ ██ █████      ██    ███████ ██    ██ ██   ██ ███████         #
#         ██  ██  ██ ██         ██    ██   ██ ██    ██ ██   ██      ██         #
#         ██      ██ ███████    ██    ██   ██  ██████  ██████  ███████         #
func                        _________METHODS_________              ()->void:pass

func run_test() -> void:
	print("Processing: ", get_script().resource_path )

	assert( OS.get_thread_caller_id() == OS.get_main_thread_id(),
		"A run_test() must not be called in a threaded context.\n" + \
		"TestBase relies on the 'await' keyword and functionality which is." + \
		"not usable in a threaded context.\n")

	# Format Dictionary
	var fd:Dictionary
	scene_tree = EditorInterface.get_base_control().get_tree()

	# An opportunity for derived scripts to set the maximum run time and other
	# variables.
	@warning_ignore('redundant_await')
	if await _setup() != OK:
		fd = {'color':'tomato', 'msg':'_setup() - FAILED'}
		logp("[color={color}][b]_run() - {msg}[/b][/color]".format(fd) )
		return

	# In case of failure of some unforseen way, I want to make sure the name
	# of our timer node is unique
	var script:Script = get_script()
	var test_name:String = script.resource_path.validate_node_name()

	# Find, or create our timer.
	timer = scene_tree.root.find_child(test_name, false)
	if timer:
		logd( "Error: Timer was not removed in last run.")
		timer.queue_free()

	timer = Timer.new()
	timer.name = test_name
	scene_tree.root.add_child(timer)
	@warning_ignore('return_value_discarded')
	timer.timeout.connect( _on_timer_timeout )

	# Start the timer, and call the test function and await its finish.
	timer.start(max_runtime_s)

	@warning_ignore('redundant_await')
	runcode = await _run_test()

		# printing output.
	if runcode == RetCode.TEST_OK:
		fd = {'color':'yellowgreen', 'msg':'OK'}
	else:
		fd = {'color':'tomato', 'msg':'FAILED'}

	logp("[color={color}][b]_run() - {msg}[/b][/color]".format(fd) )
	if _verbose or _debug:
		output.reduce(Shared.reducer_to_lines)

	# Cleanup after ourselves.
	@warning_ignore('redundant_await')
	if await _cleanup() != OK:
		fd = {'color':'tomato', 'msg':'_cleanup() - FAILED'}
		logp("[color={color}][b]_run() - {msg}[/b][/color]".format(fd) )
	timer.queue_free()
	test_finished.emit()


func logd( msg:Variant = "" ) -> void:
	if msg is Array:
		var array:Array = msg
		msg = array.reduce( Shared.reducer_to_lines )
	if _debug:
		print_rich( msg )
		output.append( msg )


func logp( msg:Variant ) -> void:
	if msg is Array:
		var array:Array = msg
		msg = array.reduce( Shared.reducer_to_lines )
	if _debug or _verbose: print_rich( msg )
	output.append( msg )


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

# test is abstracted so that exceptions trigger a fail.
func _test_eq( want_v:Variant, got_v:Variant, desc:String = "" ) -> bool:
	if want_v == got_v: return true
	var msg := "[b][color=salmon]Failed: '%s'[/color][/b]\nwanted: '%s'\n   got: '%s'" % [desc, want_v, got_v ]
	output.append.call( msg )
	if _verbose: print_rich( msg )
	return false


## Returns [enum RetCode] 1 on failure, and 0 on OK.
func TEST_EQ_RET( want_v:Variant, got_v:Variant, desc:String = "" ) -> RetCode:
	logd("TEST_EQ_RET(want:'%s' == got:'%s'): %s" % [want_v, got_v, desc])
	if _test_eq(want_v, got_v, desc): return RetCode.TEST_OK
	runcode &= RetCode.TEST_FAILED
	return RetCode.TEST_FAILED


func TEST_EQ( want_v:Variant, got_v:Variant, desc:String = "") -> void:
	logd("TEST_EQ(want:'%s' == got:'%s'): %s" % [want_v, got_v, desc])
	if _test_eq(want_v, got_v, desc): return
	runcode &= RetCode.TEST_FAILED


func _test_approx( want_v:float, got_v:float, desc:String = "" ) -> bool:
	if is_equal_approx(want_v, got_v): return true
	var msg := "[b][color=salmon]Failed: '%s'[/color][/b]\nwanted: '%s'\n   got: '%s'" % [desc, want_v, got_v ]
	output.append.call( msg )
	if _verbose: print_rich( msg )
	return false


## Returns [enum RetCode] 1 on failure, and 0 on OK.
func TEST_APPROX_RET( want_v:float, got_v:float, desc:String = "" ) -> RetCode:
	logd("TEST_APPROX_RET(want:'%s' ~= got:'%s'): %s" % [want_v, got_v, desc])
	if _test_approx(want_v, got_v, desc ): return RetCode.TEST_OK
	runcode &= RetCode.TEST_FAILED
	return RetCode.TEST_FAILED


func TEST_APPROX( want_v:float, got_v:float, desc:String = "" ) -> void:
	logd("TEST_APPROX(want:'%s' ~= got:'%s'): %s" % [want_v, got_v, desc])
	if _test_approx(want_v, got_v, desc ): return
	runcode &= RetCode.TEST_FAILED


func _test_true( value:Variant, desc:String = "" ) -> bool:
	if value: return true
	var msg:String = "[b][color=salmon]TEST_TRUE Failed: '%s'[/color][/b]\nwanted: true | value != (0 & null)\n   got: '%s'" % [desc, value ]
	output.append.call( msg )
	if _verbose: print_rich( msg )
	return false


## Returns [enum RetCode] 1 on failure, and 0 on OK.
func TEST_TRUE_RET( value:Variant, desc:String = "" ) -> RetCode:
	logd("TEST_TRUE_RET('%s'): %s" % [value, desc])
	if _test_true( value, desc ): return RetCode.TEST_OK
	runcode &= RetCode.TEST_FAILED
	return RetCode.TEST_FAILED


func TEST_TRUE( value:Variant, desc:String = "" ) -> void:
	logd("TEST_TRUE('%s'): %s" % [value, desc])
	if _test_true( value, desc ): return
	runcode &= RetCode.TEST_FAILED


func _test_false( value:Variant, desc:String = "" ) -> bool:
	if not value: return true
	var msg:String = "[b][color=salmon]TEST_FALSE Failed: '%s'[/color][/b]\nwanted: false | value == (0 & null)\n   got: '%s'" % [desc, value ]
	output.append.call( msg )
	if _verbose: print_rich( msg )
	return false


## Returns [enum RetCode] 1 on failure, and 0 on OK.
func TEST_FALSE_RET( value:Variant, desc:String = "" ) -> RetCode:
	logd("TEST_FALSE_RET('%s'): %s" % [value, desc])
	if _test_true( value, desc ): return RetCode.TEST_OK
	runcode &= RetCode.TEST_FAILED
	return RetCode.TEST_FAILED


func TEST_FALSE( value:Variant, desc:String = "" ) -> void:
	logd("TEST_FALSE('%s'): %s" % [value, desc])
	if _test_true( value, desc ): return
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
	var msg:String = "[b][color=salmon]TEST_OP Failed: '%s'[/color][/b]" % desc
	msg += "\n\tOp: ('%s' %s '%s') is false" % [val1, op_string[op], val2]
	output.append.call( msg )
	if _verbose: print_rich( msg )
	return false


## Returns [enum RetCode] 1 on failure, and 0 on OK.
func TEST_OP_RET( val1:Variant, op:int, val2:Variant, desc:String = ""  ) -> RetCode:
	logd("TEST_OP_RET('%s', %s, '%s'): %s" % [val1, op_string[op], val2, desc])
	if _test_op(val1, op, val2, desc): return RetCode.TEST_OK
	runcode &= RetCode.TEST_FAILED
	return RetCode.TEST_FAILED


func TEST_OP( val1:Variant, op:int, val2:Variant, desc:String = ""  ) -> void:
	logd("TEST_OP('%s', %s, '%s'): %s" % [val1, op_string[op], val2, desc])
	if _test_op(val1, op, val2, desc): return
	runcode &= RetCode.TEST_FAILED

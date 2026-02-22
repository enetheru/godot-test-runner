@tool
extends TestBase

# runcode is defined in the parent script, it is the result that is checked for success
# it's default value is RetCode.TEST_OK, there is only TEST_OK and TEST_FAILED at this point

# var output:Array is where all the text is appended.

# var max_runtime_s:float is how long the test is allowed to run before timing out

# signal test_finished is triggered at the end.

# is a virtual override that can be used to setup state
func _setup() -> Error:
	return OK

# similarly, cleanup after onesself.
func _cleanup() -> Error:
	return OK

# the test is run in the main thread so that the await features can be used.

# logd("msg") can be used for logging to debug
# logp("msg") can be used for general logging
# both logging functions use print_rich

# sbytes(bytes, cols) can be used to print binary data in a hex format

# TEST_EQ( want_value, got_value, description) uses the == operator
# TEST_APPROX( want_value, got_value, description) uses the is_equal_approx(a,b) method
# TEST_TRUE( value description): uses 'if value'
# TEST_OP( a, op, b, description), where a and b are Variants, and op is one of Variant.Operator values

# This test should Succeed
func _run_test() -> int:
	TEST_EQ( 1, 1, "Testing EQUAL")

	TEST_APPROX(1.1,1.1,"Testing APPROX")

	TEST_TRUE( true )

	TEST_OP( 1, OP_EQUAL, 1, "Testing OP_EQUAL = true")
	TEST_OP( 1, OP_NOT_EQUAL, 0, "Testing OP_NOT_EQUAL = true")
	TEST_OP( 1, OP_GREATER_EQUAL, 0, "Testing OP_GREATER_EQUAL = true")
	TEST_OP( 1, OP_GREATER_EQUAL, 1, "Testing OP_GREATER_EQUAL = true")
	TEST_OP( 1, OP_GREATER, 0, "Testing OP_GREATER = true")
	TEST_OP( 0, OP_LESS_EQUAL, 1, "Testing OP_LESS_EQUAL = true")
	TEST_OP( 1, OP_LESS_EQUAL, 1, "Testing OP_LESS_EQUAL = true")
	TEST_OP( 0, OP_LESS, 1, "Testing OP_LESS = true")

	# This will spit errors, but the test will succeed.
	TEST_OP( 1, OP_EQUAL, 0, "Testing OP_EQUAL = false")
	TEST_OP( 1, OP_NOT_EQUAL, 1, "Testing OP_NOT_EQUAL = false")
	TEST_OP( 0, OP_GREATER_EQUAL, 1, "Testing OP_GREATER_EQUAL = false")
	TEST_OP( 0, OP_GREATER, 1, "Testing OP_GREATER = false")
	TEST_OP( 1, OP_LESS_EQUAL, 0, "Testing OP_LESS_EQUAL = false")
	TEST_OP( 1, OP_LESS, 0, "Testing OP_LESS = false")

	return runcode

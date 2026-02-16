@tool
extends EditorScript

#           ████ ███    ███ ██████   ██████  ██████  ████████ ███████          #
#            ██  ████  ████ ██   ██ ██    ██ ██   ██    ██    ██               #
#            ██  ██ ████ ██ ██████  ██    ██ ██████     ██    ███████          #
#            ██  ██  ██  ██ ██      ██    ██ ██   ██    ██         ██          #
#           ████ ██      ██ ██       ██████  ██   ██    ██    ███████          #
func                        _________IMPORTS_________              ()->void:pass

const InfoBox = preload('../info_box.gd')

#                       ██████  ███████ ███████ ███████                        #
#                       ██   ██ ██      ██      ██                             #
#                       ██   ██ █████   █████   ███████                        #
#                       ██   ██ ██      ██           ██                        #
#                       ██████  ███████ ██      ███████                        #
func                        __________DEFS___________              ()->void:pass

#NOTE: When a function bails due to assert, or crash, it returns the default
# value in the case of an integer that is 0, which unfortunately equates to OK
# So unfortunately in this case we have to flip the expectation and not rely
# on the builtin constants OK and FAILED
enum RetCode {
	TEST_FAILED = 0,
	TEST_OK = 1
}

class TestDef extends RefCounted:
	var name : String
	var folder_path : String
	var test_scripts : Array
	var results : Dictionary[TreeItem, TestResult]


class TestResult extends RefCounted:
	var latest : InfoBox
	var path : String
	var retcode : RetCode
	var output : Array

	func _to_string() -> String:
		return JSON.stringify({
			'latest':latest,
			'path':path,
			'retcode':retcode,
			'output':output
		}, "  ", false)

#         ███    ███ ███████ ████████ ██   ██  ██████  ██████  ███████         #
#         ████  ████ ██         ██    ██   ██ ██    ██ ██   ██ ██              #
#         ██ ████ ██ █████      ██    ███████ ██    ██ ██   ██ ███████         #
#         ██  ██  ██ ██         ██    ██   ██ ██    ██ ██   ██      ██         #
#         ██      ██ ███████    ██    ██   ██  ██████  ██████  ███████         #
func                        _________METHODS_________              ()->void:pass

static func reducer_to_lines(a:String = "", v:Variant = null) -> String:
	return (a + "\n%s" if a else "%s") % v

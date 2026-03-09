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

## NOTE: When a function bails due to assert, or crash, it returns the default
##  value in the case of an integer that is 0, which unfortunately equates to OK
##  So unfortunately in this case we have to flip the expectation and not rely
##  on the builtin constants OK and FAILED
enum RetCode {
	## TEST_FAILED = 0,
	TEST_FAILED = 0,
	
	## TEST_OK = 1
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
	if a: return a + "\n" +  str(v)
	return str(v)

static var folder_filter:Callable = func()->bool:return true
static var test_script_filter:Callable = func()->bool:return true
static var schema_file_filter:Callable = func()->bool:return true

static func collect_tests( test_path : String ) -> Array[Dictionary]:
	var tests : Array[Dictionary]

	var folders : Array = DirAccess.get_directories_at(test_path)
	var folder_paths:Array = folders.map(
		func(folder : String) -> String:
			return "/".join([test_path,folder]))
	folder_paths.sort()
	for folder_path : String in folder_paths.filter( folder_filter ):
		var files : Array = DirAccess.get_files_at( folder_path )
		var folder:String = folder_path.get_file()

		var test_dict : Dictionary = {
			"name": folder.to_pascal_case(),
			"folder_path": folder_path,
			"test_scripts": files.filter( test_script_filter ),
			"schema_files": files.filter( schema_file_filter )
		}
		tests.append( test_dict )

	return tests

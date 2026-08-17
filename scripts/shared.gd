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
	## Nested folders (same type). Empty when this folder has only scripts.
	var children : Array = []
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

static var folder_filter:Callable = func(_f:Variant)->bool:return true
static var test_script_filter:Callable = func(_f:Variant)->bool:return true
static var schema_file_filter:Callable = func(_f:Variant)->bool:return true

## Safety cap for junction / symlink cycles. Not a product tree-depth limit.
const DEFAULT_MAX_SCAN_DEPTH:int = 32


## Nested folder dicts: name, folder_path, test_scripts, schema_files, children.
static func collect_test_tree(
			test_path:String,
			max_depth:int = DEFAULT_MAX_SCAN_DEPTH,
			script_filter:Callable = test_script_filter,
			schema_filter:Callable = schema_file_filter,
			dir_filter:Callable = Callable()
			) -> Array[Dictionary]:
	var visited:Dictionary = {}
	var out:Array[Dictionary] = []
	var folders:PackedStringArray = DirAccess.get_directories_at( test_path )
	var names:Array[String] = []
	for folder:String in folders:
		names.append( folder )
	names.sort()
	for folder:String in names:
		if _skip_dir_name( folder ):
			continue
		var node:Dictionary = _scan_test_dir(
				test_path.path_join( folder ),
				1,
				max_depth,
				visited,
				script_filter,
				schema_filter,
				dir_filter )
		if not node.is_empty():
			out.append( node )
	return out


## Flat list of folders that contain scripts (nested children inlined).
static func collect_tests( test_path:String ) -> Array[Dictionary]:
	return flatten_test_tree( collect_test_tree( test_path ) )


static func flatten_test_tree( tree:Array ) -> Array[Dictionary]:
	var out:Array[Dictionary] = []
	for node_v:Variant in tree:
		if not node_v is Dictionary:
			continue
		var node:Dictionary = node_v
		var scripts:Array = node.get( "test_scripts", [] )
		if not scripts.is_empty():
			out.append( node )
		var kids:Array = node.get( "children", [] )
		if not kids.is_empty():
			out.append_array( flatten_test_tree( kids ) )
	return out


static func _skip_dir_name( folder:String ) -> bool:
	return folder.is_empty() \
	or folder.begins_with( "." )


static func _abs_visit_key( folder_path:String ) -> String:
	var abs_path:String = ProjectSettings.globalize_path( folder_path )
	return abs_path.simplify_path().replace( "\\", "/" ).to_lower()


static func _scan_test_dir(
			folder_path:String,
			depth:int,
			max_depth:int,
			visited:Dictionary,
			script_filter:Callable,
			schema_filter:Callable,
			dir_filter:Callable
			) -> Dictionary:
	if depth > max_depth:
		return {}
	if dir_filter.is_valid() \
	and not dir_filter.call( folder_path ):
		return {}
	var key:String = _abs_visit_key( folder_path )
	if key.is_empty() \
	or visited.has( key ):
		return {}
	visited[key] = true

	var files:PackedStringArray = DirAccess.get_files_at( folder_path )
	var scripts:Array = []
	var schemas:Array = []
	for f:String in files:
		if script_filter.is_valid() \
		and script_filter.call( f ):
			scripts.append( f )
		if schema_filter.is_valid() \
		and schema_filter.call( f ):
			schemas.append( f )

	var children:Array = []
	if depth < max_depth:
		var sub_names:Array[String] = []
		for folder:String in DirAccess.get_directories_at( folder_path ):
			sub_names.append( folder )
		sub_names.sort()
		for folder:String in sub_names:
			if _skip_dir_name( folder ):
				continue
			var child:Dictionary = _scan_test_dir(
					folder_path.path_join( folder ),
					depth + 1,
					max_depth,
					visited,
					script_filter,
					schema_filter,
					dir_filter )
			if not child.is_empty():
				children.append( child )

	if scripts.is_empty() \
	and children.is_empty():
		return {}

	return {
		"name": folder_path.get_file().to_pascal_case(),
		"folder_path": folder_path,
		"test_scripts": scripts,
		"schema_files": schemas,
		"children": children,
	}


## returns a bbcode string url to the source location at [param depth].
static func get_call_site(depth:int = 1) -> String:
	var stack:Array = get_stack()
	var frame:Dictionary = stack[mini(stack.size(), depth)]
	return "[url='{source}:{line}']{source}:{line}:{function}()[/url]".format(frame)

@tool
extends RefCounted

## Folder walk for the panel and the service.
##
## Each dictionary has [code]name[/code], [code]folder_path[/code],
## [code]test_scripts[/code], and [code]children[/code]. A folder with no
## scripts and no child folders is left out. [constant DEFAULT_MAX_SCAN_DEPTH]
## stops a junction cycle.


const DEFAULT_MAX_SCAN_DEPTH:int = 32


# ██████  ██████   ██████  ██████  ███████ ██████  ████████ ██ ███████ ███████ #
# ██   ██ ██   ██ ██    ██ ██   ██ ██      ██   ██    ██    ██ ██      ██      #
# ██████  ██████  ██    ██ ██████  █████   ██████     ██    ██ █████   ███████ #
# ██      ██   ██ ██    ██ ██      ██      ██   ██    ██    ██ ██           ██ #
# ██      ██   ██  ██████  ██      ███████ ██   ██    ██    ██ ███████ ███████ #
func                        ________PROPERTIES_______              ()->void:pass

# Default when a caller passes no script filter. Accepts every file name.
static var _accept_file:Callable = func( _file_name:Variant ) -> bool: return true


#                 ███████ ████████  █████  ████████ ██  ██████                 #
#                 ██         ██    ██   ██    ██    ██ ██                      #
#                 ███████    ██    ███████    ██    ██ ██                      #
#                      ██    ██    ██   ██    ██    ██ ██                      #
#                 ███████    ██    ██   ██    ██    ██  ██████                 #
func                        __________STATIC_________              ()->void:pass

## Nested folder dictionaries under [param test_path].
static func collect_test_tree(
		test_path:String,
		max_depth:int = DEFAULT_MAX_SCAN_DEPTH,
		script_filter:Callable = _accept_file,
		dir_filter:Callable = Callable()
		) -> Array[Dictionary]:
	var visited:Dictionary = {}
	var out:Array[Dictionary] = []
	var names:Array[String] = _sorted_dirs( test_path )
	for folder:String in names:
		if _skip_dir_name( folder ):
			continue

		var node:Dictionary = _scan_test_dir(
				test_path.path_join( folder ),
				1,
				max_depth,
				visited,
				script_filter,
				dir_filter )
		if node.is_empty():
			continue
		out.append( node )
	return out


#       ██ ███    ██ ████████ ███████ ██████  ███    ██  █████  ██             #
#       ██ ████   ██    ██    ██      ██   ██ ████   ██ ██   ██ ██             #
#       ██ ██ ██  ██    ██    █████   ██████  ██ ██  ██ ███████ ██             #
#       ██ ██  ██ ██    ██    ██      ██   ██ ██  ██ ██ ██   ██ ██             #
#       ██ ██   ████    ██    ███████ ██   ██ ██   ████ ██   ██ ███████        #
func                        ________INTERNAL_________              ()->void:pass

static func _skip_dir_name( folder:String ) -> bool:
	return folder.is_empty() or folder.begins_with( "." )


static func _sorted_dirs( folder_path:String ) -> Array[String]:
	var names:Array[String] = []
	for folder:String in DirAccess.get_directories_at( folder_path ):
		names.append( folder )
	names.sort()
	return names


static func _abs_visit_key( folder_path:String ) -> String:
	var abs_path:String = ProjectSettings.globalize_path( folder_path )
	return abs_path.simplify_path().replace( "\\", "/" ).to_lower()


static func _scan_test_dir(
		folder_path:String,
		depth:int,
		max_depth:int,
		visited:Dictionary,
		script_filter:Callable,
		dir_filter:Callable
		) -> Dictionary:
	if depth > max_depth:
		return {}
	if dir_filter.is_valid() and not dir_filter.call( folder_path ):
		return {}

	var key:String = _abs_visit_key( folder_path )
	if key.is_empty() or visited.has( key ):
		return {}
	visited[key] = true

	var scripts:Array = []
	for file_name:String in DirAccess.get_files_at( folder_path ):
		if script_filter.is_valid() and script_filter.call( file_name ):
			scripts.append( file_name )

	var children:Array = []
	if depth < max_depth:
		for folder:String in _sorted_dirs( folder_path ):
			if _skip_dir_name( folder ):
				continue
			var child:Dictionary = _scan_test_dir(
					folder_path.path_join( folder ),
					depth + 1,
					max_depth,
					visited,
					script_filter,
					dir_filter )
			if child.is_empty():
				continue
			children.append( child )

	if scripts.is_empty() and children.is_empty():
		return {}

	return {
		"name": folder_path.get_file().to_pascal_case(),
		"folder_path": folder_path,
		"test_scripts": scripts,
		"children": children,
	}

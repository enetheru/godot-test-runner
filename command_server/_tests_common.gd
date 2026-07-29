@tool
extends RefCounted

## Shared helpers for TESTS_* Command Server handlers.


static func find_test_runner_plugin() -> EditorPlugin:
	if not Engine.is_editor_hint():
		return null
	var base:Control = EditorInterface.get_base_control()
	if base == null:
		return null
	var tree:SceneTree = base.get_tree()
	if tree == null:
		return null
	return _find_plugin( tree.root )


static func _find_plugin( n:Node ) -> EditorPlugin:
	if n == null:
		return null
	if n is EditorPlugin:
		var scr:Script = n.get_script()
		if scr != null:
			var path:String = scr.resource_path
			if path.ends_with( "enetheru.test-runner/plugin.gd" ) \
			or path.ends_with( "test-runner/plugin.gd" ):
				return n as EditorPlugin
			# Fallback: plugin name method.
			if n.has_method( &"_get_plugin_name" ):
				var pname:Variant = n.call( &"_get_plugin_name" )
				if str( pname ) == "TestRunner":
					return n as EditorPlugin
	for c:Node in n.get_children():
		var found:EditorPlugin = _find_plugin( c )
		if found != null:
			return found
	return null


static func get_service() -> Node:
	var plugin:EditorPlugin = find_test_runner_plugin()
	if plugin == null:
		return null
	if plugin.has_method( &"get_test_runner_service" ):
		var svc_v:Variant = plugin.call( &"get_test_runner_service" )
		if svc_v is Node:
			return svc_v
	# Fallback: named child.
	var child:Node = plugin.get_node_or_null( "TestRunnerService" )
	return child


static func require_service() -> Dictionary:
	var svc:Node = get_service()
	if svc == null:
		return { &"error": "ERROR: TestRunner service not available (enable enetheru.test-runner)" }
	return { &"service": svc }


## Parse trailing flag tokens: verbose / debug / parallel (+ =0|1|true|false).
## Returns remaining positional tokens + flags dict.
static func parse_flags( args:String ) -> Dictionary:
	var tokens:PackedStringArray = args.strip_edges().split( " ", false )
	var positional:Array = []
	var verbose_set:bool = false
	var debug_set:bool = false
	var parallel_set:bool = false
	var verbose:bool = false
	var debug:bool = false
	var parallel:bool = false

	for t:String in tokens:
		var low:String = t.to_lower()
		if low == "verbose" or low == "verbose=1" or low == "verbose=true":
			verbose = true
			verbose_set = true
		elif low == "verbose=0" or low == "verbose=false":
			verbose = false
			verbose_set = true
		elif low == "debug" or low == "debug=1" or low == "debug=true":
			debug = true
			debug_set = true
		elif low == "debug=0" or low == "debug=false":
			debug = false
			debug_set = true
		elif low == "parallel" or low == "parallel=1" or low == "parallel=true":
			parallel = true
			parallel_set = true
		elif low == "parallel=0" or low == "parallel=false":
			parallel = false
			parallel_set = true
		elif low.begins_with( "verbose=" ) \
		or low.begins_with( "debug=" ) \
		or low.begins_with( "parallel=" ):
			return { &"error": "ERROR: bad flag token '%s'" % t }
		else:
			positional.append( t )

	return {
		&"positional": positional,
		&"verbose": verbose,
		&"debug": debug,
		&"parallel": parallel,
		&"verbose_set": verbose_set,
		&"debug_set": debug_set,
		&"parallel_set": parallel_set,
	}

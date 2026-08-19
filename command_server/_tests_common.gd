@tool
extends RefCounted

## Shared helpers for TESTS_* Command Server handlers.


static func find_test_runner_plugin() -> EditorPlugin:
	if not Engine.is_editor_hint():
		return null
	var base:Control = EditorInterface.get_base_control()
	if not is_instance_valid( base ):
		return null
	var tree:SceneTree = base.get_tree()
	if not is_instance_valid( tree ):
		return null
	return _find_plugin( tree.root )


static func _find_plugin( n:Node ) -> EditorPlugin:
	if not is_instance_valid( n ):
		return null
	if n is EditorPlugin:
		var p:EditorPlugin = n as EditorPlugin
		var scr:Script = p.get_script()
		if is_instance_valid( scr ):
			var path:String = scr.resource_path
			if path.ends_with( "enetheru.test-runner/plugin.gd" ) \
			or path.ends_with( "test-runner/plugin.gd" ):
				return p
		if p.has_method( &"_get_plugin_name" ):
			var pname:Variant = p.call( &"_get_plugin_name" )
			if str( pname ) == "TestRunner":
				return p
	for c:Node in n.get_children():
		var found:EditorPlugin = _find_plugin( c )
		if is_instance_valid( found ):
			return found
	return null


static func get_service() -> Node:
	var plugin:EditorPlugin = find_test_runner_plugin()
	if not is_instance_valid( plugin ):
		return null
	if plugin.has_method( &"get_test_runner_service" ):
		var svc_v:Variant = plugin.call( &"get_test_runner_service" )
		if svc_v is Node:
			return svc_v
	return plugin.get_node_or_null( "TestRunnerService" )


static func require_service() -> Dictionary:
	var svc:Node = get_service()
	if not is_instance_valid( svc ):
		return {
			&"error": "ERROR: TestRunner service not available (enable enetheru.test-runner)",
		}
	return { &"service": svc }


static func dict_error( arguments:Dictionary ) -> String:
	if arguments.has( &"error" ):
		return str( arguments[&"error"] )
	if arguments.has( "error" ):
		return str( arguments["error"] )
	return ""


static func bool_arg( arguments:Dictionary, key:StringName, default_v:bool = false ) -> bool:
	var v:Variant = default_v
	if arguments.has( key ):
		v = arguments[key]
	elif arguments.has( String( key ) ):
		v = arguments[String( key )]
	return v if v is bool else default_v


static func string_arg( arguments:Dictionary, key:StringName, default_v:String = "" ) -> String:
	var v:Variant = default_v
	if arguments.has( key ):
		v = arguments[key]
	elif arguments.has( String( key ) ):
		v = arguments[String( key )]
	return str( v ) if v != null else default_v


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

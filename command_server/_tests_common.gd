@tool
extends RefCounted

## Shared helpers for TESTS_* Command Server handlers.

const Log = preload( "../logging.gd" )


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


## Parse trailing flag tokens: level= / lvl= and parallel.
## Returns remaining positional tokens plus the flags.
static func parse_flags( args:String ) -> Dictionary:
	var tokens:PackedStringArray = args.strip_edges().split( " ", false )
	var positional:Array = []
	var lvl:int = -1
	var lvl_set:bool = false
	var parallel_set:bool = false
	var parallel:bool = false

	for t:String in tokens:
		var low:String = t.to_lower()
		if low == "level" or low == "lvl":
			return {
				&"error": "ERROR: level needs notice, info, debug, or trace",
			}
		if low.begins_with( "level=" ) or low.begins_with( "lvl=" ):
			var name:String = low.substr( low.find( "=" ) + 1 )
			var got:int = Log.parse_level( name )
			if got < 0:
				return { &"error": "ERROR: bad level '%s'" % name }
			if lvl_set and lvl != got:
				return { &"error": "ERROR: level given twice" }
			lvl = got
			lvl_set = true
		elif low == "parallel" or low == "parallel=1" or low == "parallel=true":
			parallel = true
			parallel_set = true
		elif low == "parallel=0" or low == "parallel=false":
			parallel = false
			parallel_set = true
		elif low.begins_with( "parallel=" ):
			return { &"error": "ERROR: bad flag token '%s'" % t }
		else:
			positional.append( t )

	return {
		&"positional": positional,
		&"lvl": lvl,
		&"parallel": parallel,
		&"lvl_set": lvl_set,
		&"parallel_set": parallel_set,
	}

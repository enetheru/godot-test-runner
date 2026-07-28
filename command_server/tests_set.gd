@tool
extends CommandServerCommand

const Common = preload( "_tests_common.gd" )


func get_name() -> String:
	return "TESTS_SET"


func get_description() -> String:
	return "Set TestRunner verbose/debug flags without running tests."


func get_usage() -> String:
	return "TESTS_SET [verbose|verbose=0|1] [debug|debug=0|1]"


func execute( args:String, _context:Dictionary ) -> String:
	var req:Dictionary = Common.require_service()
	if req.has( &"error" ):
		return str( req[&"error"] )
	var svc:Node = req[&"service"]
	var parsed:Dictionary = Common.parse_flags( args )
	if parsed.has( &"error" ):
		return str( parsed[&"error"] )
	var positional:PackedStringArray = parsed.get( &"positional", PackedStringArray() )
	if not positional.is_empty():
		return "ERROR: unexpected args: %s (usage: %s)" % [
				" ".join( positional ),
				get_usage(),
		]
	if not parsed.get( &"verbose_set", false ) \
	and not parsed.get( &"debug_set", false ):
		return "ERROR: Usage: " + get_usage()

	var v:bool = svc.get( "verbose" )
	var d:bool = svc.get( "debug" )
	if parsed.get( &"verbose_set", false ):
		v = parsed.get( &"verbose", false )
	if parsed.get( &"debug_set", false ):
		d = parsed.get( &"debug", false )
	svc.call( &"set_flags", v, d )

	# Mirror to panel toggles when present.
	var plugin:EditorPlugin = Common.find_test_runner_plugin()
	if plugin != null and plugin.get( "main_panel_instance" ) != null:
		var panel:Object = plugin.get( "main_panel_instance" )
		if panel != null:
			if panel.get( "test_verbose" ) != null:
				panel.set( "test_verbose", v )
			if panel.get( "test_debug" ) != null:
				panel.set( "test_debug", d )
			if panel.get( "verbose_btn" ) is CheckButton:
				var cb:CheckButton = panel.get( "verbose_btn" )
				cb.set_pressed_no_signal( v )
			if panel.get( "debug_btn" ) is CheckButton:
				var cb:CheckButton = panel.get( "debug_btn" )
				cb.set_pressed_no_signal( d )

	return "OK: verbose=%s debug=%s" % [str( v ), str( d )]

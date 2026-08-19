@tool
extends CommandServerTool

const Common = preload( "_tests_common.gd" )


func get_command_name() -> String:
	return "TESTS_SET"


func get_description() -> String:
	return "Set TestRunner verbose/debug flags without running tests."


func get_usage() -> String:
	return "TESTS_SET [verbose|verbose=0|1] [debug|debug=0|1]"


func get_input_schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"verbose": {
				"type": "boolean",
				"description": "Enable verbose TestRunner logging.",
			},
			"debug": {
				"type": "boolean",
				"description": "Enable debug TestRunner logging.",
			},
		},
		"additionalProperties": false,
	}


func arguments_from_line( line:String, _tail:String ) -> Dictionary:
	var parsed:Dictionary = Common.parse_flags( line )
	if parsed.has( &"error" ):
		return parsed
	var positional:PackedStringArray = parsed.get( &"positional", PackedStringArray() )
	if not positional.is_empty():
		return {
			&"error": "ERROR: unexpected args: %s (usage: %s)" % [
					" ".join( positional ),
					get_usage(),
			],
		}
	if not parsed.get( &"verbose_set", false ) \
	and not parsed.get( &"debug_set", false ):
		return { &"error": "ERROR: Usage: " + get_usage() }
	var out:Dictionary = {}
	if parsed.get( &"verbose_set", false ):
		out[&"verbose"] = parsed.get( &"verbose", false )
	if parsed.get( &"debug_set", false ):
		out[&"debug"] = parsed.get( &"debug", false )
	return out


func execute( arguments:Dictionary, _context:Dictionary ) -> Dictionary:
	var err:String = Common.dict_error( arguments )
	if not err.is_empty():
		return result_from_text( err )
	var extra:String = line_from_arguments( arguments ).strip_edges()
	var parsed:Dictionary = {}
	if not extra.is_empty():
		parsed = arguments_from_line( extra, "" )
		err = Common.dict_error( parsed )
		if not err.is_empty():
			return result_from_text( err )
	else:
		parsed = arguments
	var has_v:bool = parsed.has( &"verbose" ) or parsed.has( "verbose" )
	var has_d:bool = parsed.has( &"debug" ) or parsed.has( "debug" )
	if not has_v and not has_d:
		return result_from_text( "ERROR: Usage: " + get_usage() )
	var req:Dictionary = Common.require_service()
	if req.has( &"error" ):
		return result_from_text( str( req[&"error"] ) )
	var svc:Node = req[&"service"]
	var v:bool = svc.get( "verbose" )
	var d:bool = svc.get( "debug" )
	if has_v:
		v = Common.bool_arg( parsed, &"verbose", v )
	if has_d:
		d = Common.bool_arg( parsed, &"debug", d )
	svc.call( &"set_flags", v, d )
	_mirror_panel( v, d )
	return result_from_text( "OK: verbose=%s debug=%s" % [str( v ), str( d )] )


func _mirror_panel( v:bool, d:bool ) -> void:
	var plugin:EditorPlugin = Common.find_test_runner_plugin()
	if not is_instance_valid( plugin ):
		return
	var panel_v:Variant = plugin.get( "main_panel_instance" )
	if not ( panel_v is Object ):
		return
	var panel:Object = panel_v
	if panel.get( "test_verbose" ) != null:
		panel.set( "test_verbose", v )
	if panel.get( "test_debug" ) != null:
		panel.set( "test_debug", d )
	if panel.get( "verbose_btn" ) is CheckButton:
		var vb:CheckButton = panel.get( "verbose_btn" )
		vb.set_pressed_no_signal( v )
	if panel.get( "debug_btn" ) is CheckButton:
		var db:CheckButton = panel.get( "debug_btn" )
		db.set_pressed_no_signal( d )

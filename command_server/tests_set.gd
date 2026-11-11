@tool
extends CommandServerTool

const Common = preload( "uid://byjo8kv2agqny" )
const Log = preload( "uid://br7jtx5cntuan" )


func get_command_name() -> String:
	return "TESTS_SET"


func get_description() -> String:
	return "Set the TestRunner log level without running tests."


func get_usage() -> String:
	return "TESTS_SET level=<notice|info|debug|trace>"


func get_input_schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"level": {
				"type": "string",
				"description": "Inclusive log ceiling: notice, info, debug, or trace.",
				"enum": ["notice", "info", "debug", "trace"],
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
	if not parsed.get( &"lvl_set", false ):
		return { &"error": "ERROR: Usage: " + get_usage() }
	return { &"level": parsed.get( &"lvl", -1 ) }


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
	var has_level:bool = parsed.has( &"level" ) or parsed.has( "level" )
	if not has_level:
		return result_from_text( "ERROR: Usage: " + get_usage() )
	var raw:Variant = parsed[&"level"] if parsed.has( &"level" ) else parsed["level"]
	var level:int = Log.parse_level( raw )
	if level < 0:
		return result_from_text(
				"ERROR: bad level '%s' (notice|info|debug|trace)" % str( raw )
		)
	var req:Dictionary = Common.require_service()
	if req.has( &"error" ):
		return result_from_text( str( req[&"error"] ) )
	var svc:Node = req[&"service"]
	svc.call( &"set_lvl", level )
	_mirror_panel( level )
	return result_from_text( "OK: level=%s" % Log.level_name( level ) )


func _mirror_panel( level:int ) -> void:
	var plugin:EditorPlugin = Common.find_test_runner_plugin()
	if not is_instance_valid( plugin ):
		return
	var panel_v:Variant = plugin.get( "main_panel_instance" )
	if not ( panel_v is Object ):
		return
	var panel:Object = panel_v
	if panel.has_method( &"set_lvl" ):
		panel.call( &"set_lvl", level )

@tool
extends CommandServerTool

const Common = preload( "_tests_common.gd" )


func get_command_name() -> String:
	return "TESTS_LIST"


func get_description() -> String:
	return "List TestRunner groups and scripts under res://tests."


func get_usage() -> String:
	return "TESTS_LIST [--json]"


func get_input_schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"json": {
				"type": "boolean",
				"description": "If true, reply with JSON instead of text.",
			},
		},
		"additionalProperties": false,
	}


func arguments_from_line( line:String, _tail:String ) -> Dictionary:
	var raw:String = line.strip_edges()
	if raw.is_empty():
		return { &"json": false }
	var low:String = raw.to_lower()
	if low == "--json" or low == "json":
		return { &"json": true }
	return {
		&"error": "ERROR: TESTS_LIST unknown args (use --json or none). Usage: "
				+ get_usage(),
	}


func execute( arguments:Dictionary, _context:Dictionary ) -> Dictionary:
	var err:String = Common.dict_error( arguments )
	if not err.is_empty():
		return result_from_text( err )
	var extra:String = line_from_arguments( arguments ).strip_edges()
	var want_json:bool = Common.bool_arg( arguments, &"json", false )
	if not extra.is_empty():
		var low:String = extra.to_lower()
		if low == "--json" or low == "json":
			want_json = true
		else:
			return result_from_text(
					"ERROR: TESTS_LIST unknown args (use --json or none). Usage: "
					+ get_usage()
			)
	var req:Dictionary = Common.require_service()
	if req.has( &"error" ):
		return result_from_text( str( req[&"error"] ) )
	var svc:Node = req[&"service"]
	if want_json:
		var list:Variant = svc.call( &"list_tests" )
		return result_from_text( "OK: TESTS_LIST\n" + JSON.stringify( list ) )
	return result_from_text( str( svc.call( &"format_list_text" ) ) )

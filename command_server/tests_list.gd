@tool
extends CommandServerCommand

const Common = preload( "_tests_common.gd" )


func get_name() -> String:
	return "TESTS_LIST"


func get_description() -> String:
	return "List TestRunner groups and scripts under res://tests."


func get_usage() -> String:
	return "TESTS_LIST [--json]"


func execute( args:String, _context:Dictionary ) -> String:
	var req:Dictionary = Common.require_service()
	if req.has( &"error" ):
		return str( req[&"error"] )
	var svc:Node = req[&"service"]
	var want_json:bool = args.strip_edges().to_lower() == "--json" \
			or args.strip_edges().to_lower() == "json"
	if want_json:
		var list:Variant = svc.call( &"list_tests" )
		return "OK: TESTS_LIST\n" + JSON.stringify( list )
	return str( svc.call( &"format_list_text" ) )

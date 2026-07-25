@tool
extends CommandServerCommand

const Common = preload( "_tests_common.gd" )


func get_name() -> String:
	return "TESTS_LAST"


func get_description() -> String:
	return "Return last TestRunner batch results (memory or user://test_runner_last.json)."


func get_usage() -> String:
	return "TESTS_LAST"


func execute( _args:String, _context:Dictionary ) -> String:
	var req:Dictionary = Common.require_service()
	if req.has( &"error" ):
		return str( req[&"error"] )
	var svc:Node = req[&"service"]
	var results:Dictionary = svc.call( &"get_last_results" )
	if results.is_empty():
		return "ERROR: no last results (run TESTS_RUN first)"
	return str( svc.call( &"format_results_reply", results, "TESTS_LAST" ) )

@tool
extends CommandServerCommand

const Common = preload( "_tests_common.gd" )


func get_name() -> String:
	return "TESTS_CLEAR"


func get_description() -> String:
	return "Clear TestRunner last results (service + panel InfoBoxes)."


func get_usage() -> String:
	return "TESTS_CLEAR"


func execute( _args:String, _context:Dictionary ) -> String:
	var req:Dictionary = Common.require_service()
	if req.has( &"error" ):
		return str( req[&"error"] )
	var plugin:EditorPlugin = Common.find_test_runner_plugin()
	if plugin != null and plugin.get( "main_panel_instance" ) != null:
		var panel:Object = plugin.get( "main_panel_instance" )
		if panel.has_method( &"clear_results_ui" ):
			panel.call( &"clear_results_ui" )
			return "OK: results cleared"
	# Panel not ready — clear service only.
	var svc:Node = req[&"service"]
	svc.call( &"clear_results" )
	return "OK: results cleared (service only)"

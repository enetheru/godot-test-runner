@tool
extends CommandServerTool

const Common = preload( "_tests_common.gd" )


func get_command_name() -> String:
	return "TESTS_CLEAR"


func get_description() -> String:
	return "Clear TestRunner last results (service + panel InfoBoxes)."


func get_usage() -> String:
	return "TESTS_CLEAR"


func get_input_schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {},
		"additionalProperties": false,
	}


func _execute_line( _args:String, _context:Dictionary ) -> String:
	var req:Dictionary = Common.require_service()
	if req.has( &"error" ):
		return str( req[&"error"] )
	var plugin:EditorPlugin = Common.find_test_runner_plugin()
	if is_instance_valid( plugin ):
		var panel_v:Variant = plugin.get( "main_panel_instance" )
		if panel_v is Object:
			var panel:Object = panel_v
			if panel.has_method( &"clear_results_ui" ):
				panel.call( &"clear_results_ui" )
				return "OK: results cleared"
	var svc:Node = req[&"service"]
	svc.call( &"clear_results" )
	return "OK: results cleared (service only)"

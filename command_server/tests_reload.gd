@tool
extends CommandServerTool

const Common = preload( "_tests_common.gd" )


func get_command_name() -> String:
	return "TESTS_RELOAD"


func get_description() -> String:
	return "Rescan res://tests and refresh TestRunner discovery."


func get_usage() -> String:
	return "TESTS_RELOAD"


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
	var svc:Node = req[&"service"]
	svc.call( &"reload" )
	var plugin:EditorPlugin = Common.find_test_runner_plugin()
	if is_instance_valid( plugin ):
		var panel_v:Variant = plugin.get( "main_panel_instance" )
		if panel_v is Object:
			var panel:Object = panel_v
			if panel.has_method( &"regenerate_tree" ):
				panel.call( &"regenerate_tree" )
	var list:Array = svc.call( &"list_tests" )
	var n_groups:int = list.size()
	var n_scripts:int = 0
	for g:Variant in list:
		if g is Dictionary:
			var gd:Dictionary = g
			var scripts:Array = gd.get( "scripts", [] )
			n_scripts += scripts.size()
	return "OK: reloaded groups=%d scripts=%d" % [n_groups, n_scripts]

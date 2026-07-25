@tool
extends CommandServerCommand

const Common = preload( "_tests_common.gd" )


func get_name() -> String:
	return "TESTS_RELOAD"


func get_description() -> String:
	return "Rescan res://tests and refresh TestRunner discovery."


func get_usage() -> String:
	return "TESTS_RELOAD"


func execute( _args:String, _context:Dictionary ) -> String:
	var req:Dictionary = Common.require_service()
	if req.has( &"error" ):
		return str( req[&"error"] )
	var svc:Node = req[&"service"]
	svc.call( &"reload" )
	# Best-effort: refresh panel tree if present.
	var plugin:EditorPlugin = Common.find_test_runner_plugin()
	if plugin != null and plugin.get( "main_panel_instance" ) != null:
		var panel:Variant = plugin.get( "main_panel_instance" )
		if panel is Object and ( panel as Object ).has_method( &"regenerate_tree" ):
			( panel as Object ).call( &"regenerate_tree" )
	var list:Variant = svc.call( &"list_tests" )
	var n_groups:int = 0
	var n_scripts:int = 0
	if list is Array:
		n_groups = ( list as Array ).size()
		for g:Variant in list:
			if g is Dictionary:
				n_scripts += ( g as Dictionary ).get( "scripts", [] ).size()
	return "OK: reloaded groups=%d scripts=%d" % [n_groups, n_scripts]

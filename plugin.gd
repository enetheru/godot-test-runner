@tool
extends EditorPlugin

const MainPanel = preload( "main_panel.tscn" )
const CHECKLIST = preload( "res/checklist.svg" )
const ServiceScript = preload( "test_runner_service.gd" )

const CS_OWNER:String = "enetheru.test-runner"
const _ExportPlugin = preload( "export_plugin.gd" )

var main_panel_instance:Control
var service:Node = null
var _cs_plugin:EditorPlugin = null
var _cs_reloaded_cb:Callable = Callable()
var _export_plugin:EditorExportPlugin = null


func _enter_tree() -> void:
	_export_plugin = _ExportPlugin.new()
	add_export_plugin( _export_plugin )

	service = ServiceScript.new()
	service.name = "TestRunnerService"
	add_child( service )
	service.call( &"reload" )

	main_panel_instance = MainPanel.instantiate()
	EditorInterface.get_editor_main_screen().add_child( main_panel_instance )
	_make_visible( false )
	if main_panel_instance.has_method( &"bind_service" ):
		main_panel_instance.call( &"bind_service", service )
	call_deferred( &"_register_with_command_server" )


func _exit_tree() -> void:
	if _export_plugin:
		remove_export_plugin( _export_plugin )
		_export_plugin = null
	_unregister_from_command_server()
	if main_panel_instance:
		main_panel_instance.queue_free()
		main_panel_instance = null
	if is_instance_valid( service ):
		service.queue_free()
		service = null


func _has_main_screen() -> bool:
	return true


func _make_visible( visible:bool ) -> void:
	if main_panel_instance:
		main_panel_instance.visible = visible


func _get_plugin_name() -> String:
	return "TestRunner"


func _get_plugin_icon() -> Texture2D:
	return CHECKLIST


func get_test_runner_service() -> Node:
	return service


func _register_with_command_server() -> void:
	_unregister_from_command_server()
	var cs:EditorPlugin = _find_command_server()
	if not is_instance_valid( cs ):
		print( "TestRunner: Command Server not found; TESTS_* commands not registered" )
		return
	if not cs.has_method( &"register_commands_from_path" ):
		push_warning(
				"TestRunner: Command Server missing register_commands_from_path "
				+ "(update enetheru.command-server)"
		)
		return

	var rpath:String = get_script().resource_path
	var cmd_dir:String = rpath.get_base_dir().path_join( "command_server" )
	var added:int = cs.call( &"register_commands_from_path", cmd_dir, CS_OWNER )
	_cs_plugin = cs
	if cs.has_signal( &"commands_reloaded" ):
		_cs_reloaded_cb = _on_command_server_reloaded
		if not cs.is_connected( &"commands_reloaded", _cs_reloaded_cb ):
			var err:Error = cs.connect( &"commands_reloaded", _cs_reloaded_cb )
			if err != OK:
				push_error( "TestRunner: connect commands_reloaded failed: %d" % err )
	print( "TestRunner: registered %d command(s) with Command Server" % added )


func _on_command_server_reloaded() -> void:
	# Builtin rescan finished; re-publish our external commands.
	call_deferred( &"_register_with_command_server" )


func _unregister_from_command_server() -> void:
	if is_instance_valid( _cs_plugin ):
		if _cs_reloaded_cb.is_valid() \
		and _cs_plugin.is_connected( &"commands_reloaded", _cs_reloaded_cb ):
			_cs_plugin.disconnect( &"commands_reloaded", _cs_reloaded_cb )
		if _cs_plugin.has_method( &"unregister_owner" ):
			_cs_plugin.call( &"unregister_owner", CS_OWNER )
	_cs_plugin = null
	_cs_reloaded_cb = Callable()


func _find_command_server() -> EditorPlugin:
	var helper:Script = load(
			"res://addons/enetheru.command-server/command_server.gd"
	) as Script
	if is_instance_valid( helper ) \
	and helper.has_method( &"get_command_server_plugin" ):
		var found:Variant = helper.call( &"get_command_server_plugin" )
		if found is EditorPlugin:
			return found
	var base:Control = EditorInterface.get_base_control()
	if not is_instance_valid( base ):
		return null
	return _find_cs_in_tree( base.get_tree().root )


func _find_cs_in_tree( n:Node ) -> EditorPlugin:
	if not is_instance_valid( n ):
		return null
	if n is EditorPlugin:
		var p:EditorPlugin = n as EditorPlugin
		var scr:Script = p.get_script()
		if is_instance_valid( scr ):
			var path:String = scr.resource_path
			if path.ends_with( "command_server.gd" ) \
			or path.contains( "enetheru.command-server/command_server.gd" ):
				return p
	for c:Node in n.get_children():
		var found:EditorPlugin = _find_cs_in_tree( c )
		if is_instance_valid( found ):
			return found
	return null

@tool
extends CommandServerCommand

# Privileged: confirm dialog then sequential TestBase runs via TestRunnerService.
# Do NOT await here — bare RefCounted coroutines are unreliable. Service is a
# Node and completes via begin_run → on_done.

const Common = preload( "_tests_common.gd" )


func get_name() -> String:
	return "TESTS_RUN"


func get_description() -> String:
	return "Confirm-and-run tests (all | group:Name | path | file) [verbose] [debug]."


func get_usage() -> String:
	return "TESTS_RUN <all|group:Name|res://path.gd|file.gd> [verbose] [debug]"


func execute( _args:String, _context:Dictionary ) -> String:
	return "ERROR: TESTS_RUN requires async begin_execute (internal)"


func begin_execute( args:String, context:Dictionary, on_done:Callable ) -> void:
	var req:Dictionary = Common.require_service()
	if req.has( &"error" ):
		on_done.call( str( req[&"error"] ) )
		return
	var svc:Node = req[&"service"]

	var parsed:Dictionary = Common.parse_flags( args )
	if parsed.has( &"error" ):
		on_done.call( str( parsed[&"error"] ) )
		return

	var positional:PackedStringArray = parsed.get( &"positional", PackedStringArray() )
	if positional.is_empty():
		on_done.call( "ERROR: Usage: " + get_usage() )
		return
	if positional.size() > 1:
		# Allow multi-token path? Prefer single target token.
		on_done.call(
				"ERROR: expected one target (all|group:…|path|file), got: %s"
				% " ".join( positional )
		)
		return

	var target:String = positional[0]
	var resolved:Dictionary = svc.call( &"resolve_targets", target )
	var err:String = str( resolved.get( &"error", "" ) )
	if not err.is_empty():
		on_done.call( "ERROR: " + err )
		return
	var paths:PackedStringArray = resolved.get( &"paths", PackedStringArray() )
	if paths.is_empty():
		on_done.call( "ERROR: no tests matched '%s'" % target )
		return

	var opts:Dictionary = {}
	if bool( parsed.get( &"verbose_set", false ) ):
		opts["verbose"] = bool( parsed.get( &"verbose", false ) )
	if bool( parsed.get( &"debug_set", false ) ):
		opts["debug"] = bool( parsed.get( &"debug", false ) )

	var use_v:bool = bool( opts.get( "verbose", svc.get( "verbose" ) ) )
	var use_d:bool = bool( opts.get( "debug", svc.get( "debug" ) ) )

	var plugin:EditorPlugin = null
	var server_v:Variant = context.get( &"server" )
	if server_v is EditorPlugin:
		plugin = server_v

	var label:String = "%s (%d test(s), verbose=%s debug=%s)" % [
			target,
			paths.size(),
			str( use_v ),
			str( use_d ),
	]
	_toast( "Command Server: TESTS_RUN awaiting approval", label )
	_show_confirm_dialog( plugin, svc, paths, opts, label, on_done )


func _show_confirm_dialog(
		plugin:EditorPlugin,
		svc:Node,
		paths:PackedStringArray,
		opts:Dictionary,
		label:String,
		on_done:Callable
) -> void:
	var host:Control = EditorInterface.get_base_control()
	if host == null:
		on_done.call( "ERROR: no editor base control" )
		return

	const WIN_SIZE:Vector2i = Vector2i( 560, 320 )
	const WIN_MIN:Vector2i = Vector2i( 400, 240 )

	var win:Window = Window.new()
	win.title = "Command Server: Run tests?"
	win.exclusive = true
	win.unresizable = false
	win.wrap_controls = false
	win.min_size = WIN_MIN
	win.size = WIN_SIZE
	win.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN

	var margin:MarginContainer = MarginContainer.new()
	margin.set_anchors_preset( Control.PRESET_FULL_RECT )
	margin.set_offsets_preset( Control.PRESET_FULL_RECT )
	margin.add_theme_constant_override( &"margin_left", 10 )
	margin.add_theme_constant_override( &"margin_right", 10 )
	margin.add_theme_constant_override( &"margin_top", 10 )
	margin.add_theme_constant_override( &"margin_bottom", 10 )

	var root:VBoxContainer = VBoxContainer.new()
	root.set_anchors_preset( Control.PRESET_FULL_RECT )
	root.set_offsets_preset( Control.PRESET_FULL_RECT )
	root.add_theme_constant_override( &"separation", 8 )

	var info:Label = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var preview:PackedStringArray = PackedStringArray()
	var max_show:int = mini( 12, paths.size() )
	for i:int in max_show:
		preview.append( "  • " + paths[i] )
	if paths.size() > max_show:
		preview.append( "  … +%d more" % ( paths.size() - max_show ) )
	info.text = (
			"A remote client requested TESTS_RUN.\n"
			+ "%s\n\n"
			+ "Scripts:\n%s\n\n"
			+ "Runs sequentially on the editor main thread (may crash)."
	) % [label, "\n".join( preview )]

	var buttons:HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.size_flags_vertical = Control.SIZE_SHRINK_END
	buttons.add_theme_constant_override( &"separation", 8 )
	var cancel_btn:Button = Button.new()
	cancel_btn.text = "Cancel"
	var run_btn:Button = Button.new()
	run_btn.text = "Run tests"
	buttons.add_child( cancel_btn )
	buttons.add_child( run_btn )

	root.add_child( info )
	root.add_child( buttons )
	margin.add_child( root )
	win.add_child( margin )

	var editor_win:Window = host.get_window()
	if editor_win != null:
		editor_win.add_child( win )
	else:
		host.add_child( win )

	if plugin != null and plugin.has_method( &"track_window" ):
		plugin.call( &"track_window", win )

	var finished:Array = [false]

	var finish := func( approved:bool ) -> void:
		if finished[0]:
			return
		finished[0] = true
		if plugin != null and plugin.has_method( &"untrack_window" ):
			plugin.call( &"untrack_window", win )
		if is_instance_valid( win ):
			win.hide()
			win.queue_free()
		if not approved:
			on_done.call( "ERROR: User cancelled TESTS_RUN" )
			return
		if not is_instance_valid( svc ):
			on_done.call( "ERROR: TestRunner service gone" )
			return
		svc.call(
				&"begin_run",
				paths,
				opts,
				func( results:Dictionary ) -> void:
					if not is_instance_valid( svc ):
						on_done.call( "ERROR: service lost after run" )
						return
					var reply:String = str(
							svc.call( &"format_results_reply", results, "TESTS_RUN complete" )
					)
					on_done.call( reply )
		)

	var _c1:int = run_btn.pressed.connect( func() -> void: finish.call( true ) )
	var _c2:int = cancel_btn.pressed.connect( func() -> void: finish.call( false ) )
	var _c3:int = win.close_requested.connect( func() -> void: finish.call( false ) )

	win.popup()
	run_btn.grab_focus()


func _toast( title:String, body:String ) -> void:
	if EditorInterface.has_method( &"get_editor_toaster" ):
		var toaster_v:Variant = EditorInterface.call( &"get_editor_toaster" )
		if toaster_v is Object:
			var t:Object = toaster_v
			if t.has_method( &"push_toast" ):
				t.call( &"push_toast", title + " — " + body, 0, body )
				return
	print( "Command Server: ", title, " — ", body )

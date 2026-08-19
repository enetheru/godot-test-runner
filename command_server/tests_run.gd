@tool
extends CommandServerTool

# Privileged: confirm dialog then TestBase runs via TestRunnerService.
# Default sequential; [code]parallel[/code] matches TestRunner UI (launch all,
# no await between suites). Do NOT await here — bare RefCounted coroutines are
# unreliable. Service is a Node and completes via begin_run → on_done.

const Common = preload( "_tests_common.gd" )


func get_command_name() -> String:
	return "TESTS_RUN"


func get_description() -> String:
	return "Confirm-and-run tests (all | group:Name | path | file) [verbose] [debug] [parallel]."


func get_usage() -> String:
	return "TESTS_RUN <all|group:Name|res://path.gd|file.gd> [verbose] [debug] [parallel]"


func is_privileged() -> bool:
	return true


func get_input_schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"target": {
				"type": "string",
				"description": "all | group:Name | res://path.gd | file.gd",
			},
			"verbose": {
				"type": "boolean",
				"description": "Verbose logging for this run.",
			},
			"debug": {
				"type": "boolean",
				"description": "Debug logging for this run.",
			},
			"parallel": {
				"type": "boolean",
				"description": "Launch every suite without awaiting the previous.",
			},
		},
		"required": ["target"],
		"additionalProperties": false,
	}


func arguments_from_line( line:String, _tail:String ) -> Dictionary:
	var parsed:Dictionary = Common.parse_flags( line )
	if parsed.has( &"error" ):
		return parsed
	var positional:PackedStringArray = parsed.get( &"positional", PackedStringArray() )
	if positional.is_empty():
		return { &"error": "ERROR: Usage: " + get_usage() }
	if positional.size() > 1:
		return {
			&"error": "ERROR: expected one target (all|group:…|path|file), got: %s"
					% " ".join( positional ),
		}
	var out:Dictionary = { &"target": positional[0] }
	if parsed.get( &"verbose_set", false ):
		out[&"verbose"] = parsed.get( &"verbose", false )
	if parsed.get( &"debug_set", false ):
		out[&"debug"] = parsed.get( &"debug", false )
	if parsed.get( &"parallel_set", false ):
		out[&"parallel"] = parsed.get( &"parallel", false )
	return out


func _execute_line( _args:String, _context:Dictionary ) -> String:
	return "ERROR: TESTS_RUN requires async begin_execute (internal)"


func begin_execute(
		arguments:Dictionary,
		context:Dictionary,
		on_done:Callable
) -> void:
	var parsed:Dictionary = arguments
	var extra:String = line_from_arguments( arguments ).strip_edges()
	if not extra.is_empty() or not (
			arguments.has( &"target" ) or arguments.has( "target" )
	):
		parsed = arguments_from_line( extra, "" )
	_begin_parsed(
			parsed,
			context,
			func( reply:String ) -> void:
				on_done.call( result_from_text( reply ) )
	)


func _begin( args:String, context:Dictionary, on_done:Callable ) -> void:
	var parsed:Dictionary = arguments_from_line( args, "" )
	if parsed.has( &"error" ):
		on_done.call( str( parsed[&"error"] ) )
		return
	_begin_parsed( parsed, context, on_done )


func _begin_parsed(
		parsed:Dictionary,
		context:Dictionary,
		on_done:Callable
) -> void:
	var parse_err:String = Common.dict_error( parsed )
	if not parse_err.is_empty():
		on_done.call( parse_err )
		return
	var req:Dictionary = Common.require_service()
	if req.has( &"error" ):
		on_done.call( str( req[&"error"] ) )
		return
	var svc:Node = req[&"service"]

	var target:String = Common.string_arg( parsed, &"target", "" )
	if target.is_empty():
		on_done.call( "ERROR: Usage: " + get_usage() )
		return
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
	if parsed.has( &"verbose" ) or parsed.has( "verbose" ):
		opts["verbose"] = Common.bool_arg( parsed, &"verbose", false )
	if parsed.has( &"debug" ) or parsed.has( "debug" ):
		opts["debug"] = Common.bool_arg( parsed, &"debug", false )
	if parsed.has( &"parallel" ) or parsed.has( "parallel" ):
		opts["parallel"] = Common.bool_arg( parsed, &"parallel", false )

	var use_v:bool = opts.get( "verbose", svc.get( "verbose" ) )
	var use_d:bool = opts.get( "debug", svc.get( "debug" ) )
	var use_p:bool = opts.get( "parallel", false )

	var plugin:EditorPlugin = null
	var server_v:Variant = context.get( &"server" )
	if server_v is EditorPlugin:
		plugin = server_v

	var label:String = "%s (%d test(s), verbose=%s debug=%s parallel=%s)" % [
			target,
			paths.size(),
			str( use_v ),
			str( use_d ),
			str( use_p ),
	]
	_toast( "Command Server: TESTS_RUN awaiting approval", label )
	_show_confirm_dialog( plugin, svc, paths, opts, label, on_done )


func _show_confirm_dialog(
			plugin:EditorPlugin,
			svc:Node,
			paths:PackedStringArray,
			opts:Dictionary,
			label:String,
			on_done:Callable ) -> void:
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
	info.clip_text = false
	info.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	var preview:Array = []
	var max_show:int = mini( 12, paths.size() )
	for i:int in max_show:
		preview.append( "  • " + paths[i] )
	if paths.size() > max_show:
		preview.append( "  … +%d more" % ( paths.size() - max_show ) )
	var mode_line:String = (
			"Runs in parallel on the editor main thread (same as TestRunner UI)."
			if opts.get( "parallel", false )
			else "Runs sequentially on the editor main thread (default)."
	)
	info.text = (
			"A remote client requested TESTS_RUN.\n"
			+ "%s\n\n"
			+ "Scripts:\n%s\n\n"
			+ "%s May crash the editor."
	) % [label, "\n".join( preview ), mode_line]

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
		# Snapshot the existing session_logger ring. Do NOT OS.add_logger —
		# a second Logger around @tool TestBase batches deadlocked / crashed.
		var bus:RefCounted = _event_bus( plugin )
		var since_seq:int = _bus_seq( bus )
		svc.call(
				&"begin_run",
				paths,
				opts,
				func( results:Dictionary ) -> void:
					# Off the TestBase / Logger stack. Reading the bus (or
					# stringifying) here deadlocks session_logger.emit vs since.
					_complete_run.call_deferred(
							svc, bus, since_seq, results, on_done )
		)

	var _c1:int = run_btn.pressed.connect( func() -> void: finish.call( true ) )
	var _c2:int = cancel_btn.pressed.connect( func() -> void: finish.call( false ) )
	var _c3:int = win.close_requested.connect( func() -> void: finish.call( false ) )

	win.popup()
	run_btn.grab_focus()


func _event_bus( plugin:EditorPlugin ) -> RefCounted:
	if plugin == null or not is_instance_valid( plugin ):
		return null
	var bus_v:Variant = plugin.get( "event_bus" )
	if bus_v is RefCounted:
		return bus_v
	return null


func _bus_seq( bus:RefCounted ) -> int:
	if bus == null or not bus.has_method( &"get_seq" ):
		return 0
	return int( bus.call( &"get_seq" ) )


func _complete_run(
		svc:Node,
		bus:RefCounted,
		since_seq:int,
		results:Dictionary,
		on_done:Callable
) -> void:
	var lines:PackedStringArray = _bus_log_lines( bus, since_seq )
	var reply:String = "ERROR: service lost after run"
	if is_instance_valid( svc ):
		reply = str(
				svc.call( &"format_results_reply", results, "TESTS_RUN complete" )
		)
	if on_done.is_valid():
		on_done.call( _reply_with_log( reply, lines ) )


func _bus_log_lines( bus:RefCounted, since_seq:int ) -> PackedStringArray:
	var out:PackedStringArray = PackedStringArray()
	if bus == null or not bus.has_method( &"since" ):
		return out
	const SCAN:int = 200
	const KEEP:int = 50
	var rows_v:Variant = bus.call( &"since", since_seq, SCAN )
	if not ( rows_v is Array ):
		return out
	for row_v:Variant in rows_v:
		if not ( row_v is Dictionary ):
			continue
		var row:Dictionary = row_v
		if str( row.get( &"type", "" ) ) != "log":
			continue
		var data_v:Variant = row.get( &"data", {} )
		if not ( data_v is Dictionary ):
			continue
		var data:Dictionary = data_v
		var lvl:String = str( data.get( "lvl", "print" ) )
		# Skip PRINT flood from ConsoleReporter. Keep engine failures.
		if lvl != "error" and lvl != "script" and lvl != "warning" \
				and lvl != "stderr":
			continue
		var msg:String = str( data.get( "msg", "" ) )
		var loc:String = str( data.get( "loc", "" ) )
		var line:String = "%s: %s" % [lvl.to_upper(), msg] if loc.is_empty() \
				else "%s: %s — %s" % [lvl.to_upper(), loc, msg]
		var _n:int = out.append( line )
		if out.size() >= KEEP:
			break
	return out


func _reply_with_log( reply:String, lines:PackedStringArray ) -> String:
	if lines.is_empty():
		return reply
	var log_block:String = "--- log ---\n" + "\n".join( lines )
	var nl:int = reply.find( "\n" )
	if nl < 0:
		return reply + "\n" + log_block
	return reply.substr( 0, nl ) + "\n" + log_block + reply.substr( nl )


func _toast( title:String, body:String ) -> void:
	if EditorInterface.has_method( &"get_editor_toaster" ):
		var toaster_v:Variant = EditorInterface.call( &"get_editor_toaster" )
		if toaster_v is Object:
			var t:Object = toaster_v
			if t.has_method( &"push_toast" ):
				t.call( &"push_toast", title + " — " + body, 0, body )
				return
	print( "Command Server: ", title, " — ", body )

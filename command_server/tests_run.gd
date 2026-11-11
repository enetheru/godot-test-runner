@tool
extends CommandServerTool

# Privileged: confirm dialog then TR_Base runs via TR_Service.
# Default sequential; [code]parallel[/code] matches TestRunner UI (launch all,
# no await between suites). Do NOT await here — bare RefCounted coroutines are
# unreliable. Service is a Node and completes via begin_run → on_done.

const Common = preload( "uid://byjo8kv2agqny" )
const Log = preload( "uid://br7jtx5cntuan" )
const TracyHooks = preload( "uid://c38qii7m273x0" )
const _ConfirmScene = preload( "../../enetheru.command-server/ui/confirm.tscn" )
const _ConfirmScript = preload( "../../enetheru.command-server/ui/confirm.gd" )


func get_command_name() -> String:
	return "TESTS_RUN"


func get_description() -> String:
	return "Confirm-and-run tests or case scripts (all | group:Name | path | file) [level=<notice|info|debug|trace>] [parallel] [tracy]."


func get_usage() -> String:
	return "TESTS_RUN <all|group:Name|res://path.gd|file.gd> [level=<notice|info|debug|trace>] [parallel] [tracy]"


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
			"level": {
				"type": "string",
				"description": "Inclusive log ceiling for this run: notice, info, debug, or trace.",
				"enum": ["notice", "info", "debug", "trace"],
			},
			"parallel": {
				"type": "boolean",
				"description": "Launch every suite without awaiting the previous.",
			},
			"tracy": {
				"type": "boolean",
				"description": "Install Tracy capture for this run. Omitted or false leaves capture off. Requires the Profiler singleton and configured capture paths.",
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
	if parsed.get( &"lvl_set", false ):
		out[&"level"] = parsed.get( &"lvl", -1 )
	if parsed.get( &"parallel_set", false ):
		out[&"parallel"] = parsed.get( &"parallel", false )
	if parsed.get( &"tracy_set", false ):
		out[&"tracy"] = parsed.get( &"tracy", false )
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
	var has_level:bool = parsed.has( &"level" ) or parsed.has( "level" )
	if has_level:
		var raw:Variant = parsed[&"level"] if parsed.has( &"level" ) \
				else parsed["level"]
		var level:int = Log.parse_level( raw )
		if level < 0:
			on_done.call(
					"ERROR: bad level '%s' (notice|info|debug|trace)" % str( raw )
			)
			return
		opts["lvl"] = level
	if parsed.has( &"parallel" ) or parsed.has( "parallel" ):
		opts["parallel"] = Common.bool_arg( parsed, &"parallel", false )
	var use_tracy:bool = false
	if parsed.has( &"tracy" ) or parsed.has( "tracy" ):
		use_tracy = Common.bool_arg( parsed, &"tracy", false )
		opts["tracy"] = use_tracy
	if use_tracy:
		var tracy_err:String = _tracy_ready_error()
		if not tracy_err.is_empty():
			on_done.call( tracy_err )
			return

	var use_lvl:int = Log.Level.DEFAULT
	var got_lvl:Variant = opts.get( "lvl", svc.get( "lvl" ) )
	if got_lvl is int:
		use_lvl = got_lvl
	var use_p:bool = opts.get( "parallel", false )

	var plugin:EditorPlugin = null
	var server_v:Variant = context.get( &"server" )
	if server_v is EditorPlugin:
		plugin = server_v

	var label:String = "%s (%d test(s), level=%s parallel=%s tracy=%s)" % [
			target,
			paths.size(),
			Log.level_name( use_lvl ),
			str( use_p ),
			str( use_tracy ),
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

	var dlg:Window = _ConfirmScene.instantiate() as Window
	if dlg == null:
		on_done.call( "ERROR: Failed to instantiate confirm dialog" )
		return

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
	var message:String = (
			"A remote client requested TESTS_RUN.\n"
			+ "%s\n\n"
			+ "Scripts:\n%s\n\n"
			+ "%s May crash the editor."
	) % [label, "\n".join( preview ), mode_line]

	dlg.call(
			&"configure",
			"Command Server: Run tests?",
			message,
			"Run tests",
			"",
			Vector2i( 520, 320 ) )

	var _c:int = dlg.connect(
			&"finished",
			func( approved:bool, response:String = "" ) -> void:
				if not approved:
					on_done.call( _ConfirmScript.with_response(
							"ERROR: User cancelled TESTS_RUN",
							response ) )
					return
				if not is_instance_valid( svc ):
					on_done.call( _ConfirmScript.with_response(
							"ERROR: TestRunner service gone",
							response ) )
					return
				# Snapshot the existing session_logger ring. Do NOT OS.add_logger —
				# a second Logger around @tool TR_Base batches deadlocked / crashed.
				var bus:RefCounted = _event_bus( plugin )
				var since_seq:int = _bus_seq( bus )
				svc.call(
						&"begin_run",
						paths,
						opts,
						func( results:Dictionary ) -> void:
							# Off the TR_Base / Logger stack. Reading the bus (or
							# stringifying) here deadlocks session_logger.emit vs since.
							_complete_run.call_deferred(
									svc,
									bus,
									since_seq,
									results,
									response,
									on_done )
				)
	)
	dlg.call( &"open", plugin, host )


func _tracy_ready_error() -> String:
	if not Engine.has_singleton( &"Profiler" ):
		return "ERROR: Tracy capture needs a Godot binary with the Profiler singleton"
	if not TracyHooks.is_configured():
		return "ERROR: Tracy capture is not configured (capture executable, Python, and crop scripts)"
	return ""


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
	var seq_v:Variant = bus.call( &"get_seq" )
	if seq_v is int:
		var n:int = seq_v
		return n
	return 0


func _complete_run(
		svc:Node,
		bus:RefCounted,
		since_seq:int,
		results:Dictionary,
		response:String,
		on_done:Callable
) -> void:
	var lines:PackedStringArray = _bus_log_lines( bus, since_seq )
	var reply:String = "ERROR: service lost after run"
	if is_instance_valid( svc ):
		reply = str(
				svc.call( &"format_results_reply", results, "TESTS_RUN complete" )
		)
	reply = _reply_with_log( reply, lines )
	reply = _ConfirmScript.with_response( reply, response )
	if on_done.is_valid():
		on_done.call( reply )


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

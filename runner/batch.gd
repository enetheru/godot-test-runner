@tool
extends Node

## Runs one batch for the test runner service.
## Sequential by default. Parallel launches every script without awaiting the previous.

const TR_Service = preload( "uid://dmaf85hvsuhon" )

const MAX_OUTPUT_LINES:int = 200
const _TRACY_HOOK:String = "res://addons/enetheru.test-runner/runner/hooks/TracyCapture.gd"


# ██████  ██████   ██████  ██████  ███████ ██████  ████████ ██ ███████ ███████ #
# ██   ██ ██   ██ ██    ██ ██   ██ ██      ██   ██    ██    ██ ██      ██      #
# ██████  ██████  ██    ██ ██████  █████   ██████     ██    ██ █████   ███████ #
# ██      ██   ██ ██    ██ ██      ██      ██   ██    ██    ██ ██           ██ #
# ██      ██   ██  ██████  ██      ███████ ██   ██    ██    ██ ███████ ███████ #
func                        ________PROPERTIES_______              ()->void:pass

## Owner. The service assigns this before [method start].
var service:TR_Service


#         ███    ███ ███████ ████████ ██   ██  ██████  ██████  ███████         #
#         ████  ████ ██         ██    ██   ██ ██    ██ ██   ██ ██              #
#         ██ ████ ██ █████      ██    ███████ ██    ██ ██   ██ ███████         #
#         ██  ██  ██ ██         ██    ██   ██ ██    ██ ██   ██      ██         #
#         ██      ██ ███████    ██    ██   ██  ██████  ██████  ███████         #
func                        _________METHODS_________              ()->void:pass

## [param service] is already marked running. Completes via [param on_done].
func start(
		paths:PackedStringArray,
		opts:Dictionary,
		on_done:Callable ) -> void:
	var use_lvl:int = service.lvl
	var got_lvl:Variant = opts.get( "lvl", service.lvl )
	if got_lvl is int:
		use_lvl = got_lvl
	var use_parallel:bool = opts.get( "parallel", false )
	var stamp:String = Time.get_datetime_string_from_system( false, true )
	stamp = stamp.replace( ":", "-" ).replace( " ", "_" )
	var run_id:String = "run_%s" % stamp

	var results:Dictionary = {
		"ok": true,
		"ran": 0,
		"passed": 0,
		"failed": 0,
		"lvl": use_lvl,
		"parallel": use_parallel,
		"run_id": run_id,
		"log_path": "",
		"tests": [],
	}

	var tracy_mode:int = -1
	if opts.has( "tracy" ):
		tracy_mode = 1 if opts.get( "tracy", false ) else 0
	results["tracy"] = tracy_mode == 1
	if use_parallel:
		_run_parallel( paths, use_lvl, tracy_mode, results, run_id, on_done )
	else:
		await _run_sequential( paths, use_lvl, tracy_mode, results, run_id )
		_finish( results, on_done )


#       ██ ███    ██ ████████ ███████ ██████  ███    ██  █████  ██             #
#       ██ ████   ██    ██    ██      ██   ██ ████   ██ ██   ██ ██             #
#       ██ ██ ██  ██    ██    █████   ██████  ██ ██  ██ ███████ ██             #
#       ██ ██  ██ ██    ██    ██      ██   ██ ██  ██ ██ ██   ██ ██             #
#       ██ ██   ████    ██    ███████ ██   ██ ██   ████ ██   ██ ███████        #
func                        ________INTERNAL_________              ()->void:pass

func _run_sequential(
			paths:PackedStringArray,
			use_lvl:int,
			tracy_mode:int,
			results:Dictionary,
			run_id:String ) -> void:
	var total:int = paths.size()
	var i:int = 0
	for path:String in paths:
		i += 1
		var entry:Dictionary = await _run_one( path, use_lvl, tracy_mode )
		var tests_arr:Array = results["tests"]
		tests_arr.append( entry )
		results["ran"] = results["ran"] + 1
		if entry.get( "retcode", TR_CaseSession.TEST_FAILED ) == TR_CaseSession.TEST_OK:
			results["passed"] = results["passed"] + 1
		else:
			results["failed"] = results["failed"] + 1
			results["ok"] = false
		service.report_progress( i, total, entry )
		# Persist after each test so a crash mid-batch keeps partial progress.
		service.store_results( results, run_id )


## Parallel batch: same launch model as TestRunner UI process_selection.
## Why flag exists: sequential-only could not prove suite isolation under real
## concurrent load (UI Run-all). Default remains sequential.
func _run_parallel(
			paths:PackedStringArray,
			use_lvl:int,
			tracy_mode:int,
			results:Dictionary,
			run_id:String,
			on_done:Callable ) -> void:
	var total:int = paths.size()
	# Array box so each worker mutates one shared remaining-count (int by value would not).
	var left:Array = [ total ]
	# Slots preserve discovery order in the reply even when finish order differs.
	var slots:Array = []
	assert( slots.resize( total ) )
	for i:int in total:
		slots[i] = null
	results["tests"] = slots

	if total == 0:
		_finish( results, on_done )
		return

	for i:int in total:
		# No await — fire concurrent coroutines like process_test(file_item).
		@warning_ignore("missing_await")
		_run_slot(
				paths[i],
				i,
				total,
				use_lvl,
				tracy_mode,
				results,
				run_id,
				left,
				on_done
		)


func _run_slot(
			path:String,
			index:int,
			total:int,
			use_lvl:int,
			tracy_mode:int,
			results:Dictionary,
			run_id:String,
			left:Array,
			on_done:Callable ) -> void:
	var entry:Dictionary = await _run_one( path, use_lvl, tracy_mode )
	var tests_arr:Array = results["tests"]
	tests_arr[index] = entry

	if entry.get( "retcode", TR_CaseSession.TEST_FAILED ) == TR_CaseSession.TEST_OK:
		results["passed"] = results["passed"] + 1
	else:
		results["failed"] = results["failed"] + 1
		results["ok"] = false
	results["ran"] = results["ran"] + 1

	var done_n:int = results["ran"]
	service.report_progress( done_n, total, entry )
	service.store_results( results, run_id )

	left[0] = left[0] - 1
	if left[0] <= 0:
		_finish( results, on_done )


func _finish( results:Dictionary, on_done:Callable ) -> void:
	service.last_results = results
	service.last_log_path = str( results.get( "log_path", "" ) )
	service.is_running = false
	service.report_finished( results )
	if on_done.is_valid():
		on_done.call( results )


## [param tracy_mode] [code]1[/code] forces the Tracy hook on. [code]0[/code] drops it from the options list.
func _apply_tracy_mode( target:Object, tracy_mode:int ) -> void:
	if target == null or tracy_mode < 0:
		return
	var prop:StringName = &"hook_paths" if tracy_mode == 1 else &"hook_skip"
	var raw:Variant = target.get( prop )
	var paths:PackedStringArray = raw if raw is PackedStringArray else PackedStringArray()
	if paths.has( _TRACY_HOOK ):
		return
	if paths.append( _TRACY_HOOK ):
		push_error( "batch: hook path append failed" )
		return
	target.set( prop, paths )


func _run_one( script_path:String, _use_lvl:int, tracy_mode:int = -1 ) -> Dictionary:
	var group_name:String = _group_for_path( script_path )
	var entry:Dictionary = {
		"path": script_path,
		"group": group_name,
		"retcode": TR_CaseSession.TEST_FAILED,
		"status": "FAILED",
		"output": [],
	}

	if not ResourceLoader.exists( script_path ) and not FileAccess.file_exists( script_path ):
		entry["output"] = ["Resource not found: %s" % script_path]
		return entry

	var script_res:Resource = ResourceLoader.load(
			script_path,
			"",
			ResourceLoader.CACHE_MODE_REPLACE
	)
	if script_res == null or not ( script_res is GDScript ):
		entry["output"] = ["Failed to load GDScript: %s" % script_path]
		return entry

	var script:GDScript = script_res
	if not script.can_instantiate():
		entry["output"] = ["Cannot instantiate: %s" % script_path]
		return entry

	if TR_CaseSession.is_case_script( script ):
		return await _run_case( script, entry, tracy_mode )

	entry["output"] = ["Not a case: %s" % script_path]
	return entry


## Editor host. [param tracy_mode] [code]1[/code] adds the Tracy hook, [code]0[/code] skips the options-list copy, and [code]-1[/code] leaves the list alone.
func _run_case( script:GDScript, entry:Dictionary, tracy_mode:int ) -> Dictionary:
	var session := TR_CaseSession.new()
	session.host = TR_CaseSession.Host.EDITOR
	_apply_tracy_mode( session, tracy_mode )
	var scene_tree:SceneTree = get_tree()
	if scene_tree == null:
		var loop:MainLoop = Engine.get_main_loop()
		if loop is SceneTree:
			scene_tree = loop
	if scene_tree == null:
		entry["output"] = ["No SceneTree for case: %s" % str( entry.get( "path", "" ) )]
		return entry
	session.attach_tree( scene_tree )
	var body:TR_Case = session.instantiate( script )
	if body == null:
		entry["output"] = ["Not a case: %s" % str( entry.get( "path", "" ) )]
		return entry
	await session.run_await( body )
	var code:int = session.runcode
	entry["retcode"] = code
	var label:String = "OK" if code == TR_CaseSession.TEST_OK else "FAILED"
	if session.status == "timeout":
		label = "TIMEOUT"
	entry["status"] = label
	var lines:Array = []
	for row:String in session.line().split( "\n" ):
		lines.append( row )
	entry["output"] = _cap_output( lines )
	return entry


func _cap_output( lines:Array ) -> Array:
	if lines.size() <= MAX_OUTPUT_LINES:
		return lines.duplicate()
	var skip:int = lines.size() - MAX_OUTPUT_LINES
	var capped:Array = ["… (%d earlier lines omitted)" % skip]
	for i:int in range( skip, lines.size() ):
		capped.append( lines[i] )
	return capped


func _group_for_path( script_path:String ) -> String:
	var best:String = ""
	var best_len:int = -1
	for g:Variant in service.groups:
		var gd:Dictionary = g
		var folder:String = str( gd.get( "folder", "" ) )
		if script_path.begins_with( folder + "/" ) \
		or script_path.begins_with( folder + "\\" ):
			if folder.length() > best_len:
				best = str( gd.get( "group", "" ) )
				best_len = folder.length()
	if not best.is_empty():
		return best
	var parent:String = script_path.get_base_dir().get_file()
	return parent.to_pascal_case()

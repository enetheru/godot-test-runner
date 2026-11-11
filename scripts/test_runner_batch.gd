@tool
extends Node

## Runs one batch for the test runner service.
## Sequential by default. Parallel launches every script without awaiting the previous.

const TR_Service = preload( "uid://dmaf85hvsuhon" )
const RetCode = TR_Base.RetCode

const MAX_OUTPUT_LINES:int = 200


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

	var use_tracy:bool = opts.get( "tracy", false )
	results["tracy"] = use_tracy
	if use_parallel:
		_run_parallel( paths, use_lvl, use_tracy, results, run_id, on_done )
	else:
		await _run_sequential( paths, use_lvl, use_tracy, results, run_id )
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
			use_tracy:bool,
			results:Dictionary,
			run_id:String ) -> void:
	var total:int = paths.size()
	var i:int = 0
	for path:String in paths:
		i += 1
		var entry:Dictionary = await _run_one( path, use_lvl, use_tracy )
		var tests_arr:Array = results["tests"]
		tests_arr.append( entry )
		results["ran"] = results["ran"] + 1
		if entry.get( "retcode", RetCode.TEST_FAILED ) == RetCode.TEST_OK:
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
			use_tracy:bool,
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
				use_tracy,
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
			use_tracy:bool,
			results:Dictionary,
			run_id:String,
			left:Array,
			on_done:Callable ) -> void:
	var entry:Dictionary = await _run_one( path, use_lvl, use_tracy )
	var tests_arr:Array = results["tests"]
	tests_arr[index] = entry

	if entry.get( "retcode", RetCode.TEST_FAILED ) == RetCode.TEST_OK:
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


func _run_one( script_path:String, use_lvl:int, use_tracy:bool = false ) -> Dictionary:
	var group_name:String = _group_for_path( script_path )
	var entry:Dictionary = {
		"path": script_path,
		"group": group_name,
		"retcode": RetCode.TEST_FAILED,
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
		return await _run_case( script, entry, use_tracy )

	var instance_v:Object = script.new()
	if instance_v == null:
		entry["output"] = ["script.new() returned null: %s" % script_path]
		return entry

	# Prefer TR_Base; accept duck-typed run_test + runcode/output.
	if not instance_v is TR_Base \
	and not instance_v.has_method( &"run_test" ):
		entry["output"] = ["Not a TR_Base (no run_test): %s" % script_path]
		if instance_v is Object and is_instance_valid( instance_v ):
			( instance_v as Object ).free()
		return entry

	var instance:Object = instance_v
	_try_set( instance, "local_lvl", use_lvl )
	# 0 skips capture even when the panel toggle is on. 1 installs it for this run.
	_try_set( instance, "capture_request", 1 if use_tracy else 0 )

	# Hold a hard ref for the await lifetime (same idea as TR_Base._cycleref).
	var _keep:Object = instance
	@warning_ignore( "redundant_await" )
	if instance.has_method( &"run_harness" ):
		await instance.call( &"run_harness" )
	elif instance.has_method( &"run_test" ):
		await instance.call( &"run_test" )
	else:
		entry["output"] = ["run_test missing after type check: %s" % script_path]
		return entry

	var retcode:int = instance.get( "runcode" )
	var out_v:Array = instance.get( "output" )
	var output:Array = out_v.duplicate()

	entry["retcode"] = retcode
	var status:String = "OK" if retcode == RetCode.TEST_OK else "FAILED"
	# TR_Base max_runtime leaves a distinctive log line when the timer wins.
	for line:Variant in output:
		if str( line ).contains( "Timeout was reached" ):
			status = "TIMEOUT"
			break
	if instance.get( "_timed_out" ) == true:
		status = "TIMEOUT"
	entry["status"] = status
	entry["output"] = _cap_output( output )

	_keep = null
	if is_instance_valid( instance ) and not ( instance is RefCounted ):
		instance.free()
	return entry


## Editor host. [param use_tracy] is the command override, same as TR_Base.
func _run_case( script:GDScript, entry:Dictionary, use_tracy:bool ) -> Dictionary:
	var session := TR_CaseSession.new()
	session.host = TR_CaseSession.Host.EDITOR
	session.capture_request = 1 if use_tracy else 0
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
	var label:String = "OK" if code == RetCode.TEST_OK else "FAILED"
	if session.status == "timeout":
		label = "TIMEOUT"
	entry["status"] = label
	var lines:Array = []
	for row:String in session.line().split( "\n" ):
		lines.append( row )
	entry["output"] = _cap_output( lines )
	return entry


func _try_set( obj:Object, prop:String, value:Variant ) -> void:
	if obj == null:
		return
	for p:Dictionary in obj.get_property_list():
		if str( p.get( "name", "" ) ) == prop:
			obj.set( prop, value )
			return


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

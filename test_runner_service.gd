@tool
extends Node

## Headless façade for TestRunner discovery and TestBase batch runs.
## Owned by the TestRunner EditorPlugin. Safe for Command Server callers.
## UI (main_panel) remains the Tree view; this object owns agent-facing state.
## Default batch is sequential; [code]opts.parallel[/code] matches the UI
## (launch every suite without awaiting the previous).

const Shared = preload( "scripts/shared.gd" )
const RetCode = Shared.RetCode

const LAST_JSON_PATH:String = "user://test_runner_last.json"
const RESULTS_DIR:String = "user://test_runner_results"
const MAX_OUTPUT_LINES:int = 200
const DEFAULT_TEST_PATH:String = "res://tests"


# ██████  ██████   ██████  ██████  ███████ ██████  ████████ ██ ███████ ███████ #
# ██   ██ ██   ██ ██    ██ ██   ██ ██      ██   ██    ██    ██ ██      ██      #
# ██████  ██████  ██    ██ ██████  █████   ██████     ██    ██ █████   ███████ #
# ██      ██   ██ ██    ██ ██      ██      ██   ██    ██    ██ ██           ██ #
# ██      ██   ██  ██████  ██      ███████ ██   ██    ██    ██ ███████ ███████ #
func                        ________PROPERTIES_______              ()->void:pass

var test_path:String = DEFAULT_TEST_PATH
## Cached groups: { group, folder, scripts:[{file,path}] }
var groups:Array = []
var verbose:bool = false
var debug:bool = false
var last_results:Dictionary = {}
var last_log_path:String = ""
var is_running:bool = false

var _script_filter:Callable = default_script_filter
var _folder_filter:Callable = default_folder_filter


#            ███████ ██  ██████  ███    ██  █████  ██      ███████             #
#            ██      ██ ██       ████   ██ ██   ██ ██      ██                  #
#            ███████ ██ ██   ███ ██ ██  ██ ███████ ██      ███████             #
#                 ██ ██ ██    ██ ██  ██ ██ ██   ██ ██           ██             #
#            ███████ ██  ██████  ██   ████ ██   ██ ███████ ███████             #
func                        _________SIGNALS_________              ()->void:pass

signal flags_changed
signal tests_reloaded
signal results_cleared
signal batch_progress( current:int, total:int, entry:Dictionary )
signal batch_finished( results:Dictionary )


#         ███    ███ ███████ ████████ ██   ██  ██████  ██████  ███████         #
#         ████  ████ ██         ██    ██   ██ ██    ██ ██   ██ ██              #
#         ██ ████ ██ █████      ██    ███████ ██    ██ ██   ██ ███████         #
#         ██  ██  ██ ██         ██    ██   ██ ██    ██ ██   ██      ██         #
#         ██      ██ ███████    ██    ██   ██  ██████  ██████  ███████         #
func                        _________METHODS_________              ()->void:pass

func default_script_filter( filename:String ) -> bool:
	return filename.begins_with( "test" ) \
		and filename.ends_with( ".gd" ) \
		and not filename.ends_with( "_generated.gd" )


func default_folder_filter( folder_path:String ) -> bool:
	var files:PackedStringArray = DirAccess.get_files_at( folder_path )
	for f:String in files:
		if _script_filter.call( f ):
			return true
	return false


func set_verbose( v:bool ) -> void:
	if verbose == v:
		return
	verbose = v
	flags_changed.emit()


func set_debug( d:bool ) -> void:
	if debug == d:
		return
	debug = d
	flags_changed.emit()


func set_flags( v:bool, d:bool ) -> void:
	var changed:bool = ( verbose != v ) or ( debug != d )
	verbose = v
	debug = d
	if changed:
		flags_changed.emit()


## Rescan [member test_path] and refresh [member groups].
func reload() -> void:
	groups = collect_groups( test_path )
	tests_reloaded.emit()


## Clear last batch results (in-memory). Does not delete log files.
func clear_results() -> void:
	last_results = {}
	last_log_path = ""
	results_cleared.emit()


func list_tests() -> Array:
	if groups.is_empty():
		reload()
	return groups.duplicate( true )


## Collect group dictionaries without touching Tree/UI.
func collect_groups( path:String = "" ) -> Array:
	var root:String = path if not path.is_empty() else test_path
	var out:Array = []
	if not DirAccess.dir_exists_absolute( ProjectSettings.globalize_path( root ) ) \
	and not DirAccess.dir_exists_absolute( root ):
		# DirAccess.get_directories_at works with res:// even when globalize fails.
		pass

	var folders:PackedStringArray = DirAccess.get_directories_at( root )
	var folder_paths:Array = []
	for folder:String in folders:
		folder_paths.append( root.path_join( folder ) )
	folder_paths.sort()

	for folder_path:String in folder_paths:
		if not _folder_filter.call( folder_path ):
			continue
		var files:PackedStringArray = DirAccess.get_files_at( folder_path )
		var scripts:Array = []
		for f:String in files:
			if not _script_filter.call( f ):
				continue
			scripts.append( {
				"file": f,
				"path": folder_path.path_join( f ),
			} )
		if scripts.is_empty():
			continue
		var folder_name:String = folder_path.get_file()
		out.append( {
			"group": folder_name.to_pascal_case(),
			"folder": folder_path,
			"scripts": scripts,
		} )
	return out


## Resolve a run target into script paths.
## [param spec]: `all`, `group:Name`, `res://…/test_x.gd`, or basename.
## Returns { &"paths": PackedStringArray, &"error": String } (error empty on ok).
func resolve_targets( spec:String ) -> Dictionary:
	if groups.is_empty():
		reload()
	var token:String = spec.strip_edges()
	if token.is_empty():
		return { &"paths": PackedStringArray(), &"error": "empty target" }

	if token.to_lower() == "all":
		var all_paths:Array = []
		for g:Variant in groups:
			var gd:Dictionary = g
			for s:Variant in gd.get( "scripts", [] ):
				var sd:Dictionary = s
				all_paths.append( str( sd.get( "path", "" ) ) )
		return { &"paths": all_paths, &"error": "" }

	if token.to_lower().begins_with( "group:" ):
		var gname:String = token.substr( 6 ).strip_edges()
		if gname.is_empty():
			return { &"paths": PackedStringArray(), &"error": "group: requires a name" }
		var matched:Array = []
		for g:Variant in groups:
			var gd:Dictionary = g
			var gn:String = str( gd.get( "group", "" ) )
			if gn.to_lower() == gname.to_lower() \
			or str( gd.get( "folder", "" ) ).get_file().to_lower() == gname.to_lower():
				for s:Variant in gd.get( "scripts", [] ):
					var sd:Dictionary = s
					matched.append( str( sd.get( "path", "" ) ) )
		if matched.is_empty():
			return {
				&"paths": PackedStringArray(),
				&"error": "unknown group '%s'" % gname,
			}
		return { &"paths": matched, &"error": "" }

	# Full path
	if token.begins_with( "res://" ) or token.begins_with( "user://" ):
		if not ResourceLoader.exists( token ) and not FileAccess.file_exists( token ):
			return {
				&"paths": PackedStringArray(),
				&"error": "script not found: %s" % token,
			}
		return { &"paths": PackedStringArray( [token] ), &"error": "" }

	# Basename or partial
	var basename:String = token
	if not basename.ends_with( ".gd" ):
		basename = basename + ".gd"
	var hits:Array = []
	for g:Variant in groups:
		var gd:Dictionary = g
		for s:Variant in gd.get( "scripts", [] ):
			var sd:Dictionary = s
			var f:String = str( sd.get( "file", "" ) )
			var p:String = str( sd.get( "path", "" ) )
			if f == basename or f == token or p.ends_with( "/" + basename ):
				hits.append( p )
	if hits.is_empty():
		return {
			&"paths": PackedStringArray(),
			&"error": "no test matching '%s'" % token,
		}
	if hits.size() > 1:
		return {
			&"paths": PackedStringArray(),
			&"error": "ambiguous test name '%s' (%d matches)" % [token, hits.size()],
		}
	return { &"paths": hits, &"error": "" }


func get_last_results() -> Dictionary:
	if not last_results.is_empty():
		return last_results.duplicate( true )
	return _load_last_json()


## Start a batch. Completes via [param on_done](results:Dictionary).
## [param opts.parallel]: if true, launch all suites like the TestRunner UI
## (no await between starts); otherwise sequential.
## Never use bare await from CommandServerCommand — call this instead.
func begin_run(
		paths:PackedStringArray,
		opts:Dictionary,
		on_done:Callable
) -> void:
	if is_running:
		if on_done.is_valid():
			on_done.call( {
				"ok": false,
				"error": "TESTS_RUN busy (another batch in progress)",
				"ran": 0,
				"passed": 0,
				"failed": 0,
				"tests": [],
			} )
		return
	if paths.is_empty():
		if on_done.is_valid():
			on_done.call( {
				"ok": false,
				"error": "no tests to run",
				"ran": 0,
				"passed": 0,
				"failed": 0,
				"tests": [],
			} )
		return
	is_running = true
	# Deferred so this Node owns the async stack (caller is sync begin_execute).
	_run_batch.call_deferred( paths, opts, on_done )


func _run_batch(
			paths:PackedStringArray,
			opts:Dictionary,
			on_done:Callable ) -> void:
	var use_verbose:bool = opts.get( "verbose", verbose )
	var use_debug:bool = opts.get( "debug", debug )
	var use_parallel:bool = opts.get( "parallel", false )
	var stamp:String = Time.get_datetime_string_from_system( false, true )
	stamp = stamp.replace( ":", "-" ).replace( " ", "_" )
	var run_id:String = "run_%s" % stamp

	var results:Dictionary = {
		"ok": true,
		"ran": 0,
		"passed": 0,
		"failed": 0,
		"verbose": use_verbose,
		"debug": use_debug,
		"parallel": use_parallel,
		"run_id": run_id,
		"log_path": "",
		"tests": [],
	}

	if use_parallel:
		_run_batch_parallel( paths, use_verbose, use_debug, results, run_id, on_done )
	else:
		await _run_batch_sequential( paths, use_verbose, use_debug, results, run_id )
		_finish_batch( results, on_done )


func _run_batch_sequential(
			paths:PackedStringArray,
			use_verbose:bool,
			use_debug:bool,
			results:Dictionary,
			run_id:String ) -> void:
	var total:int = paths.size()
	var i:int = 0
	for path:String in paths:
		i += 1
		var entry:Dictionary = await _run_one( path, use_verbose, use_debug )
		var tests_arr:Array = results["tests"]
		tests_arr.append( entry )
		results["ran"] = results["ran"] + 1
		if entry.get( "retcode", RetCode.TEST_FAILED ) == RetCode.TEST_OK:
			results["passed"] = results["passed"] + 1
		else:
			results["failed"] = results["failed"] + 1
			results["ok"] = false
		batch_progress.emit( i, total, entry )
		# Persist after each test so a crash mid-batch keeps partial progress.
		_write_results_files( results, run_id )


## Parallel batch: same launch model as TestRunner UI process_selection.
## Why flag exists: sequential-only could not prove suite isolation under real
## concurrent load (UI Run-all). Default remains sequential.
func _run_batch_parallel(
			paths:PackedStringArray,
			use_verbose:bool,
			use_debug:bool,
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
		_finish_batch( results, on_done )
		return

	for i:int in total:
		# No await — fire concurrent coroutines like process_test(file_item).
		_run_one_parallel_slot(
				paths[i],
				i,
				total,
				use_verbose,
				use_debug,
				results,
				run_id,
				left,
				on_done
		)


func _run_one_parallel_slot(
			path:String,
			index:int,
			total:int,
			use_verbose:bool,
			use_debug:bool,
			results:Dictionary,
			run_id:String,
			left:Array,
			on_done:Callable ) -> void:
	var entry:Dictionary = await _run_one( path, use_verbose, use_debug )
	var tests_arr:Array = results["tests"]
	tests_arr[index] = entry

	if entry.get( "retcode", RetCode.TEST_FAILED ) == RetCode.TEST_OK:
		results["passed"] = results["passed"] + 1
	else:
		results["failed"] = results["failed"] + 1
		results["ok"] = false
	results["ran"] = results["ran"] + 1

	var done_n:int = results["ran"]
	batch_progress.emit( done_n, total, entry )
	_write_results_files( results, run_id )

	left[0] = left[0] - 1
	if left[0] <= 0:
		_finish_batch( results, on_done )


func _finish_batch( results:Dictionary, on_done:Callable ) -> void:
	last_results = results
	last_log_path = str( results.get( "log_path", "" ) )
	is_running = false
	batch_finished.emit( results )
	if on_done.is_valid():
		on_done.call( results )


func _run_one( script_path:String, use_verbose:bool, use_debug:bool ) -> Dictionary:
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

	var instance_v:Object = script.new()
	if instance_v == null:
		entry["output"] = ["script.new() returned null: %s" % script_path]
		return entry

	# Prefer TestBase; accept duck-typed run_test + runcode/output.
	if not instance_v is TestBase \
	and not instance_v.has_method( &"run_test" ):
		entry["output"] = ["Not a TestBase (no run_test): %s" % script_path]
		if instance_v is Object and is_instance_valid( instance_v ):
			( instance_v as Object ).free()
		return entry

	var instance:Object = instance_v
	_try_set( instance, "_verbose", use_verbose )
	_try_set( instance, "_debug", use_debug )

	# Hold a hard ref for the await lifetime (same idea as TestBase.cycleref).
	var _keep:Object = instance
	@warning_ignore( "redundant_await" )
	if instance.has_method( &"run_test" ):
		await instance.call( &"run_test" )
	else:
		entry["output"] = ["run_test missing after type check: %s" % script_path]
		return entry

	var retcode:int = instance.get( "runcode" )
	var out_v:Array = instance.get( "output" )
	var output:Array = out_v.duplicate()

	entry["retcode"] = retcode
	var status:String = "OK" if retcode == RetCode.TEST_OK else "FAILED"
	# TestBase max_runtime leaves a distinctive log line when the timer wins.
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
	var start:int = lines.size() - MAX_OUTPUT_LINES
	var capped:Array = ["… (%d earlier lines omitted)" % start]
	for i:int in range( start, lines.size() ):
		capped.append( lines[i] )
	return capped


func _group_for_path( script_path:String ) -> String:
	for g:Variant in groups:
		var gd:Dictionary = g
		var folder:String = str( gd.get( "folder", "" ) )
		if script_path.begins_with( folder + "/" ) or script_path.begins_with( folder + "\\" ):
			return str( gd.get( "group", "" ) )
	var parent:String = script_path.get_base_dir().get_file()
	return parent.to_pascal_case()


func _write_results_files( results:Dictionary, run_id:String ) -> void:
	var abs_dir:String = ProjectSettings.globalize_path( RESULTS_DIR )
	var mk:Error = DirAccess.make_dir_recursive_absolute( abs_dir )
	if mk != OK and not DirAccess.dir_exists_absolute( abs_dir ):
		push_warning( "TestRunnerService: cannot create %s" % RESULTS_DIR )

	var json_path:String = RESULTS_DIR.path_join( "%s.json" % run_id )
	var text_path:String = RESULTS_DIR.path_join( "%s.log" % run_id )
	results["log_path"] = json_path

	var json_text:String = JSON.stringify( results, "\t" )
	_write_text( json_path, json_text )
	_write_text( LAST_JSON_PATH, json_text )
	_write_text( text_path, _format_log( results ) )


func _format_log( results:Dictionary ) -> String:
	var lines:Array = []
	lines.append( "run_id=%s ok=%s ran=%s passed=%s failed=%s verbose=%s debug=%s parallel=%s" % [
			str( results.get( "run_id", "" ) ),
			str( results.get( "ok", false ) ),
			str( results.get( "ran", 0 ) ),
			str( results.get( "passed", 0 ) ),
			str( results.get( "failed", 0 ) ),
			str( results.get( "verbose", false ) ),
			str( results.get( "debug", false ) ),
			str( results.get( "parallel", false ) ),
	] )
	for t:Variant in results.get( "tests", [] ):
		var td:Dictionary = t
		lines.append( "" )
		lines.append( "=== %s [%s] retcode=%s ===" % [
				str( td.get( "path", "" ) ),
				str( td.get( "status", "" ) ),
				str( td.get( "retcode", "" ) ),
		] )
		for line:Variant in td.get( "output", [] ):
			lines.append( str( line ) )
	return "\n".join( lines )


func _write_text( path:String, text:String ) -> void:
	var f:FileAccess = FileAccess.open( path, FileAccess.WRITE )
	if f == null:
		push_warning(
				"TestRunnerService: failed to write %s: %s"
				% [path, error_string( FileAccess.get_open_error() )]
		)
		return
	var _ok:bool = f.store_string( text )
	f.close()


func _load_last_json() -> Dictionary:
	if not FileAccess.file_exists( LAST_JSON_PATH ):
		return {}
	var raw:String = FileAccess.get_file_as_string( LAST_JSON_PATH )
	if raw.is_empty():
		return {}
	var parsed:Variant = JSON.parse_string( raw )
	if parsed is Dictionary:
		return parsed
	return {}


## Format list_tests for human TCP reply (non-JSON).
func format_list_text() -> String:
	var list:Array = list_tests()
	if list.is_empty():
		return "OK: no test groups under %s" % test_path
	var lines:Array = []
	lines.append( "OK: tests under %s" % test_path )
	for g:Variant in list:
		var gd:Dictionary = g
		var scripts:Array = gd.get( "scripts", [] )
		lines.append( "  [%s] %s (%d)" % [
				str( gd.get( "group", "" ) ),
				str( gd.get( "folder", "" ) ),
				scripts.size(),
		] )
		for s:Variant in scripts:
			var sd:Dictionary = s
			lines.append( "    - %s" % str( sd.get( "file", "" ) ) )
	return "\n".join( lines )


## Serialize results for TCP: OK line + JSON body.
func format_results_reply( results:Dictionary, heading:String = "TESTS_RUN complete" ) -> String:
	if results.has( "error" ) and str( results.get( "error", "" ) ) != "":
		var err:String = str( results["error"] )
		var tests:Array = results.get( "tests" )
		if tests.is_empty():
			return "ERROR: %s" % err
	var ok_flag:bool = results.get( "ok", false )
	var prefix:String = "OK" if ok_flag else "OK"
	# Always OK: prefix for parseable multi-line; body carries ok:false.
	# Agent exit codes: godot-cmd treats OK: as success of the *command*, not tests.
	var summary:String = "%s: %s ran=%s passed=%s failed=%s log=%s" % [
			prefix,
			heading,
			str( results.get( "ran", 0 ) ),
			str( results.get( "passed", 0 ) ),
			str( results.get( "failed", 0 ) ),
			str( results.get( "log_path", last_log_path ) ),
	]
	var body:String = JSON.stringify( results )
	return summary + "\n" + body

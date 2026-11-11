@tool
class_name TestRunnerService
extends Node

## Headless façade for TestRunner discovery and batch runs.
## Owned by the TestRunner EditorPlugin. Safe for Command Server callers.
## A [Case] script runs through [CaseSession] in this editor. The batch
## runner owns each script.
## UI (main_panel) remains the Tree view; this object owns agent-facing state.
## Default batch is sequential; [code]opts.parallel[/code] matches the UI
## (launch every suite without awaiting the previous).

const Shared = preload( "uid://ccrhkvl5ptefw" )
const Log = preload( "uid://br7jtx5cntuan" )
const BatchScript = preload( "uid://bsx0nrerfipri" )

const LAST_JSON_PATH:String = "user://test_runner_last.json"
const RESULTS_DIR:String = "user://test_runner_results"
const DEFAULT_TEST_PATH:String = TestRunnerOpts.DEFAULT_TESTS_DIR
const DEFAULT_CASE_PATH:String = TestRunnerOpts.DEFAULT_CASES_DIR


# ██████  ██████   ██████  ██████  ███████ ██████  ████████ ██ ███████ ███████ #
# ██   ██ ██   ██ ██    ██ ██   ██ ██      ██   ██    ██    ██ ██      ██      #
# ██████  ██████  ██    ██ ██████  █████   ██████     ██    ██ █████   ███████ #
# ██      ██   ██ ██    ██ ██      ██      ██   ██    ██    ██ ██           ██ #
# ██      ██   ██  ██████  ██      ███████ ██   ██    ██    ██ ███████ ███████ #
func                        ________PROPERTIES_______              ()->void:pass

var test_path:String = DEFAULT_TEST_PATH
var case_path:String = DEFAULT_CASE_PATH
## Junction / symlink cycle guard — not a group-name depth limit.
var max_scan_depth:int = Shared.DEFAULT_MAX_SCAN_DEPTH
## Cached groups: { group, folder, scripts:[{file,path}] }
var groups:Array = []
## Inclusive [constant Log.Level] copied onto each instance as [code]local_lvl[/code].
var lvl:int = Log.Level.DEFAULT
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

func default_folder_filter( _folder_path:String ) -> bool:
	# Do not require scripts in this folder — children may hold them.
	return true

## Inclusive ceiling for the next run. Notice is quiet.
func set_lvl( level:int ) -> void:
	if lvl == level:
		return
	lvl = level
	flags_changed.emit()

## Rescan [member test_path] and [member case_path], then refresh [member groups].
func reload() -> void:
	test_path = TestRunnerOpts.tests_root()
	case_path = TestRunnerOpts.cases_root()
	groups = collect_groups( test_path )
	groups.append_array( _case_groups() )
	tests_reloaded.emit()

## Clear last batch results (in-memory). Does not delete log files.
func clear_results() -> void:
	last_results = {}
	last_log_path = ""
	results_cleared.emit()

func list_tests() -> Array:
	_ensure_roots()
	return groups.duplicate( true )


## Collect group dictionaries without touching Tree/UI.
## Nested folders become [code]Group/Sub[/code] names. [code]group:Parent[/code]
## matches that node and every descendant.
func collect_groups( path:String = "" ) -> Array:
	var root:String = path if not path.is_empty() else test_path
	var tree:Array[Dictionary] = Shared.collect_test_tree(
			root, max_scan_depth, _script_filter, Callable(), _folder_filter )
	return _groups_from_tree( tree, "" )


## Resolve a run target into script paths.
## [param spec]: `all`, `group:Name`, `res://…/test_x.gd`, or basename.
## Returns { &"paths": PackedStringArray, &"error": String } (error empty on ok).
func resolve_targets( spec:String ) -> Dictionary:
	_ensure_roots()
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
			if not _group_spec_matches( gd, gname ):
				continue
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
	# Deferred so the runner owns the async stack (caller is sync begin_execute).
	_runner().call_deferred( &"start", paths, opts, on_done )


func report_progress( current:int, total:int, entry:Dictionary ) -> void:
	batch_progress.emit( current, total, entry )


func report_finished( results:Dictionary ) -> void:
	batch_finished.emit( results )


## Write the batch json and log. Called by the runner after each script.
func store_results( results:Dictionary, run_id:String ) -> void:
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


## Format list_tests for human TCP reply (non-JSON).
func format_list_text() -> String:
	var list:Array = list_tests()
	if list.is_empty():
		return "OK: no groups under %s or %s" % [test_path, _case_root()]
	var lines:Array = []
	lines.append( "OK: tests under %s, cases under %s" % [test_path, _case_root()] )
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

## One line per suite + recap. Used by TCP/MCP and log files.
func format_summary_table( results:Dictionary, bbcode:bool = true ) -> String:
	var tests_v:Array = results.get( "tests", [] )
	var passed:int = 0
	passed = results.get( "passed", 0 )
	var failed:int = 0
	failed = results.get( "failed", 0 )
	var lines:PackedStringArray = PackedStringArray()
	var _n:int = lines.append( "[b]Summary[/b]" if bbcode else "Summary" )
	for t:Variant in tests_v:
		if not ( t is Dictionary ):
			continue
		var td:Dictionary = t
		var status:String = str( td.get( "status", "" ) )
		var group:String = str( td.get( "group", "" ) )
		var path:String = str( td.get( "path", "" ) )
		var file:String = path.get_file()
		if file.is_empty():
			file = path
		if bbcode:
			var color:String = "yellowgreen" if status == "OK" else "tomato"
			_n = lines.append( "  [color=%s]%s[/color]  %s  [i]%s[/i]" % [
					color, status, group, file ] )
		else:
			_n = lines.append( "  %s  %s  %s" % [status, group, file] )
	var recap:String = "%d passed, %d failed" % [passed, failed]
	_n = lines.append( "" )
	if bbcode:
		var recap_color:String = "yellowgreen" if failed == 0 else "tomato"
		_n = lines.append( "[b][color=%s]%s[/color][/b]" % [recap_color, recap] )
	else:
		_n = lines.append( recap )
	if failed > 0:
		for t:Variant in tests_v:
			if not ( t is Dictionary ):
				continue
			var td:Dictionary = t
			if str( td.get( "status", "" ) ) == "OK":
				continue
			var path:String = str( td.get( "path", "" ) )
			if bbcode:
				_n = lines.append( "  [color=tomato]FAIL[/color]  %s" % path )
			else:
				_n = lines.append( "  FAIL  %s" % path )
	return "\n".join( lines )

## Serialize results for TCP/MCP: OK line + BBCode body.
## Multi-suite runs print a compact table first. Per-suite logs follow only
## for failures, or for every suite when info is open / a single test.
## Full JSON stays in [member last_log_path] — do not dump it here; `[` in
## JSON arrays is not BBCode and [method @GlobalScope.print_rich] would eat it.
func format_results_reply( results:Dictionary, heading:String = "TESTS_RUN complete" ) -> String:
	if results.has( "error" ) and str( results.get( "error", "" ) ) != "":
		var err:String = str( results["error"] )
		var tests:Array = results.get( "tests" )
		if tests.is_empty():
			return "ERROR: %s" % err
	# Always OK: prefix for parseable multi-line; body carries status in BBCode.
	# Agent exit codes: godot-cmd treats OK: as success of the *command*, not tests.
	var header:String = "OK: %s ran=%s passed=%s failed=%s log=%s" % [
			heading,
			str( results.get( "ran", 0 ) ),
			str( results.get( "passed", 0 ) ),
			str( results.get( "failed", 0 ) ),
			str( results.get( "log_path", last_log_path ) ),
	]
	var lines:PackedStringArray = PackedStringArray()
	var _n:int = lines.append( header )
	var tests_v:Array = results.get( "tests", [] )
	var use_lvl:int = _result_lvl( results )
	var dump_all:bool = Log.allows( use_lvl, Log.Level.INFO ) \
			or tests_v.size() <= 1
	if tests_v.size() > 1:
		_n = lines.append( "" )
		_n = lines.append( format_summary_table( results, true ) )
	var dumped:bool = false
	for t:Variant in tests_v:
		if not ( t is Dictionary ):
			continue
		var td:Dictionary = t
		var status:String = str( td.get( "status", "" ) )
		if not dump_all and status == "OK":
			continue
		dumped = true
		var color:String = "yellowgreen" if status == "OK" else "tomato"
		_n = lines.append( "" )
		_n = lines.append( "[b]%s[/b]  [color=%s]%s[/color]  [i]%s[/i]" % [
				str( td.get( "group", "" ) ),
				color,
				status,
				str( td.get( "path", "" ) ),
		] )
		for o:Variant in td.get( "output", [] ):
			_n = lines.append( "\t%s" % _color_output_line( str( o ) ) )
	if dumped and tests_v.size() > 1:
		var failed:int = 0
		failed = results.get( "failed", 0 )
		var passed:int = 0
		passed = results.get( "passed", 0 )
		var recap:String = "%d passed, %d failed" % [passed, failed]
		var recap_color:String = "yellowgreen" if failed == 0 else "tomato"
		_n = lines.append( "" )
		_n = lines.append( "[b][color=%s]%s[/color][/b]" % [recap_color, recap] )
	return "\n".join( lines )

#       ██ ███    ██ ████████ ███████ ██████  ███    ██  █████  ██             #
#       ██ ████   ██    ██    ██      ██   ██ ████   ██ ██   ██ ██             #
#       ██ ██ ██  ██    ██    █████   ██████  ██ ██  ██ ███████ ██             #
#       ██ ██  ██ ██    ██    ██      ██   ██ ██  ██ ██ ██   ██ ██             #
#       ██ ██   ████    ██    ███████ ██   ██ ██   ████ ██   ██ ███████        #
func                        ________INTERNAL_________              ()->void:pass

func _runner() -> Node:
	var found:Node = get_node_or_null( ^"Runner" )
	if found != null:
		return found
	var created:Node = BatchScript.new()
	created.name = "Runner"
	created.set( &"service", self )
	add_child( created )
	return created

## Rescan when the configured folders changed, or when nothing is cached yet.
func _ensure_roots() -> void:
	if groups.is_empty() \
	or test_path != TestRunnerOpts.tests_root() \
	or case_path != TestRunnerOpts.cases_root():
		reload()

## [member case_path] stays empty on a node that was born before the property.
func _case_root() -> String:
	var root_v:Variant = case_path
	if root_v is String:
		var text:String = root_v
		if not text.is_empty():
			return text
	case_path = TestRunnerOpts.cases_root()
	return case_path

func _groups_from_tree( nodes:Array, prefix:String ) -> Array:
	var out:Array = []
	for node_v:Variant in nodes:
		if not node_v is Dictionary:
			continue
		var node:Dictionary = node_v
		var leaf:String = str( node.get( "name", "" ) )
		var gname:String = leaf if prefix.is_empty() else prefix + "/" + leaf
		var scripts_raw:Array = node.get( "test_scripts", [] )
		if not scripts_raw.is_empty():
			var scripts:Array = []
			var folder_path:String = str( node.get( "folder_path", "" ) )
			for f:Variant in scripts_raw:
				scripts.append( {
					"file": str( f ),
					"path": folder_path.path_join( str( f ) ),
				} )
			out.append( {
				"group": gname,
				"folder": folder_path,
				"scripts": scripts,
			} )
		var kids:Array = node.get( "children", [] )
		if not kids.is_empty():
			out.append_array( _groups_from_tree( kids, gname ) )
	return out

## Case groups under [member case_path]. Names start with [code]Cases[/code].
func _case_groups() -> Array:
	var out:Array = []
	var root:String = _case_root()
	var root_files:Array[String] = CaseSession.case_files( root )
	if not root_files.is_empty():
		out.append( {
			"group": "Cases",
			"folder": root,
			"scripts": _script_rows( root, root_files ),
		} )
	var tree:Array[Dictionary] = Shared.collect_test_tree(
			root, max_scan_depth, _gd_file_filter, Callable(), _folder_filter )
	var nested:Array = _groups_from_tree( tree, "Cases" )
	for g:Variant in nested:
		if not ( g is Dictionary ):
			continue
		var gd:Dictionary = g
		var folder:String = str( gd.get( "folder", "" ) )
		var files:Array[String] = CaseSession.case_files( folder )
		if files.is_empty():
			continue
		gd["scripts"] = _script_rows( folder, files )
		out.append( gd )
	return out

func _script_rows( folder:String, files:Array ) -> Array:
	var scripts:Array = []
	for f:Variant in files:
		var file_name:String = str( f )
		scripts.append( {
			"file": file_name,
			"path": folder.path_join( file_name ),
		} )
	return scripts

func _gd_file_filter( filename:String ) -> bool:
	return filename.ends_with( ".gd" )

func _group_spec_matches( gd:Dictionary, spec:String ) -> bool:
	var want:String = spec.to_lower()
	var gn:String = str( gd.get( "group", "" ) ).to_lower()
	if gn == want \
	or gn.begins_with( want + "/" ):
		return true
	var folder:String = str( gd.get( "folder", "" ) )
	return folder.get_file().to_lower() == want \
	or folder.get_file().to_pascal_case().to_lower() == want

func _result_lvl( results:Dictionary ) -> int:
	var got:Variant = results.get( "lvl", Log.Level.DEFAULT )
	if got is int:
		return got
	return Log.Level.DEFAULT

func _format_log( results:Dictionary ) -> String:
	var lines:Array = []
	lines.append( "run_id=%s ok=%s ran=%s passed=%s failed=%s lvl=%s parallel=%s" % [
			str( results.get( "run_id", "" ) ),
			str( results.get( "ok", false ) ),
			str( results.get( "ran", 0 ) ),
			str( results.get( "passed", 0 ) ),
			str( results.get( "failed", 0 ) ),
			Log.level_name( _result_lvl( results ) ),
			str( results.get( "parallel", false ) ),
	] )
	var tests_v:Array = results.get( "tests", [] )
	if tests_v.size() > 1:
		lines.append( "" )
		lines.append( format_summary_table( results, false ) )
	for t:Variant in tests_v:
		if not ( t is Dictionary ):
			continue
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

## Color the logger's WARNING label. The stored line stays plain.
func _color_output_line( line:String ) -> String:
	if line.begins_with( "WARNING:" ):
		return "[color=gold]WARNING[/color]" + line.substr( 7 )
	return line

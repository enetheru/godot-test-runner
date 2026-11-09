@tool
extends VBoxContainer

# Test Runner
# TODO - make the script names clickable to load them up in the editor.



# Scripts
const InfoBox = preload('info_box.gd')
const Shared = preload('../scripts/shared.gd')
const OptsScript = preload( "../scripts/test_runner_opts.gd" )
const Log = preload('../logging.gd')
const CaseMenu = preload('../case/menu.gd')

# Classes
const TestDef = Shared.TestDef
const TestResult = Shared.TestResult
const RetCode = Shared.RetCode

# Scenes
const INFO_BOX = preload('info_box.tscn')
const HELP_PATH:String = "res://addons/enetheru.test-runner/ui/help.md"

# Resources
# Icons
const DEBUG_RERUN = preload('../res/debug-rerun.svg')
const FILE_CODE = preload('../res/file-code.svg')
const FOLDER_OPEN = preload('../res/folder-open.svg')

const MEDAL = preload('../res/medal.tres')
const SKULL = preload('../res/skull.svg')


# ██████  ██████   ██████  ██████  ███████ ██████  ████████ ██ ███████ ███████ #
# ██   ██ ██   ██ ██    ██ ██   ██ ██      ██   ██    ██    ██ ██      ██      #
# ██████  ██████  ██    ██ ██████  █████   ██████     ██    ██ █████   ███████ #
# ██      ██   ██ ██    ██ ██      ██      ██   ██    ██    ██ ██           ██ #
# ██      ██   ██  ██████  ██      ███████ ██   ██    ██    ██ ███████ ███████ #
func                        ________PROPERTIES_______              ()->void:pass

# Top Row Left
@onready var run_btn: Button = $Buttons/Left/Run
@onready var reload_btn: Button = $Buttons/Left/Reload

var _play_icon: Texture2D

# Top Row Center
@onready var stats_counter: RichTextLabel = $Buttons/Right/StatsCounter
# Top Row Right
@onready var clear_btn: Button = $Buttons/Right/ClearResults
@onready var help_btn: Button = $Buttons/Right/Help

# Help Popup
@onready var help_popup: PopupPanel = $PopupPanel
@onready var help_text: RichTextLabel = $PopupPanel/HelpText

# tree control
@onready var list_filter: LineEdit = $TestOutput/TestList/FilterRow/Filter
@onready var tests_tree: Tree = $TestOutput/TestList/TestsTree
@onready var info_list: VBoxContainer = $TestOutput/InfoList
@onready var info_scroller: ScrollContainer = $TestOutput/InfoList/ScrollContainer
@onready var info_items: VBoxContainer = $TestOutput/InfoList/ScrollContainer/InfoItems

# Runtime
var test_list:Array[TestDef]
var test_selection:Dictionary = {}



var test_lvl:int = Log.Level.DEFAULT

var test_tracy:bool = false

## ProjectSettings mirror. The plugin assigns this before the dock enters the tree.
var opts:OptsScript

## Optional headless service (Command Server). UI still owns Tree/InfoBoxes.
var _service:Node = null

## Same Run Case With menu as the FileSystem dock. Built on the first right-click.
var _run_menu: CaseMenu
var _case_popup: PopupMenu

## File rows captured when Run As opened. EditorScript walks this list.
var _pending_rows:Array[TreeItem] = []

## Dock walks inside process_selection. The menu counter can hit zero early.
var _walks: int = 0
## Cancel for a dock walk. The case menu keeps its own halt flag.
var _halt_walk: bool = false

# Configuration
var test_path:String = OptsScript.DEFAULT_TESTS_DIR
var case_path:String = OptsScript.DEFAULT_CASES_DIR

var test_script_filter:Callable = default_script_filter

var test_folder_filter:Callable = default_folder_filter

## Junction / symlink cycle guard — not a UI depth limit.
var max_scan_depth:int = Shared.DEFAULT_MAX_SCAN_DEPTH

var already_updating:bool = false

#             ███████ ██    ██ ███████ ███    ██ ████████ ███████              #
#             ██      ██    ██ ██      ████   ██    ██    ██                   #
#             █████   ██    ██ █████   ██ ██  ██    ██    ███████              #
#             ██       ██  ██  ██      ██  ██ ██    ██         ██              #
#             ███████   ████   ███████ ██   ████    ██    ███████              #
func                        __________EVENTS_________              ()->void:pass

func _on_run_pressed() -> void:
	if _walks > 0 or CaseMenu.set_count > 0:
		var stopping: bool = ( _walks > 0 and _halt_walk ) or CaseMenu.halt_set
		if stopping:
			return
		if _walks > 0:
			_halt_walk = true
		if CaseMenu.set_count > 0:
			CaseMenu.halt_set = true
		_apply_run_button()
		return

	# Outside the editor there is no Run As menu, so the rows run here.
	if not Engine.is_editor_hint():
		await process_selection()
		return

	var files := _selection_files()
	if files.is_empty():
		return
	_pending_rows = files
	var case_paths := _case_paths_of( files )
	# EditorScript runs the rows. Play and Headless still use the case paths.
	if not _show_run_menu( case_paths, _run_menu_origin(), true ):
		return


func _on_set_changed( _active: bool ) -> void:
	_apply_run_button()


func _apply_run_button() -> void:
	if not is_node_ready():
		return
	var active: bool = _walks > 0 or CaseMenu.set_count > 0
	var cancelling: bool = active and ( ( _walks > 0 and _halt_walk ) or CaseMenu.halt_set )
	if cancelling:
		run_btn.text = "Cancelling"
		run_btn.icon = null
		run_btn.disabled = true
		run_btn.tooltip_text = "The current script is still finishing."
		return
	if active:
		run_btn.text = "Cancel"
		run_btn.icon = null
		run_btn.disabled = false
		run_btn.tooltip_text = "After the current script finishes, leave the rest of the set unrun."
		return
	run_btn.text = "Play"
	run_btn.icon = _play_icon
	run_btn.disabled = false
	run_btn.tooltip_text = "Open the Run As menu for the rows on screen."


func _on_reload_pressed() -> void:
	if is_instance_valid( _service ) and _service.has_method( &"reload" ):
		_service.call( &"reload" )
	regenerate_tree()
	# TODO, reload tests should have some effect on the results list


func _on_filter_text_changed( new_text:String ) -> void:
	_apply_list_filter( new_text )


func _on_help_pressed() -> void:
	# Click-through made every press land on the editor, which hid the popup.
	help_popup.mouse_passthrough = false
	help_popup.wrap_controls = false
	help_text.text = _help_bbcode( _load_help() )
	var bounds:Vector2 = get_viewport_rect().size
	var width:int = maxi( mini( int( bounds.x * 0.62 ), 880 ), 520 )
	var height:int = maxi( mini( int( bounds.y * 0.72 ), 760 ), 420 )
	help_popup.size = Vector2i( width, height )
	help_popup.popup_centered()
	help_text.call_deferred( "scroll_to_line", 0 )
	help_text.call_deferred( "grab_focus" )


func _on_options_pressed() -> void:
	if not Engine.is_editor_hint():
		return

	var target:Resource = opts if opts != null else OptsScript.shared()
	EditorInterface.inspect_object( target )


func _on_opts_changed() -> void:
	var prev_tests:String = test_path
	var prev_cases:String = case_path
	_apply_opts()
	if not is_node_ready():
		return
	if prev_tests == test_path and prev_cases == case_path:
		return
	if is_instance_valid( _service ) and _service.has_method( &"reload" ):
		_service.call( &"reload" )
	regenerate_tree()


func _on_clear_results_pressed() -> void:
	clear_results_ui()


func _on_tests_tree_multi_selected(
			item: TreeItem,
			_column: int,
			selected: bool
			) -> void:
	if selected: test_selection[item] = true
	else:
		@warning_ignore('return_value_discarded')
		test_selection.erase(item)


func _on_tests_tree_button_clicked(
			item: TreeItem,
			_column: int,
			_id: int,
			_mouse_button_index: int
			) -> void:
	await process_test(item)


func _on_tests_tree_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton: return
	var mb_event:InputEventMouseButton = event
	if not mb_event.pressed: return
	var tree_item:TreeItem = tests_tree.get_item_at_position(mb_event.position)
	if not tree_item: return

	if mb_event.button_index == MOUSE_BUTTON_RIGHT:
		_popup_case_menu( tree_item, mb_event.global_position )
		tests_tree.accept_event()
		return
	if mb_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _is_file_item( tree_item ):
		return

	var metadata:Variant = tree_item.get_metadata(0)
	if not metadata: return
	var test_def:TestDef = metadata
	var test_file:String = tree_item.get_text(0)

	# FIXME it would be nice if I could get the file open in the text editor
	var file_path:String = "/".join([test_def.folder_path, test_file])
	if Engine.is_editor_hint():
		EditorInterface.get_file_system_dock().navigate_to_path(file_path)

	var item_results:TestResult = test_def.results.get(tree_item)
	if item_results and item_results.latest:
		item_results.latest.call_deferred( "grab_focus")


func _popup_case_menu( item:TreeItem, at:Vector2 ) -> void:
	if not Engine.is_editor_hint():
		return
	if not is_instance_valid( item ):
		return
	var files := _file_items_under( item )
	if files.is_empty():
		return
	_pending_rows = files
	# EditorScript runs these rows. Play and Headless still use the case paths.
	if not _show_run_menu( _case_paths_of( files ), at, true ):
		return


func _show_run_menu( paths:PackedStringArray, at:Vector2, run_rows:bool = false ) -> bool:
	if not Engine.is_editor_hint():
		return false
	if _run_menu == null:
		_run_menu = CaseMenu.new()
	_run_menu.editor_runner = _run_rows_as_editor if run_rows else Callable()
	if paths.is_empty() and not run_rows:
		return false
	var popup:PopupMenu = _run_menu.make_run_menu( paths, "Run As" )
	if popup == null:
		return false

	# A hide from the menu we are replacing must not free the one just opened.
	var previous:PopupMenu = _case_popup
	_case_popup = null
	if is_instance_valid( previous ):
		if previous.popup_hide.is_connected( _on_case_popup_hide ):
			previous.popup_hide.disconnect( _on_case_popup_hide )
		previous.queue_free()
	_case_popup = popup
	add_child( popup )
	popup.popup( Rect2i( Vector2i( at ), Vector2i.ZERO ) )
	var err:int = popup.popup_hide.connect( _on_case_popup_hide, CONNECT_ONE_SHOT as Object.ConnectFlags )
	if err != OK:
		push_error( "main_panel._show_run_menu: hide connect failed (%s)" % error_string( err ) )
	return true


func _run_menu_origin() -> Vector2:
	return run_btn.global_position + Vector2( 0, run_btn.size.y )


func _on_case_popup_hide() -> void:
	if is_instance_valid( _case_popup ):
		_case_popup.queue_free()
	_case_popup = null


func _row_path( item:TreeItem ) -> String:
	var meta:Variant = item.get_metadata( 0 )
	if not meta is TestDef:
		return ""
	var test_def:TestDef = meta
	if _is_file_item( item ):
		return test_def.folder_path.path_join( item.get_text( 0 ) )
	return test_def.folder_path


#      ██████  ██    ██ ███████ ██████  ██████  ██ ██████  ███████ ███████     #
#     ██    ██ ██    ██ ██      ██   ██ ██   ██ ██ ██   ██ ██      ██          #
#     ██    ██ ██    ██ █████   ██████  ██████  ██ ██   ██ █████   ███████     #
#     ██    ██  ██  ██  ██      ██   ██ ██   ██ ██ ██   ██ ██           ██     #
#      ██████    ████   ███████ ██   ██ ██   ██ ██ ██████  ███████ ███████     #
func                        ________OVERRIDES________              ()->void:pass

func _notification( what:int ) -> void:
	if what != NOTIFICATION_THEME_CHANGED or not is_node_ready():
		return
	_fit_result_column()
	_stripe_tree()


func _ready() -> void:
	if opts != null \
	and not opts.changed.is_connected( _on_opts_changed ):
		@warning_ignore( "return_value_discarded" )
		opts.changed.connect( _on_opts_changed )
	_apply_opts()
	_play_icon = run_btn.icon
	CaseMenu.set_changed = _on_set_changed
	_on_set_changed( CaseMenu.set_count > 0 )
	if not tests_tree.item_collapsed.is_connected( _on_tree_collapsed ):
		@warning_ignore( "return_value_discarded" )
		tests_tree.item_collapsed.connect( _on_tree_collapsed )
	_on_reload_pressed()


func _exit_tree() -> void:
	if opts != null \
	and opts.changed.is_connected( _on_opts_changed ):
		opts.changed.disconnect( _on_opts_changed )
	if CaseMenu.set_changed == _on_set_changed:
		CaseMenu.set_changed = Callable()
	if tests_tree != null and tests_tree.item_collapsed.is_connected( _on_tree_collapsed ):
		tests_tree.item_collapsed.disconnect( _on_tree_collapsed )


#         ███    ███ ███████ ████████ ██   ██  ██████  ██████  ███████         #
#         ████  ████ ██         ██    ██   ██ ██    ██ ██   ██ ██              #
#         ██ ████ ██ █████      ██    ███████ ██    ██ ██   ██ ███████         #
#         ██  ██  ██ ██         ██    ██   ██ ██    ██ ██   ██      ██         #
#         ██      ██ ███████    ██    ██   ██  ██████  ██████  ███████         #
func                        _________METHODS_________              ()->void:pass

func bind_service( svc:Node ) -> void:
	_service = svc
	_apply_opts()


## Log level from TESTS_SET. Writes [member opts] and ProjectSettings.
func set_lvl( level:int ) -> void:
	_store_flag( &"lvl", level )


func default_script_filter( filename:String ) -> bool:
	return filename.begins_with("test") \
		and filename.ends_with(".gd") \
		and not filename.ends_with("_generated.gd")


func default_folder_filter( folder_path:String ) -> bool:
	var files:Array = DirAccess.get_files_at( folder_path )
	return not files.filter( test_script_filter ).is_empty()


func collect_tests( _path:String ) -> Array[TestDef]:
	var tree:Array[Dictionary] = Shared.collect_test_tree(
			_path, max_scan_depth, test_script_filter )
	var tests:Array[TestDef] = []
	for node:Dictionary in tree:
		tests.append( _test_def_from_node( node ) )
	var cases_branch:TestDef = _cases_branch()
	if cases_branch != null:
		tests.append( cases_branch )
	return tests



func update_stats() -> void:
	if already_updating: return
	already_updating = true
	stats_counter.clear()
	var groups:int = 0
	var results:int = 0
	var failures:int = 0
	var successes:int = 0
	var stack:Array = test_list.duplicate()
	while not stack.is_empty():
		var test_def:TestDef = stack.pop_back()
		groups += 1
		for result:TestResult in test_def.results.values():
			results += 1
			if result.retcode == RetCode.TEST_OK: successes += 1
			if result.retcode == RetCode.TEST_FAILED: failures += 1
		for child_v:Variant in test_def.children:
			if child_v is TestDef:
				var child_def:TestDef = child_v
				stack.append( child_def )

	var plain := stats_counter.get_theme_color( &"plain" )
	var bad := stats_counter.get_theme_color( &"failure" )
	var good := stats_counter.get_theme_color( &"pass" )
	_add_count( groups, "folder", "folders", plain, false )
	_add_count( results, "result", "results", plain, true )
	_add_count( failures, "failure", "failures", bad, true )
	_add_count( successes, "pass", "passes", good, true )
	already_updating = false


## One count, in [param tint]. A separator stays in the label's own font color.
func _add_count( count:int, one:String, many:String, tint:Color, separator:bool ) -> void:
	if separator:
		stats_counter.add_text( ", " )
	var word := one if count == 1 else many
	stats_counter.push_color( tint )
	stats_counter.add_text( "%d %s" % [count, word] )
	stats_counter.pop()


func create_info( file_item:TreeItem ) -> Control:
	var test_def:TestDef = file_item.get_metadata(0)
	var file_name:String = file_item.get_text(0)

	var info_box:InfoBox = INFO_BOX.instantiate()
	info_items.add_child(info_box)
	info_box.show()
	if not info_box.is_node_ready(): await info_box.ready

	info_box.set_title( "/".join([test_def.name, file_name]) )

	return info_box


func _run_rows_as_editor( _paths:PackedStringArray ) -> void:
	var rows:Array[TreeItem] = []
	rows.assign( _pending_rows )
	await _walk_rows( rows )


func process_selection() -> void:
	await _walk_rows( _selection_files() )


func _walk_rows( rows:Array[TreeItem] ) -> void:
	_walks += 1
	CaseMenu.begin_set()
	_apply_run_button()
	# One frame so Cancel paints before the first script, and a click can land.
	var scene_tree:SceneTree = get_tree()
	if scene_tree != null:
		await scene_tree.process_frame
	for file_item:TreeItem in rows:
		if _halt_walk or CaseMenu.halt_set:
			break
		if not is_instance_valid( file_item ):
			continue
		# The menu counter can drop after one script. This walk is still open.
		_apply_run_button()
		await process_test( file_item )
	_walks = maxi( _walks - 1, 0 )
	if _walks == 0:
		_halt_walk = false
	CaseMenu.end_set()
	_apply_run_button()


func _selection_files() -> Array[TreeItem]:
	var files:Array[TreeItem] = []
	var root:TreeItem = tests_tree.get_root()
	if root == null:
		return files
	var selection:Array[TreeItem] = _live_selection()
	if selection.is_empty() or root in selection:
		selection = root.get_children()
	for item:TreeItem in selection:
		if not is_instance_valid( item ):
			continue
		for file_item:TreeItem in _file_items_under( item ):
			files.append( file_item )
	return files


## Drop keys whose rows were freed when the tree was rebuilt.
func _live_selection() -> Array[TreeItem]:
	var live:Array[TreeItem] = []
	var stale:Array = []
	for key:Variant in test_selection.keys():
		if not is_instance_valid( key ):
			stale.append( key )
			continue
		var row:TreeItem = key
		live.append( row )
	for key:Variant in stale:
		test_selection.erase( key )
	return live


func _case_paths_of( files:Array[TreeItem] ) -> PackedStringArray:
	var case_paths := PackedStringArray()
	for file_item:TreeItem in files:
		if not is_instance_valid( file_item ):
			continue
		var path:String = _row_path( file_item )
		if not CaseSession.is_case_path( path ):
			continue
		if case_paths.append( path ):
			push_error( "main_panel._case_paths_of: append failed" )
			break
	return case_paths



func process_test( file_item:TreeItem ) -> void:
	if not _is_file_item( file_item ):
		return
	var info_box:InfoBox = await create_info( file_item )
	var test_def:TestDef = file_item.get_metadata(0)
	var script_file:String = file_item.get_text(0)
	var script_path:String = "/".join([test_def.folder_path, script_file])
	var info_text:String

	# We're only keeping around one rest result per test.
	var result:TestResult = test_def.results.get_or_add( file_item, TestResult.new() )
	result.latest = info_box
	result.retcode = RetCode.TEST_FAILED
	result.output = ["Only Just Created"]
	update_tree_item(file_item, "INPROGRESS")

	# Tests can be run three ways.
	# 	1. Headless as EditorScript
	# 	2. From the test runner as EditorScript
	# 	3. In a game from the test runner as Node
	# If the last, the script header needs to be re-written to extend Node.
	# A case keeps its script. The session is the host.
	var case_run:bool = CaseSession.is_case_path( script_path )
	if not case_run and not Engine.is_editor_hint():
		script_path = re_write(script_path)
		# If Script path fails
		if script_path.is_empty():
			result.retcode = RetCode.TEST_FAILED
			result.output = ["Re-Writing the script for in-game testing failed."]
			info_text = result.output.reduce(Shared.reducer_to_lines)
			update_tree_item(file_item, "FAILED" )
			info_box.set_content( "FAILED", info_text )
			return

	# Load up the script and run the test
	var script:GDScript = load( script_path )
	if script == null or not script.can_instantiate():
		result.output = ["Cannot instantiate '%s'" % script_path ]
	elif case_run:
		await run_case( script, result )
	elif Engine.is_editor_hint():
		var instance:TestBase  = script.new()
		if instance:await run_test_base( instance, result )

	#Erase our alternate script file after we are done.
	if not case_run and not Engine.is_editor_hint():
		var err:Error = DirAccess.remove_absolute(script_path)
		if err != OK:
			var msg:String = error_string(err) + ": Failure to remove alternate script"
			result.output.append(msg)
			printerr( msg )

	if Log.allows( test_lvl, Log.Level.INFO ) \
	or result.retcode == RetCode.TEST_FAILED:
		info_text = "Empty" if result.output.is_empty() \
			else result.output.reduce(Shared.reducer_to_lines)

	# Update the tree_item
	if result.retcode == RetCode.TEST_FAILED:
		update_tree_item(file_item, "FAILED")
		info_box.set_content( "FAILED", info_text )
	elif 'warn' in info_text.to_lower():
		update_tree_item(file_item, "WARNING" )
		info_box.set_content( "WARNING", info_text )
	else:
		update_tree_item(file_item, "OK" )
		info_box.set_content( "OK", info_text )
	update_stats()


func run_test_base( instance:TestBase, result:TestResult ) -> void:
	_apply_opts()
	instance.local_lvl = test_lvl
	@warning_ignore('redundant_await')
	await instance.run_harness()
	result.retcode = instance.runcode as RetCode
	result.output = instance.output


## Editor host while this dock is in the editor. Play host while a game is running.
func run_case( script:GDScript, result:TestResult ) -> void:
	_apply_opts()
	var session := CaseSession.new()
	session.host = CaseSession.Host.EDITOR if Engine.is_editor_hint() else CaseSession.Host.PLAY
	# The options flag requests a capture. Off leaves the run untraced.
	if test_tracy:
		session.capture_request = 1
	var scene_tree:SceneTree = get_tree()
	if scene_tree == null:
		result.retcode = RetCode.TEST_FAILED
		result.output = ["No SceneTree for case"]
		return
	session.attach_tree( scene_tree )
	var body:Case = session.instantiate( script )
	if body == null:
		result.retcode = RetCode.TEST_FAILED
		result.output = ["Not a case"]
		return
	await session.run_await( body )
	result.retcode = session.runcode as RetCode
	result.output = []
	for row:String in session.line().split( "\n" ):
		result.output.append( row )


func re_write( orig_path:String) -> String:
	var orig:Dictionary = {
		"dir":orig_path.get_base_dir(),
		"name":orig_path.get_file().get_basename()
	}
	var alt_path := "{dir}/{name}_alt.gd".format(orig)

	var orig_file := FileAccess.open(orig_path, FileAccess.READ)
	if not orig_file.is_open():
		printerr("Failed to open file: ", orig_path)
		return ""

	# skip the first three lines.
	for i:int in 3:
		var _line:String = orig_file.get_line()

	var alt_file := FileAccess.open( alt_path, FileAccess.WRITE)
	var header_replacement:String = "# This script is modified automatically to work in play mode.
extends PlayBase\n"
	if not alt_file.store_string(header_replacement):
		printerr( "Failed to write to script alternate")
		orig_file.close()
		alt_file.close()
		return ""


	while not orig_file.eof_reached():
		var line:String = orig_file.get_line()
		if not alt_file.store_string(line + "\n"):
			printerr( "Failed to write to script alternate")
			orig_file.close()
			alt_file.close()
			return ""

	orig_file.close()
	alt_file.close()
	return alt_path


## Clear InfoBoxes + tree status; also clears service last-results when bound.
func clear_results_ui() -> void:
	if is_instance_valid( _service ) and _service.has_method( &"clear_results" ):
		_service.call( &"clear_results" )
	regenerate_tree()
	if info_items:
		for child in info_items.get_children():
			child.call_deferred( "queue_free" )


#       ██ ███    ██ ████████ ███████ ██████  ███    ██  █████  ██             #
#       ██ ████   ██    ██    ██      ██   ██ ████   ██ ██   ██ ██             #
#       ██ ██ ██  ██    ██    █████   ██████  ██ ██  ██ ███████ ██             #
#       ██ ██  ██ ██    ██    ██      ██   ██ ██  ██ ██ ██   ██ ██             #
#       ██ ██   ████    ██    ███████ ██   ██ ██   ████ ██   ██ ███████        #
func                        ________INTERNAL_________              ()->void:pass

## This binary registered the Profiler singleton. Stock Godot has no such name.
func _tracy_supported() -> bool:
	return Engine.has_singleton(&'Profiler')


## Copy [member opts] onto the service and the Tracy hook.
func _apply_opts() -> void:
	test_path = OptsScript.tests_root()
	case_path = OptsScript.cases_root()
	if opts != null:
		test_lvl = opts.lvl
		test_tracy = opts.tracy
	var capture_ready:bool = _tracy_supported() and TracyCapture.is_configured()
	var installer:Callable = Callable()
	if capture_ready and test_tracy:
		installer = Callable(TracyCapture, &"install")
	TestBase.prepare_run = installer
	if is_instance_valid( _service ) \
	and _service.has_method( &"set_lvl" ):
		_service.call( &"set_lvl", test_lvl )


func _load_help() -> String:
	var body:String = FileAccess.get_file_as_string( HELP_PATH )
	if FileAccess.get_open_error() != OK:
		return "The help file failed to load."
	return body


## Headings and `code` spans. The rest of the line stays as written.
func _help_bbcode( md:String ) -> String:
	var out:String = ""
	var started:bool = false
	for raw:String in md.split( "\n" ):
		if started:
			out += "\n"
		started = true
		var line:String = raw.strip_edges()
		if line.is_empty():
			continue
		if line.begins_with( "## " ):
			out += "[font_size=18][b]%s[/b][/font_size]" % _md_inline( line.substr( 3 ) )
			continue
		if line.begins_with( "# " ):
			out += "[font_size=22][b]%s[/b][/font_size]" % _md_inline( line.substr( 2 ) )
			continue
		out += _md_inline( line )
	return out


func _md_inline( line:String ) -> String:
	var parts:PackedStringArray = line.split( "`" )
	var out:String = ""
	for i:int in parts.size():
		if i % 2 == 1:
			out += "[code]%s[/code]" % parts[i]
		else:
			out += parts[i]
	return out


## Write one flag on [member opts]. The settings helper stores it.
func _store_flag( prop:StringName, value:Variant ) -> void:
	if opts != null \
	and opts.get( prop ) != value:
		opts.set( prop, value )
	_apply_opts()


func _case_root() -> String:
	var root_v:Variant = case_path
	if root_v is String:
		var text:String = root_v
		if not text.is_empty():
			return text
	case_path = OptsScript.cases_root()
	return case_path


func _cases_branch() -> TestDef:
	var root:String = _case_root()
	var branch:TestDef = TestDef.new()
	branch.name = "Cases"
	branch.folder_path = root
	branch.test_scripts = CaseSession.case_files( root )
	var tree:Array[Dictionary] = Shared.collect_test_tree(
			root, max_scan_depth, _gd_file_filter )
	for node:Dictionary in tree:
		var child:TestDef = _prune_case_def( _test_def_from_node( node ) )
		if child != null:
			branch.children.append( child )
	if branch.test_scripts.is_empty() and branch.children.is_empty():
		return null
	return branch


func _prune_case_def( def:TestDef ) -> TestDef:
	def.test_scripts = CaseSession.case_files( def.folder_path )
	var kept:Array = []
	for child_v:Variant in def.children:
		if child_v is TestDef:
			var child:TestDef = child_v
			var pruned:TestDef = _prune_case_def( child )
			if pruned != null:
				kept.append( pruned )
	def.children = kept
	if def.test_scripts.is_empty() and def.children.is_empty():
		return null
	return def


func _gd_file_filter( filename:String ) -> bool:
	return filename.ends_with( ".gd" )


func _test_def_from_node( node:Dictionary ) -> TestDef:
	var def:TestDef = TestDef.new()
	def.name = str( node.get( "name", "" ) )
	def.folder_path = str( node.get( "folder_path", "" ) )
	def.test_scripts = node.get( "test_scripts", [] )
	for child_v:Variant in node.get( "children", [] ):
		if child_v is Dictionary:
			var child:Dictionary = child_v
			def.children.append( _test_def_from_node( child ) )
	return def


func _is_file_item( item:TreeItem ) -> bool:
	if item == null:
		return false
	var meta:Variant = item.get_metadata( 0 )
	return meta is TestDef \
	and str( item.get_text( 0 ) ).ends_with( ".gd" )


func _file_items_under( item:TreeItem ) -> Array[TreeItem]:
	var out:Array[TreeItem] = []
	if item == null or not item.visible:
		return out
	if _is_file_item( item ):
		out.append( item )
	for child:TreeItem in item.get_children():
		out.append_array( _file_items_under( child ) )
	return out


#                       ████████ ██████  ███████ ███████                       #
#                          ██    ██   ██ ██      ██                            #
#                          ██    ██████  █████   █████                         #
#                          ██    ██   ██ ██      ██                            #
#                          ██    ██   ██ ███████ ███████                       #
func                        __________TREE___________              ()->void:pass

func add_action_row(
			test_def:TestDef,
			filename:String,
			parent_item:TreeItem
			) -> void:
	var item:TreeItem = parent_item.create_child()
	# Test Name
	item.set_selectable(0, false )
	item.set_metadata(0, test_def )
	item.set_text( 0, filename )
	# Result
	item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_CENTER)
	item.set_selectable(1, false )
	item.set_text(1, "PENDING ")
	item.set_expand_right(1, false)
	item.set_text_overrun_behavior(1, TextServer.OVERRUN_TRIM_ELLIPSIS)
	item.add_button(1, DEBUG_RERUN, -1, false, "[Re]Run Test Action" )
	item.set_icon(0, FILE_CODE)


func _fit_result_column() -> void:
	var font := tests_tree.get_theme_font( &"font" )
	var font_size := tests_tree.get_theme_font_size( &"font_size" )
	var widest := 0
	if font != null:
		for word:String in [ "PENDING ", "INPROGRESS", "WARNING", "FAILED", "OK", "Result" ]:
			var text_width := font.get_string_size( word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size ).x
			widest = maxi( widest, ceili( text_width ) )
	var outline := tests_tree.get_theme_constant( &"outline_size" )
	var button_margin := tests_tree.get_theme_constant( &"button_margin" )
	var inner := tests_tree.get_theme_constant( &"inner_item_margin_left" ) \
			+ tests_tree.get_theme_constant( &"inner_item_margin_right" )
	var separation := tests_tree.get_theme_constant( &"h_separation" )
	var width := widest + outline * 2 + DEBUG_RERUN.get_width() \
			+ button_margin + inner + separation
	tests_tree.set_column_custom_minimum_width( 1, width )


func regenerate_tree() -> void:
	# re-build the test dictionary
	test_list = collect_tests( test_path )

	# Rows are about to be freed. Selection keys must not outlive them.
	test_selection.clear()
	_pending_rows.clear()
	tests_tree.clear()

	# Add the column headers
	tests_tree.set_column_title(0, "Test")

	tests_tree.set_column_title(1, "Result")
	tests_tree.set_column_expand( 1, false)
	_fit_result_column()

	# Add the root
	var _top_item:TreeItem = tests_tree.create_item()
	_top_item.set_text(0,"Tests")

	# Add the rows (folder depth follows the disk; no hardcoded levels)
	var root_item:TreeItem = tests_tree.get_root()
	for test_def:TestDef in test_list:
		_add_folder_branch( test_def, root_item )

	update_stats()
	_apply_list_filter( list_filter.text if list_filter != null else "" )


func _status_font_color( label:String ) -> Color:
	var item := &"font_color"
	match label:
		"OK":
			item = &"result_ok"
		"WARNING":
			item = &"result_warning"
		"FAILED":
			item = &"result_failed"
		"INPROGRESS":
			item = &"result_progress"
	return tests_tree.get_theme_color( item )


func update_tree_item( item:TreeItem, label:String = "PENDING" ) -> void:
	item.set_text(1, label)
	item.clear_custom_color(0)
	if label == "PENDING":
		item.clear_custom_color(1)
		return
	item.set_custom_color(1, _status_font_color(label))


func _add_folder_branch( test_def:TestDef, parent_item:TreeItem ) -> void:
	# One script is still a folder. Collapsing it put that file on the parent.
	var folder_item:TreeItem = parent_item.create_child()
	folder_item.set_text( 0, test_def.name )
	folder_item.set_metadata( 0, test_def )
	folder_item.set_selectable( 1, false )
	folder_item.set_icon( 0, FOLDER_OPEN )
	folder_item.set_icon_max_width( 0, 16 )
	_add_folder_contents( test_def, folder_item )


func _add_folder_contents( test_def:TestDef, parent_item:TreeItem ) -> void:
	for child_v:Variant in test_def.children:
		if child_v is TestDef:
			var child_def:TestDef = child_v
			_add_folder_branch( child_def, parent_item )
	for file:String in test_def.test_scripts:
		add_action_row( test_def, file, parent_item )


func _apply_list_filter( pattern:String ) -> void:
	if tests_tree == null:
		return
	var root:TreeItem = tests_tree.get_root()
	if root == null:
		return
	var _shown:bool = _filter_item( root, _list_glob( pattern ) )
	_stripe_tree()


func _on_tree_collapsed( _item:TreeItem ) -> void:
	_stripe_tree()


## Tree paints a custom background over the selection style, so the stripe stays a theme color.
## Column 0 stops short of the Result column, so the same tint is painted there too.
func _stripe_tree() -> void:
	if tests_tree == null:
		return
	var root:TreeItem = tests_tree.get_root()
	if root == null:
		return
	var tint := tests_tree.get_theme_color( &"stripe" )
	var index:Array[int] = [0]
	_stripe_item( root, tint, index )


func _stripe_item( item:TreeItem, tint:Color, index:Array[int] ) -> void:
	if not item.visible:
		return
	var n:int = index[0]
	index[0] = n + 1
	if n % 2 == 1:
		item.set_custom_bg_color( 0, tint )
		item.set_custom_bg_color( 1, tint )
	else:
		item.clear_custom_bg_color( 0 )
		item.clear_custom_bg_color( 1 )
	if item.collapsed:
		return
	for child:TreeItem in item.get_children():
		_stripe_item( child, tint, index )


## A bare word matches anywhere in the name. * and ? stay as written.
func _list_glob( needle:String ) -> String:
	var text:String = needle.strip_edges()
	if text.is_empty():
		return ""
	if text.contains( "*" ) or text.contains( "?" ):
		return text
	return "*%s*" % text


## Returns true when this row stays on screen.
func _filter_item( item:TreeItem, glob:String ) -> bool:
	if item == tests_tree.get_root():
		var any_child:bool = false
		for child:TreeItem in item.get_children():
			any_child = _filter_item( child, glob ) or any_child
		item.visible = true
		return any_child
	if glob.is_empty():
		_set_all_visible( item )
		return true
	if not _is_file_item( item ) and item.get_text( 0 ).matchn( glob ):
		item.visible = true
		item.collapsed = false
		for child:TreeItem in item.get_children():
			_show_branch( child )
		return true

	var child_hit:bool = false
	for child:TreeItem in item.get_children():
		child_hit = _filter_item( child, glob ) or child_hit
	var keep:bool = child_hit or item.get_text( 0 ).matchn( glob )
	item.visible = keep
	if keep and item.get_child_count() > 0:
		item.collapsed = false
	return keep


func _set_all_visible( item:TreeItem ) -> void:
	item.visible = true
	for child:TreeItem in item.get_children():
		_set_all_visible( child )


func _show_branch( item:TreeItem ) -> void:
	item.visible = true
	if item.get_child_count() > 0:
		item.collapsed = false
	for child:TreeItem in item.get_children():
		_show_branch( child )

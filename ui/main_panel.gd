@tool
extends VBoxContainer

# Test Runner
# TODO - make the script names clickable to load them up in the editor.



# Scripts
const InfoBox = preload( "uid://gli414sa5hot" )
const Shared = preload( "uid://ccrhkvl5ptefw" )
const OptsScript = preload( "uid://c3rwpcm55iy6r" )
const Log = preload( "uid://br7jtx5cntuan" )
const CaseMenu = preload( "uid://bmxtuig6f1i7d" )
const TestTree = preload( "uid://dvvnrjmjouxec" )

# Classes
const TestDef = Shared.TestDef
const TestResult = Shared.TestResult
const RetCode = Shared.RetCode

# Scenes
const INFO_BOX = preload( "uid://dt0eqt7nuorql" )
const HELP_PATH:String = "res://addons/enetheru.test-runner/ui/help.md"

# ██████  ██████   ██████  ██████  ███████ ██████  ████████ ██ ███████ ███████ #
# ██   ██ ██   ██ ██    ██ ██   ██ ██      ██   ██    ██    ██ ██      ██      #
# ██████  ██████  ██    ██ ██████  █████   ██████     ██    ██ █████   ███████ #
# ██      ██   ██ ██    ██ ██      ██      ██   ██    ██    ██ ██           ██ #
# ██      ██   ██  ██████  ██      ███████ ██   ██    ██    ██ ███████ ███████ #
func                        ________PROPERTIES_______              ()->void:pass

# Top Row Left
@onready var run_btn: Button = $Buttons/Left/Run
@onready var run_kind: MenuButton = $Buttons/Left/RunKind
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
@onready var tests_tree: TestTree = $TestOutput/TestList/TestsTree
@onready var info_list: VBoxContainer = $TestOutput/InfoList
@onready var info_scroller: ScrollContainer = $TestOutput/InfoList/ScrollContainer
@onready var info_items: VBoxContainer = $TestOutput/InfoList/ScrollContainer/InfoItems

# Runtime
var test_list:Array[TestDef]



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

	# Outside the editor the run menu is hidden, so the rows run here.
	if not Engine.is_editor_hint():
		await process_selection()
		return

	var files := _selection_files()
	if files.is_empty():
		return
	var kinds:Array[int] = _checked_run_ids()
	if kinds.is_empty():
		return
	_pending_rows = files
	for kind_id:int in kinds:
		if _halt_walk or CaseMenu.halt_set:
			break
		if await _launch_kind( kind_id, files ):
			break


func _on_set_changed( _active: bool ) -> void:
	_apply_run_button()


func _apply_run_button() -> void:
	if not is_node_ready():
		return
	var active: bool = _walks > 0 or CaseMenu.set_count > 0
	var cancelling: bool = active and ( ( _walks > 0 and _halt_walk ) or CaseMenu.halt_set )
	if run_kind != null:
		run_kind.disabled = active
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
	var picking:bool = Engine.is_editor_hint() and _checked_run_ids().is_empty()
	run_btn.text = "Play"
	run_btn.icon = _play_icon
	run_btn.disabled = picking
	run_btn.tooltip_text = "Check a run in the menu." if picking else "Start the checked runs for the rows on screen."


func _on_reload_pressed() -> void:
	if is_instance_valid( _service ) and _service.has_method( &"reload" ):
		_service.call( &"reload" )
	regenerate_tree()
	# TODO, reload tests should have some effect on the results list


func _on_filter_text_changed( new_text:String ) -> void:
	tests_tree.apply_filter( new_text, _checked_run_ids() )


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


func _on_run_requested( item:TreeItem, kind_id:int ) -> void:
	await _run_kind_on_row( item, kind_id )


func _on_file_picked( item:TreeItem ) -> void:
	var metadata:Variant = item.get_metadata( 0 )
	if not metadata:
		return
	var test_def:TestDef = metadata
	var file_path:String = "/".join( [ test_def.folder_path, item.get_text( 0 ) ] )
	if Engine.is_editor_hint():
		EditorInterface.get_file_system_dock().navigate_to_path( file_path )
	var item_results:TestResult = test_def.results.get( item )
	if item_results and item_results.latest:
		item_results.latest.call_deferred( "grab_focus" )


func _popup_case_menu( item:TreeItem, at:Vector2 ) -> void:
	if not Engine.is_editor_hint():
		return
	if not is_instance_valid( item ):
		return
	var files := tests_tree.files_under( item )
	if files.is_empty():
		return
	_pending_rows = files
	# EditorScript runs these rows. Play and Headless still use the case paths.
	if not _show_run_menu( tests_tree.case_paths_of( files ), at, true ):
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


func _on_case_popup_hide() -> void:
	if is_instance_valid( _case_popup ):
		_case_popup.queue_free()
	_case_popup = null


#      ██████  ██    ██ ███████ ██████  ██████  ██ ██████  ███████ ███████     #
#     ██    ██ ██    ██ ██      ██   ██ ██   ██ ██ ██   ██ ██      ██          #
#     ██    ██ ██    ██ █████   ██████  ██████  ██ ██   ██ █████   ███████     #
#     ██    ██  ██  ██  ██      ██   ██ ██   ██ ██ ██   ██ ██           ██     #
#      ██████    ████   ███████ ██   ██ ██   ██ ██ ██████  ███████ ███████     #
func                        ________OVERRIDES________              ()->void:pass

func _ready() -> void:
	if opts != null \
	and not opts.changed.is_connected( _on_opts_changed ):
		@warning_ignore( "return_value_discarded" )
		opts.changed.connect( _on_opts_changed )
	_apply_opts()
	_play_icon = run_btn.icon
	CaseMenu.set_changed = _on_set_changed
	_on_set_changed( CaseMenu.set_count > 0 )
	_build_run_kinds()
	if not tests_tree.run_requested.is_connected( _on_run_requested ):
		@warning_ignore( "return_value_discarded" )
		tests_tree.run_requested.connect( _on_run_requested )
	if not tests_tree.context_menu_requested.is_connected( _popup_case_menu ):
		@warning_ignore( "return_value_discarded" )
		tests_tree.context_menu_requested.connect( _popup_case_menu )
	if not tests_tree.file_picked.is_connected( _on_file_picked ):
		@warning_ignore( "return_value_discarded" )
		tests_tree.file_picked.connect( _on_file_picked )
	_on_reload_pressed()


func _exit_tree() -> void:
	if opts != null \
	and opts.changed.is_connected( _on_opts_changed ):
		opts.changed.disconnect( _on_opts_changed )
	if CaseMenu.set_changed == _on_set_changed:
		CaseMenu.set_changed = Callable()
	if is_instance_valid( run_kind ) \
	and run_kind.get_popup().index_pressed.is_connected( _on_run_kind_index_pressed ):
		run_kind.get_popup().index_pressed.disconnect( _on_run_kind_index_pressed )


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


## True when Cancel stopped this walk. Later checked runs stay unstarted.
func _walk_rows( rows:Array[TreeItem] ) -> bool:
	_walks += 1
	CaseMenu.begin_set()
	_apply_run_button()
	# One frame so Cancel paints before the first script, and a click can land.
	var scene_tree:SceneTree = get_tree()
	if scene_tree != null:
		await scene_tree.process_frame
	var stopped := false
	for file_item:TreeItem in rows:
		if _halt_walk or CaseMenu.halt_set:
			stopped = true
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
	return stopped


func _selection_files() -> Array[TreeItem]:
	return tests_tree.selected_files()


func _build_run_kinds() -> void:
	if run_kind == null:
		return
	if not Engine.is_editor_hint():
		run_kind.visible = false
		return
	var popup := run_kind.get_popup()
	popup.clear()
	# The menu draws the mark. It does not change it.
	popup.hide_on_item_selection = false
	popup.hide_on_checkable_item_selection = false
	_add_run_kind( popup, "EditorScript", CaseSession.Launch.EDITORSCRIPT, true )
	_add_run_kind( popup, "Play Editor", CaseSession.Launch.PLAY_EDITOR, false )
	_add_run_kind( popup, "Play template_debug", CaseSession.Launch.PLAY_DEBUG, false )
	_add_run_kind( popup, "Play template_release", CaseSession.Launch.PLAY_RELEASE, false )
	_add_run_kind( popup, "Headless -s", CaseSession.Launch.HEADLESS, false )
	if not popup.index_pressed.is_connected( _on_run_kind_index_pressed ):
		var err:int = popup.index_pressed.connect( _on_run_kind_index_pressed )
		if err != OK:
			push_error( "main_panel._build_run_kinds: connect failed (%s)" % error_string( err ) )
	_refresh_run_kind_title()
	_apply_run_button()


func _add_run_kind( popup:PopupMenu, label:String, id:int, on:bool ) -> void:
	popup.add_item( label, id )
	var index := popup.get_item_index( id )
	popup.set_item_as_checkable( index, true )
	popup.set_item_checked( index, on )


func _on_run_kind_index_pressed( index:int ) -> void:
	var popup := run_kind.get_popup()
	popup.toggle_item_checked( index )

	_refresh_run_kind_title()
	_apply_list_filter()
	_apply_run_button()


func _refresh_run_kind_title() -> void:
	if run_kind == null:
		return
	var labels := PackedStringArray()
	var popup := run_kind.get_popup()
	for index:int in popup.item_count:
		if not popup.is_item_checked( index ):
			continue
		if labels.append( popup.get_item_text( index ) ):
			push_error( "main_panel._refresh_run_kind_title: append failed" )
			break
	if labels.is_empty():
		run_kind.text = "No run"
		return
	if labels.size() == 1:
		run_kind.text = labels[0]
		return
	run_kind.text = "%d runs" % labels.size()


func _checked_run_ids() -> Array[int]:
	var ids:Array[int] = []
	if run_kind == null or not run_kind.visible:
		return ids
	var popup := run_kind.get_popup()
	for index:int in popup.item_count:
		if popup.is_item_checked( index ):
			ids.append( popup.get_item_id( index ) )
	return ids


func process_test( file_item:TreeItem ) -> void:
	if not tests_tree.is_file_item( file_item ):
		return
	var info_box:InfoBox = await create_info( file_item )
	var test_def:TestDef = file_item.get_metadata(0)
	var script_file:String = file_item.get_text(0)
	var script_path:String = "/".join([test_def.folder_path, script_file])
	var info_text := ""

	# We're only keeping around one rest result per test.
	var result:TestResult = test_def.results.get_or_add( file_item, TestResult.new() )
	result.latest = info_box
	result.retcode = RetCode.TEST_FAILED
	result.output = ["Only Just Created"]
	tests_tree.remember( script_path, CaseSession.Launch.EDITORSCRIPT, TestTree.Mark.RUN )
	tests_tree.paint_kind( file_item, CaseSession.Launch.EDITORSCRIPT )
	tests_tree.set_status( file_item, TestTree.Status.INPROGRESS )

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
			_finish_editor( file_item, script_path, result, info_box, info_text )
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

	_finish_editor( file_item, script_path, result, info_box, info_text )


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
	tests_tree.clear_marks()
	regenerate_tree()
	if info_items:
		for child in info_items.get_children():
			child.call_deferred( "queue_free" )


func regenerate_tree() -> void:
	test_list = collect_tests( test_path )
	_pending_rows.clear()
	tests_tree.rebuild( test_list )
	update_stats()
	_apply_list_filter()


func _apply_list_filter() -> void:
	var pattern := ""
	if list_filter != null:
		pattern = list_filter.text
	tests_tree.apply_filter( pattern, _checked_run_ids() )


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


## One file, one run kind. EditorScript walks the row. The other kinds launch.
func _run_kind_on_row( item:TreeItem, kind_id:int ) -> void:
	if not tests_tree.is_file_item( item ):
		return
	if _walks > 0 or CaseMenu.set_count > 0:
		return
	var files:Array[TreeItem] = [item]
	await _launch_kind( kind_id, files )


## True when Cancel stopped this kind. EditorScript walks. Other kinds read the case report.
func _launch_kind( kind_id:int, files:Array[TreeItem] ) -> bool:
	if kind_id == CaseSession.Launch.EDITORSCRIPT:
		_pending_rows = files
		return await _walk_rows( files )
	var paths:PackedStringArray = tests_tree.paths_for_kind( kind_id, files )
	if paths.is_empty():
		return false
	for file_item:TreeItem in files:
		if is_instance_valid( file_item ) and tests_tree.kind_allows( kind_id, file_item ):
			tests_tree.remember( tests_tree.row_path( file_item ), kind_id, TestTree.Mark.RUN )
			tests_tree.paint_kind( file_item, kind_id )
			tests_tree.set_status( file_item, TestTree.Status.INPROGRESS )
	_walks += 1
	_apply_run_button()
	if _run_menu == null:
		_run_menu = CaseMenu.new()
	_run_menu.launch( kind_id, paths )
	if kind_id == CaseSession.Launch.PLAY_EDITOR:
		await _wait_for_play()
	_apply_report( kind_id, paths )
	var stopped := _halt_walk
	_walks = maxi( _walks - 1, 0 )
	if _walks == 0:
		_halt_walk = false
	_apply_run_button()
	return stopped


func _wait_for_play() -> void:
	var scene_tree:SceneTree = get_tree()
	if scene_tree == null:
		return
	var deadline:int = Time.get_ticks_msec() + 8000
	while not EditorInterface.is_playing_scene() and Time.get_ticks_msec() < deadline:
		await scene_tree.process_frame
	while EditorInterface.is_playing_scene():
		if _halt_walk:
			EditorInterface.stop_playing_scene()
		await scene_tree.process_frame


func _apply_report( kind_id:int, paths:PackedStringArray ) -> void:
	var seen:Dictionary = {}
	var text:String = FileAccess.get_file_as_string( CaseSession.report_file() )
	for raw:String in text.split( "\n" ):
		var line := raw.strip_edges()
		if not line.begins_with( "case " ):
			continue
		var path := ""
		var status := ""
		for part:String in line.split( " " ):
			if part.begins_with( "path=" ):
				path = part.trim_prefix( "path=" )
			elif part.begins_with( "status=" ):
				status = part.trim_prefix( "status=" )
		if path == "":
			continue
		var mark:TestTree.Mark = TestTree.Mark.OK if status == "pass" else TestTree.Mark.FAIL
		seen[path] = true
		tests_tree.remember( path, kind_id, mark )
		tests_tree.repaint_path( path )
	for path:String in paths:
		if seen.has( path ):
			continue
		tests_tree.remember( path, kind_id, TestTree.Mark.FAIL )
		tests_tree.repaint_path( path )


func _finish_editor(
			item:TreeItem,
			path:String,
			result:TestResult,
			info_box:InfoBox,
			info_text:String
			) -> void:
	var mark := TestTree.Mark.FAIL
	var status := TestTree.Status.FAILED
	if result.retcode != RetCode.TEST_FAILED:
		if "warn" in info_text.to_lower():
			mark = TestTree.Mark.WARN
			status = TestTree.Status.WARNING
		else:
			mark = TestTree.Mark.OK
			status = TestTree.Status.OK
	var label := tests_tree.status_text( status )
	tests_tree.remember( path, CaseSession.Launch.EDITORSCRIPT, mark )
	tests_tree.paint_kind( item, CaseSession.Launch.EDITORSCRIPT )
	tests_tree.set_status( item, status )
	if info_box != null:
		info_box.set_content( label, info_text )
	update_stats()

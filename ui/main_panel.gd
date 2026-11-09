@tool
extends VBoxContainer

# Test Runner
# TODO - make the script names clickable to load them up in the editor.



# Scripts
const InfoBox = preload('info_box.gd')
const Shared = preload('../scripts/shared.gd')
const OptsScript = preload( "../scripts/test_runner_opts.gd" )
const Log = preload('../logging.gd')

# Classes
const TestDef = Shared.TestDef
const TestResult = Shared.TestResult
const RetCode = Shared.RetCode

# Scenes
const INFO_BOX = preload('info_box.tscn')

# Resources
# Icons
const DEBUG_RERUN = preload('../res/debug-rerun.svg')
const FILE_CODE = preload('../res/file-code.svg')
const FOLDER_OPEN = preload('../res/folder-open.svg')

const FLIP_TAILS = preload('../res/flip_tails.svg')
const FLIP_HEAD = preload('../res/flip_head.svg')
const FLIP_HALF = preload('../res/flip_half.svg')

const MEDAL = preload('../res/medal.tres')
const SKULL = preload('../res/skull.svg')

const color_OK = Color.DARK_GREEN
const color_OK_bright = Color.GREEN_YELLOW
const color_FAILURE = Color.DARK_RED
const color_FAILURE_bright = Color.TOMATO
const color_WARNING = Color.DARK_GOLDENROD
const color_WARNING_bright = Color.GOLD
const color_TEST = Color.HOT_PINK


# ██████  ██████   ██████  ██████  ███████ ██████  ████████ ██ ███████ ███████ #
# ██   ██ ██   ██ ██    ██ ██   ██ ██      ██   ██    ██    ██ ██      ██      #
# ██████  ██████  ██    ██ ██████  █████   ██████     ██    ██ █████   ███████ #
# ██      ██   ██ ██    ██ ██      ██      ██   ██    ██    ██ ██           ██ #
# ██      ██   ██  ██████  ██      ███████ ██   ██    ██    ██ ███████ ███████ #
func                        ________PROPERTIES_______              ()->void:pass

# Top Row Left
@onready var run_btn: Button = $Buttons/Left/Run
@onready var reload_btn: Button = $Buttons/Left/Reload
@onready var filters_btn: Button = $Buttons/Left/Filters
@onready var folder_btn: Button = $Buttons/Left/Folder

# Top Row Center
@onready var stats_counter: RichTextLabel = $Buttons/Center/StatsCounter
# Top Row Right
@onready var tracy_btn: CheckButton = $Buttons/Right/Tracy
@onready var lvl_btn: OptionButton = $Buttons/Right/Level
@onready var clear_btn: Button = $Buttons/Right/ClearResults
@onready var help_btn: Button = $Buttons/Right/Help

# Help Popup
@onready var help_popup: PopupPanel = $PopupPanel

# tree control
@onready var tests_tree: Tree = $TestOutput/TestsTree
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
	# The button signal drops this state. Awaiting keeps it until the selection finishes.
	await process_selection()


func _on_reload_pressed() -> void:
	if is_instance_valid( _service ) and _service.has_method( &"reload" ):
		_service.call( &"reload" )
	regenerate_tree()
	# TODO, reload tests should have some effect on the results list


func _on_filters_pressed() -> void:
	pass # Replace with function body.


func _on_folder_pressed() -> void:
	pass # Replace with function body.


func _on_tracy_toggled(toggled_on: bool) -> void:
	_store_flag( &"tracy", toggled_on )


func _on_lvl_selected( index:int ) -> void:
	if index < 0 or index >= Log.CEILINGS.size():
		return
	_store_flag( &"lvl", Log.CEILINGS[index] )


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
	#var column = tree.get_column_at_position(mb_event.position)
	var tree_item:TreeItem = tests_tree.get_item_at_position(mb_event.position)
	if not tree_item: return

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
	_on_reload_pressed()


func _exit_tree() -> void:
	if opts != null \
	and opts.changed.is_connected( _on_opts_changed ):
		opts.changed.disconnect( _on_opts_changed )


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

	stats_counter.add_text("%d:" % groups)
	stats_counter.add_image(FOLDER_OPEN, 23)
	stats_counter.add_text(", %d:" % results)
	stats_counter.add_image(FLIP_HALF, 23)
	stats_counter.add_text(", %d:" % failures)
	stats_counter.add_image(FLIP_TAILS, 23, 23, color_FAILURE_bright)
	stats_counter.add_text(", %d:" % successes)
	stats_counter.add_image(FLIP_HEAD, 23, 23, color_OK_bright)
	already_updating = false


func create_info( file_item:TreeItem ) -> Control:
	var test_def:TestDef = file_item.get_metadata(0)
	var file_name:String = file_item.get_text(0)

	var info_box:InfoBox = INFO_BOX.instantiate()
	info_items.add_child(info_box)
	info_box.show()
	if not info_box.is_node_ready(): await info_box.ready

	info_box.set_title( "/".join([test_def.name, file_name]) )

	return info_box


func process_selection() -> void:
	var selection:Array
	if test_selection.is_empty():
		selection = tests_tree.get_root().get_children()
	elif tests_tree.get_root() in test_selection.keys():
		selection = tests_tree.get_root().get_children()
	else:
		selection = test_selection.keys()

	for item:TreeItem in selection:
		for file_item:TreeItem in _file_items_under( item ):
			await process_test( file_item )



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
	update_tree_item(file_item, "INPROGRESS", Color.REBECCA_PURPLE)

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
			info_box.set_content( color_FAILURE, FLIP_TAILS, info_text)
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
	#else:
		#var instance:PlayBase  = script.new()
		#if instance :
			#get_tree().root.add_child(instance, true)
			#await run_play_base( instance, result,  )
		#instance.queue_free()

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
		info_box.set_content( color_FAILURE, FLIP_TAILS, info_text )
	elif 'warn' in info_text.to_lower():
		update_tree_item(file_item, "WARNING" )
		info_box.set_content( color_WARNING, FLIP_HALF, info_text )
	else:
		update_tree_item(file_item, "OK" )
		info_box.set_content( color_OK, FLIP_HEAD, info_text )
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
	# The button forces a capture. Off leaves the saved Tracy flag in charge.
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


#func run_play_base( instance:PlayBase, result:TestResult ) -> void:
	#_apply_opts()
	#instance.local_lvl = test_lvl
	#@warning_ignore('redundant_await')
	#await instance.run_test()
	#result.retcode = instance.runcode as RetCode
	#result.output = instance.output


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


## Copy [member opts] onto the buttons, the service, and the Tracy hook.
func _apply_opts() -> void:
	test_path = OptsScript.tests_root()
	case_path = OptsScript.cases_root()
	if opts != null:
		test_lvl = opts.lvl
		test_tracy = opts.tracy
	var supported:bool = _tracy_supported()
	var capture_ready:bool = supported and TracyCapture.is_configured()
	if is_node_ready():
		_sync_lvl_btn()
		tracy_btn.visible = supported
		tracy_btn.disabled = not capture_ready
		if capture_ready:
			tracy_btn.tooltip_text = "Capture a Tracy trace for each run."
			tracy_btn.set_pressed_no_signal( test_tracy )
		else:
			tracy_btn.tooltip_text = "Set the Tracy capture executable, Python, and crop scripts before this can be enabled."
			tracy_btn.set_pressed_no_signal( false )
	var installer:Callable = Callable()
	if capture_ready and test_tracy:
		installer = Callable(TracyCapture, &"install")
	TestBase.prepare_run = installer
	#PlayBase.prepare_run = installer
	if is_instance_valid( _service ) \
	and _service.has_method( &"set_lvl" ):
		_service.call( &"set_lvl", test_lvl )


## Show [member test_lvl] on the level button. Signals stay blocked.
func _sync_lvl_btn() -> void:
	if not is_instance_valid( lvl_btn ):
		return
	lvl_btn.set_block_signals( true )
	if lvl_btn.item_count != Log.CEILINGS.size():
		lvl_btn.clear()
		for mask:int in Log.CEILINGS:
			lvl_btn.add_item( Log.level_label( mask ) )
	var idx:int = Log.CEILINGS.find( test_lvl )
	if idx < 0:
		idx = 0
	lvl_btn.select( idx )
	lvl_btn.set_block_signals( false )


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
	item.set_expand_right(1, true)
	item.set_text_overrun_behavior(1, TextServer.OVERRUN_NO_TRIMMING)
	item.add_button(1, DEBUG_RERUN, -1, false, "[Re]Run Test Action" )
	item.set_icon(0, FILE_CODE)


func regenerate_tree() -> void:
	# re-build the test dictionary
	test_list = collect_tests( test_path )

	# Clear the old tree
	tests_tree.clear()

	# Add the column headers
	tests_tree.set_column_title(0, "TestElement")

	tests_tree.set_column_title(1, "Result")
	tests_tree.set_column_expand( 1, false)
	#tests_tree.set_column_custom_minimum_width(1, 160)
	# TODO Calculate the size based on the theme font and the maximum size.

	# Add the root
	var _top_item:TreeItem = tests_tree.create_item()
	_top_item.set_text(0,"Tests")

	# Add the rows (folder depth follows the disk; no hardcoded levels)
	var root_item:TreeItem = tests_tree.get_root()
	for test_def:TestDef in test_list:
		_add_folder_branch( test_def, root_item )

	update_stats()


func update_tree_item(
			item:TreeItem,
			label:String = "PENDING",
			color:Color = color_TEST
			) -> void:
	item.set_text(1, label)
	match label:
		"PENDING" when color == color_TEST:
			item.clear_custom_bg_color(0)
			item.clear_custom_bg_color(1)
		"FAILURE" when color == color_TEST:
			item.set_custom_bg_color(0, color_FAILURE)
			item.set_custom_bg_color(1, color_FAILURE)
		"OK" when color == color_TEST:
			item.set_custom_bg_color(0, color_OK)
			item.set_custom_bg_color(1, color_OK)
		_:
			item.set_custom_bg_color(0, color)
			item.set_custom_bg_color(1, color)


func _add_folder_branch( test_def:TestDef, parent_item:TreeItem ) -> void:
	# One script is still a folder. Collapsing it put that file on the parent.
	var folder_item:TreeItem = parent_item.create_child()
	folder_item.set_text( 0, test_def.name )
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

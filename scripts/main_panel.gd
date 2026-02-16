@tool
extends VBoxContainer

# Test Runner
# TODO - make the script names clickable to load them up in the editor.

#           ████ ███    ███ ██████   ██████  ██████  ████████ ███████          #
#            ██  ████  ████ ██   ██ ██    ██ ██   ██    ██    ██               #
#            ██  ██ ████ ██ ██████  ██    ██ ██████     ██    ███████          #
#            ██  ██  ██  ██ ██      ██    ██ ██   ██    ██         ██          #
#           ████ ██      ██ ██       ██████  ██   ██    ██    ███████          #
func                        _________IMPORTS_________              ()->void:pass

# Scripts
const InfoBox = preload('uid://gli414sa5hot')
const Shared = preload('uid://ccrhkvl5ptefw')

# Classes
const TestDef = Shared.TestDef
const TestResult = Shared.TestResult
const RetCode = Shared.RetCode

# Scenes
const INFO_BOX = preload('uid://dt0eqt7nuorql')

# Resources
# Icons
const DEBUG_RERUN = preload('uid://dvy1xigrytulx')
const FILE_CODE = preload('uid://cvot4lpp8maag')
const FOLDER_OPEN = preload('uid://cepxbj0ne0kkt')

const FLIP_HALF = preload('uid://biv4nfodlftli')
const FLIP_HEAD = preload('uid://35f3dwsmtyx3')
const FLIP_TAILS = preload('uid://b7mrw71e2x5gx')

const MEDAL = preload('uid://buto46ta3chpg')
const SKULL = preload('uid://bq1h8nwto0qun')

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
@onready var verbose_btn: CheckButton = $Buttons/Right/Verbose
@onready var debug_btn: CheckButton = $Buttons/Right/Debug
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
var test_list : Array[TestDef]
var test_selection : Dictionary = {}
var test_verbose : bool = false
var test_debug : bool = false

# Configuration
var test_path : String = 'res://tests'
var test_script_filter : Callable = default_script_filter
var test_folder_filter : Callable = default_folder_filter


#             ███████ ██    ██ ███████ ███    ██ ████████ ███████              #
#             ██      ██    ██ ██      ████   ██    ██    ██                   #
#             █████   ██    ██ █████   ██ ██  ██    ██    ███████              #
#             ██       ██  ██  ██      ██  ██ ██    ██         ██              #
#             ███████   ████   ███████ ██   ████    ██    ███████              #
func                        __________EVENTS_________              ()->void:pass

func _on_run_pressed() -> void:
	process_selection()


func _on_reload_pressed() -> void:
	regenerate_tree()
	# TODO, reload tests should have some effect on the results list


func _on_filters_pressed() -> void:
	pass # Replace with function body.


func _on_folder_pressed() -> void:
	pass # Replace with function body.


func _on_verbose_toggled(toggled_on: bool) -> void:
	test_verbose = toggled_on


func _on_debug_toggled(toggled_on: bool) -> void:
	test_debug = toggled_on


func _on_clear_results_pressed() -> void:
	regenerate_tree()
	for child in info_items.get_children():
		child.call_deferred("queue_free")


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
	process_test(item)


func _on_tests_tree_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton: return
	var mb_event : InputEventMouseButton = event
	if not mb_event.pressed: return
	#var column = tree.get_column_at_position(mb_event.position)
	var tree_item : TreeItem = tests_tree.get_item_at_position(mb_event.position)
	if not tree_item: return

	var metadata : Variant = tree_item.get_metadata(0)
	if not metadata: return
	var test_def : TestDef = metadata
	var test_file : String = tree_item.get_text(0)

	# FIXME it would be nice if I could get the file open in the text editor
	var file_path : String = "/".join([test_def.folder_path, test_file])
	if Engine.is_editor_hint():
		EditorInterface.get_file_system_dock().navigate_to_path(file_path)

	var item_results : TestResult = test_def.results.get(tree_item)
	if item_results and item_results.latest:
		item_results.latest.call_deferred( "grab_focus")


#      ██████  ██    ██ ███████ ██████  ██████  ██ ██████  ███████ ███████     #
#     ██    ██ ██    ██ ██      ██   ██ ██   ██ ██ ██   ██ ██      ██          #
#     ██    ██ ██    ██ █████   ██████  ██████  ██ ██   ██ █████   ███████     #
#     ██    ██  ██  ██  ██      ██   ██ ██   ██ ██ ██   ██ ██           ██     #
#      ██████    ████   ███████ ██   ██ ██   ██ ██ ██████  ███████ ███████     #
func                        ________OVERRIDES________              ()->void:pass

func _ready() -> void:
	_on_reload_pressed()


#         ███    ███ ███████ ████████ ██   ██  ██████  ██████  ███████         #
#         ████  ████ ██         ██    ██   ██ ██    ██ ██   ██ ██              #
#         ██ ████ ██ █████      ██    ███████ ██    ██ ██   ██ ███████         #
#         ██  ██  ██ ██         ██    ██   ██ ██    ██ ██   ██      ██         #
#         ██      ██ ███████    ██    ██   ██  ██████  ██████  ███████         #
func                        _________METHODS_________              ()->void:pass

func default_script_filter( filename : String ) -> bool:
	return filename.begins_with("test") \
		and filename.ends_with(".gd") \
		and not filename.ends_with("_generated.gd")


func default_folder_filter( folder_path : String ) -> bool:
	var files : Array = DirAccess.get_files_at( folder_path )
	return not files.filter( test_script_filter ).is_empty()


func collect_tests( _path : String ) -> Array[TestDef]:
	var tests : Array[TestDef]

	var folders : Array = DirAccess.get_directories_at(_path)
	var folder_paths : Array = folders.map( func(folder : String) -> String:
			return "/".join([_path,folder]))
	folder_paths.sort()
	for folder_path : String in folder_paths.filter( test_folder_filter ):
		var files : Array = DirAccess.get_files_at( folder_path )
		var folder : String = folder_path.get_file()

		var def : TestDef = TestDef.new()
		def.name =  folder.to_pascal_case()
		def.folder_path =  folder_path
		def.test_scripts =  files.filter( test_script_filter )

		tests.append( def )

	return tests


var already_updating : bool = false
func update_stats() -> void:
	if already_updating: return
	already_updating = true
	stats_counter.clear()
	var groups : int = 0
	var results : int = 0
	var failures : int = 0
	var successes : int = 0
	for test_def : TestDef in test_list:
		groups += 1
		for result : TestResult in test_def.results.values():
			results += 1
			if result.retcode == RetCode.TEST_OK: successes += 1
			if result.retcode == RetCode.TEST_FAILED: failures += 1

	stats_counter.add_text("%d:" % groups)
	stats_counter.add_image(FOLDER_OPEN, 23)
	stats_counter.add_text(", %d:" % results)
	stats_counter.add_image(FLIP_HALF, 23)
	stats_counter.add_text(", %d:" % failures)
	stats_counter.add_image(FLIP_TAILS, 23, 23, color_FAILURE_bright)
	stats_counter.add_text(", %d:" % successes)
	stats_counter.add_image(FLIP_HEAD, 23, 23, color_OK_bright)
	already_updating = false


func create_info( file_item : TreeItem ) -> Control:
	var test_def : TestDef = file_item.get_metadata(0)
	var file_name : String = file_item.get_text(0)

	var info_box : InfoBox = INFO_BOX.instantiate()
	info_items.add_child(info_box)
	info_box.show()
	if not info_box.is_node_ready(): await info_box.ready

	info_box.set_title( "/".join([test_def.name, file_name]) )

	return info_box


func process_selection() -> void:
	var selection : Array
	if test_selection.is_empty():
		selection = tests_tree.get_root().get_children()
	elif tests_tree.get_root() in test_selection.keys():
		selection = tests_tree.get_root().get_children()
	else:
		selection = test_selection.keys()

	for folder_item : TreeItem in selection:
		for file_item : TreeItem in folder_item.get_children():
			var _test_def : TestDef = file_item.get_metadata(0)
			process_test(file_item)


func process_test( file_item : TreeItem ) -> void:
	var info_box : InfoBox = await create_info( file_item )
	var test_def : TestDef = file_item.get_metadata(0)
	var script_file : String = file_item.get_text(0)
	var script_path : String = "/".join([test_def.folder_path, script_file])
	var info_text : String

	# We're only keeping around one rest result per test.
	var result : TestResult = test_def.results.get_or_add( file_item, TestResult.new() )
	result.latest = info_box
	result.retcode = RetCode.TEST_FAILED
	result.output = ["Only Just Created"]
	update_tree_item(file_item, "INPROGRESS", Color.REBECCA_PURPLE)

	# Tests can be run three ways.
	# 	1. Headless as EditorScript
	# 	2. From the test runner as EditorScript
	# 	3. In a game from the test runner as Node
	# If the last, the script header needs to be re-written to extend Node
	if not Engine.is_editor_hint():
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
	var script : GDScript = load( script_path )
	if not script.can_instantiate():
		result.output = ["Cannot instantiate '%s'" % script_path ]
	elif Engine.is_editor_hint():
		var instance : TestBase  = script.new()
		if instance : await run_test_base( instance, result )
	else:
		var instance : PlayBase  = script.new()
		if instance :
			get_tree().root.add_child(instance, true)
			await run_play_base( instance, result,  )
		instance.queue_free()

	#Erase our alternate script file after we are done.
	if not Engine.is_editor_hint():
		var err : Error = DirAccess.remove_absolute(script_path)
		if err != OK:
			var msg : String = error_string(err) + ": Failure to remove alternate script"
			result.output.append(msg)
			printerr( msg )

	if (test_verbose or test_debug or result.retcode == RetCode.TEST_FAILED):
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


func run_test_base( instance : TestBase, result : TestResult ) -> void:
	instance._verbose = test_verbose
	instance._debug = test_debug
	@warning_ignore('redundant_await')
	await instance.run_test()
	result.retcode = instance.runcode
	result.output = instance.output


func run_play_base( instance : PlayBase, result : TestResult ) -> void:
	instance._verbose = test_verbose
	instance._debug = test_debug
	@warning_ignore('redundant_await')
	await instance.run_test()
	result.retcode = instance.runcode
	result.output = instance.output


func re_write( orig_path : String) -> String:
	var orig : Dictionary = {
		"dir":orig_path.get_base_dir(),
		"name":orig_path.get_file().get_basename()
	}
	var alt_path := "{dir}/{name}_alt.gd".format(orig)

	var orig_file := FileAccess.open(orig_path, FileAccess.READ)
	if not orig_file.is_open():
		printerr("Failed to open file: ", orig_path)
		return ""

	# skip the first three lines.
	for i : int in 3:
		var _line : String = orig_file.get_line()

	var alt_file := FileAccess.open( alt_path, FileAccess.WRITE)
	var header_replacement : String = "# This script is modified automatically to work in play mode.
extends PlayBase\n"
	if not alt_file.store_string(header_replacement):
		printerr( "Failed to write to script alternate")
		orig_file.close()
		alt_file.close()
		return ""


	while not orig_file.eof_reached():
		var line : String = orig_file.get_line()
		if not alt_file.store_string(line + "\n"):
			printerr( "Failed to write to script alternate")
			orig_file.close()
			alt_file.close()
			return ""

	orig_file.close()
	alt_file.close()
	return alt_path


#                       ████████ ██████  ███████ ███████                       #
#                          ██    ██   ██ ██      ██                            #
#                          ██    ██████  █████   █████                         #
#                          ██    ██   ██ ██      ██                            #
#                          ██    ██   ██ ███████ ███████                       #
func                        __________TREE___________              ()->void:pass

func add_action_row(
			test_def : TestDef,
			filename : String,
			parent_item : TreeItem
			) -> void:
	var item : TreeItem = parent_item.create_child()
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
	var _top_item : TreeItem = tests_tree.create_item()
	_top_item.set_text(0,"Tests")

	# Add the rows
	for test_def : TestDef in test_list:
		# Add Folder name
		var folder_item : TreeItem = tests_tree.create_item()
		folder_item.set_text( 0, test_def.name )
		folder_item.set_selectable(1, false )

		# Add script items
		for file : String in test_def.test_scripts:
			add_action_row( test_def, file, folder_item )

	update_stats()


func update_tree_item(
			item : TreeItem,
			label : String = "PENDING",
			color : Color = color_TEST
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

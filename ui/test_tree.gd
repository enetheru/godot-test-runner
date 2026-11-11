@tool
extends Tree

## The test list. The panel rebuilds it and starts runs.
## Clicks come back as signals.

const TestRows = preload( "uid://dk7mtestrows1" )
const TestDef = TestRows.TestDef
const Icons = preload( "../res/icons.tres" )

const RUN_ICON_SIZE:Vector2i = Vector2i( 24, 24 )

enum Column { TEST, STATUS }

enum RunKind { EDITORSCRIPT, PLAY, DEBUG, RELEASE, HEADLESS }

enum Mark { NONE, RUN, OK, WARN, FAIL }

enum Status { PENDING, INPROGRESS, OK, WARNING, FAILED }

## A row can hold more than one of these.
enum RowKind {
	CASE = 1,
	TREE = 2,
	EDITOR = 4,
}

## In [enum RunKind] order. [code]launch[/code] is a [enum TR_CaseSession.Launch] id.
const RUN:Array[Dictionary] = [
	{
		&"icon": &"SCRIPT_TEXT_PLAY",
		&"tip": "EditorScript",
		&"launch": TR_CaseSession.Launch.EDITORSCRIPT,
	},
	{
		&"icon": &"PLAY_BOX_EDIT_OUTLINE",
		&"tip": "Play Editor",
		&"launch": TR_CaseSession.Launch.PLAY_EDITOR,
	},
	{
		&"icon": &"BUG_PLAY",
		&"tip": "Play template_debug",
		&"launch": TR_CaseSession.Launch.PLAY_DEBUG,
	},
	{
		&"icon": &"MOVIE_PLAY",
		&"tip": "Play template_release",
		&"launch": TR_CaseSession.Launch.PLAY_RELEASE,
	},
	{
		&"icon": &"COG_PLAY",
		&"tip": "Headless -s",
		&"launch": TR_CaseSession.Launch.HEADLESS,
	},
]


# ██████  ██████   ██████  ██████  ███████ ██████  ████████ ██ ███████ ███████ #
# ██   ██ ██   ██ ██    ██ ██   ██ ██      ██   ██    ██    ██ ██      ██      #
# ██████  ██████  ██    ██ ██████  █████   ██████     ██    ██ █████   ███████ #
# ██      ██   ██ ██    ██ ██      ██      ██   ██    ██    ██ ██           ██ #
# ██      ██   ██  ██████  ██      ███████ ██   ██    ██    ██ ███████ ███████ #
func                        ________PROPERTIES_______              ()->void:pass

# Which run columns are shown. The panel sets this before a rebuild.
var _kind_ids:Array[int] = []

# Filled when the rows are built, and as results arrive.
var _row_kind:Dictionary[String, int] = {}
var _kind_mark:Dictionary = {}

# Selected file rows. Clicks add to it and a rebuild clears it.
var _selection:Dictionary = {}

# Header icons. Laid out once the tree has a size.
var _kind_headers:Array[TextureRect] = []

# Deferred layout attempts while the header band has no width yet.
var _header_layout_waits:int = 0

# Extra layouts after the first successful one, so a late resize settles.
var _header_settle:int = 0

# Unfold and fold, in that order. Laid out on the Test header.
var _fold_buttons:Array[TextureButton] = []

# True while every branch is being opened or closed. The stripe runs once at the end.
var _folding:bool = false


#            ███████ ██  ██████  ███    ██  █████  ██      ███████             #
#            ██      ██ ██       ████   ██ ██   ██ ██      ██                  #
#            ███████ ██ ██   ███ ██ ██  ██ ███████ ██      ███████             #
#                 ██ ██ ██    ██ ██  ██ ██ ██   ██ ██           ██             #
#            ███████ ██  ██████  ██   ████ ██   ██ ███████ ███████             #
func                        _________SIGNALS_________              ()->void:pass

signal run_requested( item:TreeItem, kind_id:int )
signal context_menu_requested( item:TreeItem, at:Vector2 )
signal file_picked( item:TreeItem )


#             ███████ ██    ██ ███████ ███    ██ ████████ ███████              #
#             ██      ██    ██ ██      ████   ██    ██    ██                   #
#             █████   ██    ██ █████   ██ ██  ██    ██    ███████              #
#             ██       ██  ██  ██      ██  ██ ██    ██         ██              #
#             ███████   ████   ███████ ██   ████    ██    ███████              #
func                        __________EVENTS_________              ()->void:pass

func _on_multi_selected( item:TreeItem, _column:int, selected:bool ) -> void:
	if selected:
		_selection[item] = true
		return
	@warning_ignore( "return_value_discarded" )
	_selection.erase( item )


func _on_gui_input( event:InputEvent ) -> void:
	if not event is InputEventMouseButton:
		return
	var click:InputEventMouseButton = event
	if not click.pressed:
		return
	var item:TreeItem = get_item_at_position( click.position )
	if item == null:
		return
	if click.button_index == MOUSE_BUTTON_RIGHT:
		context_menu_requested.emit( item, click.global_position )
		accept_event()
		return
	if click.button_index != MOUSE_BUTTON_LEFT or not is_file_item( item ):
		return
	var column:int = get_column_at_position( click.position )
	if column >= Column.size():
		var kind:int = column - Column.size()
		if kind_allows( _launch_of( kind ), item ):
			run_requested.emit( item, _launch_of( kind ) )
			accept_event()
		return
	file_picked.emit( item )


func _on_collapsed( _item:TreeItem ) -> void:
	if _folding:
		return
	_stripe_tree()


func _on_unfold() -> void:
	_fold_all( false )


func _on_fold() -> void:
	_fold_all( true )


#      ██████  ██    ██ ███████ ██████  ██████  ██ ██████  ███████ ███████     #
#     ██    ██ ██    ██ ██      ██   ██ ██   ██ ██ ██   ██ ██      ██          #
#     ██    ██ ██    ██ █████   ██████  ██████  ██ ██   ██ █████   ███████     #
#     ██    ██  ██  ██  ██      ██   ██ ██   ██ ██ ██   ██ ██           ██     #
#      ██████    ████   ███████ ██   ██ ██   ██ ██ ██████  ███████ ███████     #
func                        ________OVERRIDES________              ()->void:pass

func _ready() -> void:
	_listen( gui_input, _on_gui_input )
	_listen( multi_selected, _on_multi_selected )
	_listen( resized, _layout_kind_headers )
	_listen( item_collapsed, _on_collapsed )
	_ensure_kind_headers()
	_ensure_fold_buttons()
	if is_part_of_edited_scene():
		_show_edit_samples()


func _notification( what:int ) -> void:
	if what != NOTIFICATION_THEME_CHANGED or not is_node_ready():
		return
	_fit_result_columns()
	_layout_kind_headers()
	_stripe_tree()


#         ███    ███ ███████ ████████ ██   ██  ██████  ██████  ███████         #
#         ████  ████ ██         ██    ██   ██ ██    ██ ██   ██ ██              #
#         ██ ████ ██ █████      ██    ███████ ██    ██ ██   ██ ███████         #
#         ██  ██  ██ ██         ██    ██   ██ ██    ██ ██   ██      ██         #
#         ██      ██ ███████    ██    ██   ██  ██████  ██████  ███████         #
func                        _________METHODS_________              ()->void:pass

## [param kind_ids] are the checked runs. An empty list hides runnable rows in the editor.
func apply_filter( pattern:String, kind_ids:Array[int] ) -> void:
	_kind_ids = kind_ids
	var root:TreeItem = get_root()
	if root == null:
		return
	var _shown:bool = _filter_item( root, _list_glob( pattern ) )
	_stripe_tree()

#region List - Replace the tree and read which files are picked.
#MARK: List
func                        __List___________________              ()->void:pass
# │ _    _    _
# │| |  (_)__| |_
# │| |__| (_-<  _|
# │|____|_/__/\__|
# ╰────────────────

## Replace the rows with [param defs]. Marks already stored stay.
func rebuild( defs:Array ) -> void:
	_row_kind.clear()
	_selection.clear()
	clear()
	columns = _run_column( RunKind.size() )
	scroll_horizontal_enabled = true
	set_column_title( Column.TEST, "Test" )
	set_column_expand( Column.TEST, true )
	set_column_title( Column.STATUS, "Status" )
	set_column_expand( Column.STATUS, false )
	for kind:int in RunKind.size():
		var column:int = _run_column( kind )
		set_column_title( column, "" )
		set_column_title_tooltip_text( column, _tip( kind ) )
		set_column_expand( column, false )
		set_column_clip_content( column, false )
	_fit_result_columns()
	_header_settle = 0
	_layout_kind_headers.call_deferred()

	var top:TreeItem = create_item()
	top.set_text( 0, "Tests" )
	_lock_result_columns( top )
	var root_item:TreeItem = get_root()
	for def:Variant in defs:
		if def is TestDef:
			var branch:TestDef = def
			_add_folder_branch( branch, root_item )


func is_file_item( item:TreeItem ) -> bool:
	if item == null:
		return false
	var meta:Variant = item.get_metadata( 0 )
	return meta is TestDef and str( item.get_text( 0 ) ).ends_with( ".gd" )


func row_path( item:TreeItem ) -> String:
	var meta:Variant = item.get_metadata( 0 )
	if not meta is TestDef:
		return ""
	var test_def:TestDef = meta
	if is_file_item( item ):
		return test_def.folder_path.path_join( item.get_text( 0 ) )
	return test_def.folder_path


func files_under( item:TreeItem ) -> Array[TreeItem]:
	var out:Array[TreeItem] = []
	if item == null or not item.visible:
		return out
	if is_file_item( item ):
		out.append( item )
	for child:TreeItem in item.get_children():
		out.append_array( files_under( child ) )
	return out


func selected_files() -> Array[TreeItem]:
	var files:Array[TreeItem] = []
	var root:TreeItem = get_root()
	if root == null:
		return files
	var picked:Array[TreeItem] = _live_selection()
	if picked.is_empty() or root in picked:
		picked = root.get_children()
	for item:TreeItem in picked:
		if not is_instance_valid( item ):
			continue
		files.append_array( files_under( item ) )
	return files

#endregion List

#region Launch - Which files a run kind may start.
#MARK: Launch
func                        __Launch_________________              ()->void:pass
# │ _                      _
# │| |   __ _ _  _ _ _  __| |_
# │| |__/ _` | || | ' \/ _| ' \
# │|____\__,_|\_,_|_||_\__|_||_|
# ╰──────────────────────────────

func kind_allows( kind_id:int, item:TreeItem ) -> bool:
	var host:int = TR_CaseSession.launch_host( kind_id )
	if host == TR_CaseSession.Host.EDITOR:
		return true
	var flags:int = _row_flags( row_path( item ) )
	if ( flags & RowKind.CASE ) == 0:
		return false
	if ( flags & RowKind.EDITOR ) != 0:
		return false
	if host == TR_CaseSession.Host.SCRIPT:
		return ( flags & RowKind.TREE ) == 0
	return true


func paths_for_kind( kind_id:int, files:Array[TreeItem] ) -> PackedStringArray:
	var paths:PackedStringArray = PackedStringArray()
	for file_item:TreeItem in files:
		if not is_instance_valid( file_item ):
			continue
		if not kind_allows( kind_id, file_item ):
			continue
		var path:String = row_path( file_item )
		if path.is_empty():
			continue
		if paths.append( path ):
			push_error( "test_tree.paths_for_kind: append failed" )
			break
	return paths


func case_paths_of( files:Array[TreeItem] ) -> PackedStringArray:
	var paths:PackedStringArray = PackedStringArray()
	for file_item:TreeItem in files:
		if not is_instance_valid( file_item ):
			continue
		var path:String = row_path( file_item )
		if not TR_CaseSession.is_case_path( path ):
			continue
		if paths.append( path ):
			push_error( "test_tree.case_paths_of: append failed" )
			break
	return paths

#endregion Launch

#region Marks - Store a mark and paint the row.
#MARK: Marks
func                        __Marks__________________              ()->void:pass
# │ __  __          _
# │|  \/  |__ _ _ _| |__ ___
# │| |\/| / _` | '_| / /(_-<
# │|_|  |_\__,_|_| |_\_\/__/
# ╰──────────────────────────

func clear_marks() -> void:
	_kind_mark.clear()
	_repaint_files( get_root() )


func remember( path:String, host_id:int, mark:Mark ) -> void:
	var kind:int = _kind_for_host( host_id )
	if path == "" or kind < 0:
		return
	var row:Dictionary = {}
	if _kind_mark.has( path ):
		row = _kind_mark[path]
	row[kind] = mark
	_kind_mark[path] = row


func paint_kind( item:TreeItem, host_id:int ) -> void:
	var kind:int = _kind_for_host( host_id )
	if kind < 0 or item == null:
		return
	_set_run_button( item, kind, _stored_mark( row_path( item ), kind ) )


func repaint_path( path:String ) -> void:
	var item:TreeItem = _file_by_path( path )
	if item == null:
		return
	_paint_run_cells( item )


func set_status( item:TreeItem, status:Status = Status.PENDING ) -> void:
	if item == null:
		return
	item.set_text( Column.STATUS, status_text( status ) )
	item.clear_custom_color( 0 )
	if status == Status.PENDING:
		item.clear_custom_color( Column.STATUS )
		return
	item.set_custom_color( Column.STATUS, _status_color( status ) )


func status_text( status:Status ) -> String:
	return str( Status.keys()[status] )

#endregion Marks

#       ██ ███    ██ ████████ ███████ ██████  ███    ██  █████  ██             #
#       ██ ████   ██    ██    ██      ██   ██ ████   ██ ██   ██ ██             #
#       ██ ██ ██  ██    ██    █████   ██████  ██ ██  ██ ███████ ██             #
#       ██ ██  ██ ██    ██    ██      ██   ██ ██  ██ ██ ██   ██ ██             #
#       ██ ██   ████    ██    ███████ ██   ██ ██   ████ ██   ██ ███████        #
func                        ________INTERNAL_________              ()->void:pass

func _listen( sig:Signal, method:Callable ) -> void:
	if sig.is_connected( method ):
		return
	var err:int = sig.connect( method )
	if err != OK:
		push_error( "test_tree: connect failed (%s)" % error_string( err ) )


func _icon( icon_name:StringName ) -> Texture2D:
	return Icons.at_size( Icons.get_tex( icon_name ), RUN_ICON_SIZE )


func _run_column( kind:int ) -> int:
	return Column.size() + kind


func _launch_of( kind:int ) -> int:
	var launch:Variant = RUN[kind][&"launch"]
	if launch is int:
		return launch
	return TR_CaseSession.Launch.EDITORSCRIPT


func _tip( kind:int ) -> String:
	return str( RUN[kind][&"tip"] )


func _kind_icon( kind:int ) -> StringName:
	var icon:Variant = RUN[kind][&"icon"]
	if icon is StringName:
		return icon
	return &""


func _kind_for_host( host_id:int ) -> int:
	for kind:int in RunKind.size():
		if _launch_of( kind ) == host_id:
			return kind
	return -1

#region Headers - Kind icons and fold buttons on the title band.
#MARK: Headers
func                        __Headers________________              ()->void:pass
# │ _  _             _
# │| || |___ __ _ __| |___ _ _ ___
# │| __ / -_) _` / _` / -_) '_(_-<
# │|_||_\___\__,_\__,_\___|_| /__/
# ╰────────────────────────────────

func _ensure_kind_headers() -> void:
	if _kind_headers.size() == RunKind.size():
		return
	for old:TextureRect in _kind_headers:
		if is_instance_valid( old ):
			old.queue_free()
	_kind_headers.clear()
	for kind:int in RunKind.size():
		var rect := TextureRect.new()
		rect.name = "KindHeader%d" % kind
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.texture = _icon( _kind_icon( kind ) )
		add_child( rect )
		_kind_headers.append( rect )


func _layout_kind_headers() -> void:
	if _kind_headers.size() != RunKind.size():
		return
	if get_column_width( _run_column( 0 ) ) <= 1:
		if _header_layout_waits < 8:
			_header_layout_waits += 1
			_layout_kind_headers.call_deferred()
		return
	_header_layout_waits = 0
	var panel:StyleBox = get_theme_stylebox( &"panel" )
	var top:float = 0.0
	var left:float = 0.0
	if panel != null:
		top = panel.get_margin( SIDE_TOP )
		left = panel.get_margin( SIDE_LEFT )
	var scroll:Vector2 = get_scroll()
	var band_h:float = 24.0
	var root:TreeItem = get_root()
	if root != null:
		var row:Rect2 = get_item_area_rect( root, 0 )
		if row.position.y > top + RUN_ICON_SIZE.y:
			band_h = row.position.y - top
	var x:float = left - scroll.x
	for column:int in Column.size():
		x += get_column_width( column )
	for kind:int in RunKind.size():
		var rect:TextureRect = _kind_headers[kind]
		var width:int = get_column_width( _run_column( kind ) )
		var gap:float = get_theme_constant( &"h_separation" )
		var pad_left:float = get_theme_constant( &"inner_item_margin_left" )
		var pad_right:float = get_theme_constant( &"inner_item_margin_right" )
		var box_x:float = x + gap + pad_left
		var box_w:float = width - gap - pad_left - pad_right
		rect.position = Vector2(
				box_x + ( box_w - RUN_ICON_SIZE.x ) * 0.5,
				top + ( band_h - RUN_ICON_SIZE.y ) * 0.5
		)
		rect.size = Vector2( RUN_ICON_SIZE )
		x += width
	_layout_fold_buttons( top, left, scroll, band_h )
	if _header_settle < 2:
		_header_settle += 1
		_layout_kind_headers.call_deferred()


func _ensure_fold_buttons() -> void:
	if _fold_buttons.size() == 2:
		return
	for old:TextureButton in _fold_buttons:
		if is_instance_valid( old ):
			old.queue_free()
	_fold_buttons.clear()
	_fold_buttons.append( _fold_button( "Unfold", _icon( &"UNFOLD_MORE" ), "Unfold all", _on_unfold ) )
	_fold_buttons.append( _fold_button( "Fold", _icon( &"UNFOLD_LESS" ), "Fold all", _on_fold ) )


func _fold_button( node_name:String, texture:Texture2D, tip:String, method:Callable ) -> TextureButton:
	var button := TextureButton.new()
	button.name = node_name
	button.texture_normal = texture
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.tooltip_text = tip
	button.custom_minimum_size = Vector2( RUN_ICON_SIZE )
	button.focus_mode = Control.FOCUS_NONE
	var err:int = button.pressed.connect( method )
	if err != OK:
		push_error( "test_tree._fold_button: connect failed (%s)" % error_string( err ) )
	add_child( button )
	return button


func _layout_fold_buttons( top:float, left:float, scroll:Vector2, band_h:float ) -> void:
	if _fold_buttons.size() != 2:
		return
	var gap:float = 2.0
	var edge:float = 4.0
	var width:float = get_column_width( Column.TEST )
	var fold_x:float = left - scroll.x + width - edge - RUN_ICON_SIZE.x
	var unfold_x:float = fold_x - gap - RUN_ICON_SIZE.x
	var y:float = top + ( band_h - RUN_ICON_SIZE.y ) * 0.5
	_fold_buttons[0].position = Vector2( unfold_x, y )
	_fold_buttons[1].position = Vector2( fold_x, y )
	for button:TextureButton in _fold_buttons:
		button.size = Vector2( RUN_ICON_SIZE )

#endregion Headers

#region Columns - Minimum widths for Test, Status, and the run columns.
#MARK: Columns
func                        __Columns________________              ()->void:pass
# │  ___     _
# │ / __|___| |_  _ _ __  _ _  ___
# │| (__/ _ \ | || | '  \| ' \(_-<
# │ \___\___/_|\_,_|_|_|_|_||_/__/
# ╰────────────────────────────────

func _text_px( text:String, font:Font, font_size:int ) -> int:
	if font == null:
		return text.length() * 8
	return ceili( font.get_string_size( text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size ).x )


func _column_pad( icon_width:int ) -> int:
	var outline:int = get_theme_constant( &"outline_size" )
	var inner:int = get_theme_constant( &"inner_item_margin_left" ) \
			+ get_theme_constant( &"inner_item_margin_right" )
	var separation:int = get_theme_constant( &"h_separation" )
	var extra:int = outline * 2 + inner + separation
	if icon_width <= 0:
		return extra
	return extra + icon_width + get_theme_constant( &"button_margin" )


func _widest_px( words:PackedStringArray ) -> int:
	var body_font:Font = get_theme_font( &"font" )
	var body_size:int = get_theme_font_size( &"font_size" )
	var title_font:Font = get_theme_font( &"title_button_font" )
	var title_size:int = get_theme_font_size( &"title_button_font_size" )
	var widest:int = 0
	for word:String in words:
		widest = maxi( widest, _text_px( word, body_font, body_size ) )
		widest = maxi( widest, _text_px( word, title_font, title_size ) )
	return widest


func _fit_result_columns() -> void:
	var title_words:PackedStringArray = PackedStringArray( [ "Test" ] )
	var fold_room:int = RUN_ICON_SIZE.x * 2 + 6
	set_column_custom_minimum_width( Column.TEST, _widest_px( title_words ) + fold_room + _column_pad( 0 ) )
	var status_words:PackedStringArray = Status.keys()
	if status_words.append( "Status" ):
		push_error( "test_tree: status word append failed" )
	set_column_custom_minimum_width( Column.STATUS, _widest_px( status_words ) + _column_pad( 0 ) )
	var run_width:int = get_theme_constant( &"h_separation" ) \
			+ get_theme_constant( &"inner_item_margin_left" ) \
			+ get_theme_constant( &"inner_item_margin_right" ) \
			+ RUN_ICON_SIZE.x
	for kind:int in RunKind.size():
		set_column_custom_minimum_width( _run_column( kind ), run_width )

#endregion Columns

#region Rows - Build folder and file rows, then find one.
#MARK: Rows
func                        __Rows___________________              ()->void:pass
# │ ___
# │| _ \_____ __ _____
# │|   / _ \ V  V (_-<
# │|_|_\___/\_/\_//__/
# ╰────────────────────

## Rows while this node is the scene open in the editor.
func _show_edit_samples() -> void:
	var folder := TestDef.new()
	folder.name = "Examples"
	folder.folder_path = "res://examples"
	folder.test_scripts = [ "one.gd", "two.gd" ]
	rebuild( [ folder ] )

	var files:Array[TreeItem] = files_under( get_root() )
	if not files.is_empty():
		var first:TreeItem = files[0]
		remember( row_path( first ), TR_CaseSession.Launch.EDITORSCRIPT, Mark.OK )
		paint_kind( first, TR_CaseSession.Launch.EDITORSCRIPT )
		set_status( first, Status.OK )
	if files.size() > 1:
		var second:TreeItem = files[1]
		remember( row_path( second ), TR_CaseSession.Launch.EDITORSCRIPT, Mark.FAIL )
		paint_kind( second, TR_CaseSession.Launch.EDITORSCRIPT )
		set_status( second, Status.FAILED )
	_stripe_tree()


func _add_folder_branch( test_def:TestDef, parent_item:TreeItem ) -> void:
	var folder_item:TreeItem = parent_item.create_child()
	folder_item.set_text( 0, test_def.name )
	folder_item.set_metadata( 0, test_def )
	_lock_result_columns( folder_item )
	folder_item.set_icon( 0, _icon( &"FOLDER_OPEN" ) )
	folder_item.set_icon_max_width( 0, RUN_ICON_SIZE.x )
	_add_folder_contents( test_def, folder_item )


func _add_folder_contents( test_def:TestDef, parent_item:TreeItem ) -> void:
	for child_v:Variant in test_def.children:
		if child_v is TestDef:
			var child_def:TestDef = child_v
			_add_folder_branch( child_def, parent_item )
	for file:String in test_def.test_scripts:
		_add_file_row( test_def, file, parent_item )


func _add_file_row( test_def:TestDef, filename:String, parent_item:TreeItem ) -> void:
	var item:TreeItem = parent_item.create_child()
	item.set_metadata( 0, test_def )
	item.set_text( 0, filename )
	item.set_icon( 0, Icons.get_tex( &"FILE_CODE" ) )
	_lock_result_columns( item )
	item.set_expand_right( Column.STATUS, false )
	item.set_text_overrun_behavior( Column.STATUS, TextServer.OVERRUN_TRIM_ELLIPSIS )
	_paint_run_cells( item )


func _lock_result_columns( item:TreeItem ) -> void:
	var last:int = _run_column( RunKind.size() )
	for column:int in range( Column.STATUS, last ):
		item.set_selectable( column, false )
		item.set_text_alignment( column, HORIZONTAL_ALIGNMENT_CENTER )


func _file_by_path( path:String ) -> TreeItem:
	return _file_by_path_under( get_root(), path )


func _file_by_path_under( item:TreeItem, path:String ) -> TreeItem:
	if item == null:
		return null
	if is_file_item( item ) and row_path( item ) == path:
		return item
	for child:TreeItem in item.get_children():
		var found:TreeItem = _file_by_path_under( child, path )
		if found != null:
			return found
	return null


func _live_selection() -> Array[TreeItem]:
	var live:Array[TreeItem] = []
	var stale:Array = []
	for key:Variant in _selection.keys():
		if not is_instance_valid( key ):
			stale.append( key )
			continue
		live.append( key )
	for key:Variant in stale:
		@warning_ignore( "return_value_discarded" )
		_selection.erase( key )
	return live


func _row_flags( path:String ) -> int:
	if path.is_empty():
		return 0
	if _row_kind.has( path ):
		return _row_kind[path]
	var flags:int = 0
	if TR_CaseSession.is_case_path( path ):
		flags |= RowKind.CASE
		var loaded:Resource = load( path )
		if loaded is Script:
			var scr:Script = loaded
			if TR_CaseSession.script_flag( scr, "NEEDS_TREE" ):
				flags |= RowKind.TREE
			if TR_CaseSession.script_flag( scr, "EDITOR_ONLY" ):
				flags |= RowKind.EDITOR
	_row_kind[path] = flags
	return flags

#endregion Rows

#region Filter - Show rows by name and by the checked run kinds.
#MARK: Filter
func                        __Filter_________________              ()->void:pass
# │ ___ _ _ _
# │| __(_) | |_ ___ _ _
# │| _|| | |  _/ -_) '_|
# │|_| |_|_|\__\___|_|
# ╰──────────────────────

func _list_glob( needle:String ) -> String:
	var text:String = needle.strip_edges()
	if text.is_empty():
		return ""
	if text.contains( "*" ) or text.contains( "?" ):
		return text
	return "*%s*" % text


func _filter_item( item:TreeItem, glob:String ) -> bool:
	if item == get_root():
		var any_child:bool = false
		for child:TreeItem in item.get_children():
			any_child = _filter_item( child, glob ) or any_child
		item.visible = true
		return any_child
	if is_file_item( item ):
		var named:bool = glob.is_empty() or item.get_text( 0 ).matchn( glob )
		var allowed:bool = named and _host_allows( item )
		item.visible = allowed
		return allowed
	if not glob.is_empty() and item.get_text( 0 ).matchn( glob ):
		var named_hit:bool = _filter_branch_hosts( item )
		item.visible = named_hit
		if named_hit:
			item.collapsed = false
		return named_hit
	var child_hit:bool = false
	for child:TreeItem in item.get_children():
		child_hit = _filter_item( child, glob ) or child_hit
	item.visible = child_hit
	if child_hit and not glob.is_empty():
		item.collapsed = false
	return child_hit


func _filter_branch_hosts( folder:TreeItem ) -> bool:
	var any_child:bool = false
	for child:TreeItem in folder.get_children():
		if is_file_item( child ):
			var allowed:bool = _host_allows( child )
			child.visible = allowed
			any_child = any_child or allowed
			continue
		var sub:bool = _filter_branch_hosts( child )
		child.visible = sub
		if sub:
			child.collapsed = false
		any_child = any_child or sub
	return any_child


func _host_allows( item:TreeItem ) -> bool:
	if not Engine.is_editor_hint():
		return true
	for kind_id:int in _kind_ids:
		if kind_allows( kind_id, item ):
			return true
	return false

#endregion Filter

#region Fold - Open or close every branch.
#MARK: Fold
func                        __Fold___________________              ()->void:pass
# │ ___    _    _
# │| __|__| |__| |
# │| _/ _ \ / _` |
# │|_|\___/_\__,_|
# ╰────────────────

func _fold_all( collapsed:bool ) -> void:
	var root:TreeItem = get_root()
	if root == null:
		return
	_folding = true
	root.collapsed = false
	for child:TreeItem in root.get_children():
		_fold_branch( child, collapsed )
	_folding = false
	_stripe_tree()


func _fold_branch( item:TreeItem, collapsed:bool ) -> void:
	item.collapsed = collapsed
	for child:TreeItem in item.get_children():
		_fold_branch( child, collapsed )

#endregion Fold

#region Stripe - Tint visible rows.
#MARK: Stripe
func                        __Stripe_________________              ()->void:pass
# │ ___ _       _
# │/ __| |_ _ _(_)_ __  ___
# │\__ \  _| '_| | '_ \/ -_)
# │|___/\__|_| |_| .__/\___|
# ╰──────────────|_|─────────

func _stripe_tree() -> void:
	var root:TreeItem = get_root()
	if root == null:
		return
	var tint:Color = get_theme_color( &"stripe" )
	var index:Array[int] = [0]
	_stripe_item( root, tint, index )


func _stripe_item( item:TreeItem, tint:Color, index:Array[int] ) -> void:
	if not item.visible:
		return
	var n:int = index[0]
	index[0] = n + 1
	if n % 2 == 1:
		for column:int in columns:
			item.set_custom_bg_color( column, tint )
	else:
		for column:int in columns:
			item.clear_custom_bg_color( column )
	if item.collapsed:
		return
	for child:TreeItem in item.get_children():
		_stripe_item( child, tint, index )

#endregion Stripe

#region Results - Paint the stored mark and the status word.
#MARK: Results
func                        __Results________________              ()->void:pass
# │ ___             _ _
# │| _ \___ ____  _| | |_ ___
# │|   / -_|_-< || | |  _(_-<
# │|_|_\___/__/\_,_|_|\__/__/
# ╰───────────────────────────

func _repaint_files( item:TreeItem ) -> void:
	if item == null:
		return
	if is_file_item( item ):
		_paint_run_cells( item )
	for child:TreeItem in item.get_children():
		_repaint_files( child )


func _paint_run_cells( item:TreeItem ) -> void:
	var path:String = row_path( item )
	set_status( item, _status_for( path ) )
	for kind:int in RunKind.size():
		_set_run_button( item, kind, _stored_mark( path, kind ) )


func _stored_mark( path:String, kind:int ) -> int:
	if not _kind_mark.has( path ):
		return Mark.NONE
	var row:Dictionary = _kind_mark[path]
	if not row.has( kind ):
		return Mark.NONE
	return row[kind]


func _status_for( path:String ) -> Status:
	var any:bool = false
	var failed:bool = false
	var warn:bool = false
	var running:bool = false
	if _kind_mark.has( path ):
		var row:Dictionary = _kind_mark[path]
		for mark:int in row.values():
			if mark == Mark.NONE:
				continue
			any = true
			if mark == Mark.RUN:
				running = true
			elif mark == Mark.FAIL:
				failed = true
			elif mark == Mark.WARN:
				warn = true
	if running:
		return Status.INPROGRESS
	if not any:
		return Status.PENDING
	if failed:
		return Status.FAILED
	if warn:
		return Status.WARNING
	return Status.OK


func _set_run_button( item:TreeItem, kind:int, mark:Mark ) -> void:
	var column:int = _run_column( kind )
	var tip:String = _tip( kind )
	if not kind_allows( _launch_of( kind ), item ):
		var minus:Texture2D = _icon( &"MINUS" )
		if minus == null:
			item.set_cell_mode( column, TreeItem.CELL_MODE_STRING )
			item.set_text( column, "-" )
			return
		var unavailable:String = "%s is not available for this test" % tip
		_put_icon( item, column, minus, unavailable, Color( 1, 1, 1, 0.5 ) )
		return
	var tex:Texture2D = _icon( _kind_icon( kind ) )
	var color:Color = Color( 1, 1, 1, 0.45 )
	match mark:
		Mark.OK:
			tex = _icon( &"CHECK" )
			color = _status_color( Status.OK )
		Mark.WARN:
			tex = _icon( &"CHECK" )
			color = _status_color( Status.WARNING )
		Mark.FAIL:
			tex = _icon( &"CLOSE" )
			color = _status_color( Status.FAILED )
		Mark.RUN:
			color = _status_color( Status.INPROGRESS )
			tip = "Running %s" % tip
		_:
			tip = "Run %s" % tip
	if tex == null:
		return
	_put_icon( item, column, tex, tip, color )


## Cell icon, centered in the column the stripe already paints.
func _put_icon( item:TreeItem, column:int, tex:Texture2D, tip:String, color:Color ) -> void:
	while item.get_button_count( column ) > 0:
		item.erase_button( column, 0 )
	item.set_cell_mode( column, TreeItem.CELL_MODE_ICON )
	item.set_text( column, "" )
	item.set_icon( column, tex )
	item.set_icon_max_width( column, RUN_ICON_SIZE.x )
	item.set_icon_modulate( column, color )
	item.set_tooltip_text( column, tip )


func _status_color( status:Status ) -> Color:
	var item:StringName = &"font_color"
	match status:
		Status.OK:
			item = &"result_ok"
		Status.WARNING:
			item = &"result_warning"
		Status.FAILED:
			item = &"result_failed"
		Status.INPROGRESS:
			item = &"result_progress"
	return get_theme_color( item )

#endregion Results

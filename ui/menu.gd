@tool
extends EditorContextMenuPlugin

## Run Case With submenu. FileSystem dock, script tabs, and the test panel.
##
## EditorScript runs in this process. Play launches the player scene on the
## editor binary, or on a template binary with the reused pack. Headless -s
## starts the editor executable with `-s` and waits for its line. The
## code-editor slot stays empty. Scripts and folders under the configured
## cases folder are the cases. A folder runs every case script inside it.

const CaseSessionScript = preload( "uid://blrcpfnrs606p" )
const PlayPack = preload( "uid://bmt02dy5hnmht" )
const TR_Opts = preload( "uid://c3rwpcm55iy6r" )

const PLAYER_SCENE := "res://addons/enetheru.test-runner/runner/player/player.tscn"
const SCRIPT_HOST := "res://addons/enetheru.test-runner/runner/script_host.gd"


# ██████  ██████   ██████  ██████  ███████ ██████  ████████ ██ ███████ ███████ #
# ██   ██ ██   ██ ██    ██ ██   ██ ██      ██   ██    ██    ██ ██      ██      #
# ██████  ██████  ██    ██ ██████  █████   ██████     ██    ██ █████   ███████ #
# ██      ██   ██ ██    ██ ██      ██      ██   ██    ██    ██ ██           ██ #
# ██      ██   ██  ██████  ██      ███████ ██   ██    ██    ██ ███████ ███████ #
func                        ________PROPERTIES_______              ()->void:pass

# The plugin and the panel assign these before the menu is used.

## Context slot. FileSystem unless the plugin assigns another.
var slot: EditorContextMenuPlugin.ContextMenuSlot = EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM

## EditorScript row calls this instead of the case walk.
## The argument is the picked case paths.
var editor_runner: Callable

## Called with true while at least one set is walking.
static var set_changed: Callable

# A walking set writes these.

## True when the current set should stop after the script already running.
static var halt_set: bool = false

## How many case sets are walking. The panel reads this for the Run button.
static var set_count: int = 0

# The popup fills these.

# Paths the popup was built for.
var _picked: PackedStringArray = PackedStringArray()

# The menu parents this after _popup_menu returns. A local would be the only holder until then.
var _context_popup: PopupMenu

# Session for the walk that is running.
var _live: TR_CaseSession


#             ███████ ██    ██ ███████ ███    ██ ████████ ███████              #
#             ██      ██    ██ ██      ████   ██    ██    ██                   #
#             █████   ██    ██ █████   ██ ██  ██    ██    ███████              #
#             ██       ██  ██  ██      ██  ██ ██    ██         ██              #
#             ███████   ████   ███████ ██   ████    ██    ███████              #
func                        __________EVENTS_________              ()->void:pass

func _on_method( id: int ) -> void:
	var paths := _picked.duplicate()
	match id:
		TR_CaseSession.Launch.EDITORSCRIPT:
			# Hide already queue_frees this popup. Awaiting in this callback
			# ends that walk when the first script returns.
			if editor_runner.is_valid():
				editor_runner.call_deferred( paths )
			else:
				Callable( self, &"_run_editor" ).call_deferred( paths )
		TR_CaseSession.Launch.HEADLESS:
			_run_script_host( paths )


func _on_play( id: int ) -> void:
	var paths := _picked.duplicate()
	match id:
		TR_CaseSession.Launch.PLAY_EDITOR:
			_run_play( paths )
		TR_CaseSession.Launch.PLAY_DEBUG:
			_run_template( paths, true )
		TR_CaseSession.Launch.PLAY_RELEASE:
			_run_template( paths, false )


#      ██████  ██    ██ ███████ ██████  ██████  ██ ██████  ███████ ███████     #
#     ██    ██ ██    ██ ██      ██   ██ ██   ██ ██ ██   ██ ██      ██          #
#     ██    ██ ██    ██ █████   ██████  ██████  ██ ██   ██ █████   ███████     #
#     ██    ██  ██  ██  ██      ██   ██ ██   ██ ██ ██   ██ ██           ██     #
#      ██████    ████   ███████ ██   ██ ██   ██ ██ ██████  ███████ ███████     #
func                        ________OVERRIDES________              ()->void:pass

func _popup_menu( paths: PackedStringArray ) -> void:
	var popup := make_run_menu( paths )
	if popup == null:
		return
	if is_instance_valid( _context_popup ) and _context_popup.get_parent() == null:
		_context_popup.queue_free()
	_context_popup = popup
	add_context_submenu_item( "Run Case With", popup )


#         ███    ███ ███████ ████████ ██   ██  ██████  ██████  ███████         #
#         ████  ████ ██         ██    ██   ██ ██    ██ ██   ██ ██              #
#         ██ ████ ██ █████      ██    ███████ ██    ██ ██   ██ ███████         #
#         ██  ██  ██ ██         ██    ██   ██ ██    ██ ██   ██      ██         #
#         ██      ██ ███████    ██    ██   ██  ██████  ██████  ███████         #
func                        _________METHODS_________              ()->void:pass

static func begin_set() -> void:
	set_count += 1
	_emit_set_changed()


static func end_set() -> void:
	set_count = maxi( set_count - 1, 0 )
	if set_count == 0:
		halt_set = false
	_emit_set_changed()


func make_run_menu( paths: PackedStringArray, title: String = "" ) -> PopupMenu:
	var cases := _case_paths_in( paths )
	if cases.is_empty():
		if not editor_runner.is_valid():
			return null
		return _editor_item_menu( title )

	_picked = cases
	var popup := PopupMenu.new()
	if not title.is_empty():
		popup.add_separator( title )
	var play := PopupMenu.new()
	play.add_item( "Editor", TR_CaseSession.Launch.PLAY_EDITOR )
	play.add_item( "template_debug", TR_CaseSession.Launch.PLAY_DEBUG )
	play.add_item( "template_release", TR_CaseSession.Launch.PLAY_RELEASE )
	var play_err := play.id_pressed.connect( _on_play )
	if play_err != OK:
		push_error( "menu.make_run_menu: play connect failed (%s)" % error_string( play_err ) )
	popup.add_item( "EditorScript", TR_CaseSession.Launch.EDITORSCRIPT )
	popup.add_submenu_node_item( "Play", play )
	popup.add_item( "Headless -s", TR_CaseSession.Launch.HEADLESS )
	var err := popup.id_pressed.connect( _on_method )
	if err != OK:
		push_error( "menu.make_run_menu: connect failed (%s)" % error_string( err ) )
	return popup


func run_path( path: String ) -> void:
	var loaded: Resource = load( path )
	if not loaded is Script:
		_live = CaseSessionScript.new()
		_live.host = CaseSessionScript.Host.EDITOR
		_live.refuse( "not a script", path )
		_report()
		return

	var scr: Script = loaded
	await run_script( scr )


func run_script( scr: Script ) -> void:
	var tree: SceneTree = EditorInterface.get_base_control().get_tree()
	_live = CaseSessionScript.new()
	_live.host = CaseSessionScript.Host.EDITOR
	_live.attach_tree( tree )

	var case: TR_Case = _live.instantiate( scr )
	if case == null:
		_live.refuse( "not a case", scr.resource_path )
		_report()
		return

	await _live.run_await( case )
	_report()


## Play targets and Headless. The panel walks EditorScript itself.
## The report file receives one `case ` line per script.
func launch( id: int, paths: PackedStringArray ) -> void:
	CaseSessionScript.clear_report()
	OS.set_environment( CaseSessionScript.REPORT_ENV, CaseSessionScript.report_file() )
	match id:
		TR_CaseSession.Launch.PLAY_EDITOR:
			_run_play( paths )
		TR_CaseSession.Launch.PLAY_DEBUG:
			_run_template( paths, true )
		TR_CaseSession.Launch.PLAY_RELEASE:
			_run_template( paths, false )
		TR_CaseSession.Launch.HEADLESS:
			_run_script_host( paths )
	OS.unset_environment( CaseSessionScript.REPORT_ENV )


#       ██ ███    ██ ████████ ███████ ██████  ███    ██  █████  ██             #
#       ██ ████   ██    ██    ██      ██   ██ ████   ██ ██   ██ ██             #
#       ██ ██ ██  ██    ██    █████   ██████  ██ ██  ██ ███████ ██             #
#       ██ ██  ██ ██    ██    ██      ██   ██ ██  ██ ██ ██   ██ ██             #
#       ██ ██   ████    ██    ███████ ██   ██ ██   ████ ██   ██ ███████        #
func                        ________INTERNAL_________              ()->void:pass

func _editor_item_menu( title: String ) -> PopupMenu:
	_picked = PackedStringArray()
	var popup := PopupMenu.new()
	if not title.is_empty():
		popup.add_separator( title )
	popup.add_item( "EditorScript", TR_CaseSession.Launch.EDITORSCRIPT )
	var err := popup.id_pressed.connect( _on_method )
	if err != OK:
		push_error( "menu._editor_item_menu: connect failed (%s)" % error_string( err ) )
	return popup


func _run_editor( paths: PackedStringArray ) -> void:
	begin_set()
	for path: String in paths:
		if halt_set:
			break
		await run_path( path )
	end_set()


static func _emit_set_changed() -> void:
	if set_changed.is_valid():
		set_changed.call( set_count > 0 )


func _run_play( paths: PackedStringArray ) -> void:
	OS.set_environment( TR_CaseSession.PATH_ENV, ";".join( paths ) )
	EditorInterface.play_custom_scene( PLAYER_SCENE )
	OS.unset_environment( TR_CaseSession.PATH_ENV )


func _run_template( paths: PackedStringArray, debug: bool ) -> void:
	var opts: TR_Opts = TR_Opts.shared() as TR_Opts
	var which := "template_debug" if debug else "template_release"
	var exe := opts.template_debug if debug else opts.template_release
	if exe == "" or not FileAccess.file_exists( exe ):
		_toast( "Set %s" % which )
		return

	var pack := str( PlayPack.ensure( debug, PLAYER_SCENE ) )
	if pack == "":
		_toast( "Play pack export failed" )
		return

	var args := PackedStringArray()
	args = _arg( args, "--main-pack" )
	args = _arg( args, pack )
	args = _arg( args, "--" )
	for path: String in paths:
		args = _arg( args, path )

	var output: Array = []
	var code := OS.execute( exe, args, output, true )
	var reported := false
	for entry: Variant in output:
		var text := str( entry ).strip_edges()
		if not text.begins_with( "case " ):
			continue
		reported = true
		print( text )
		_toast( text )

	if reported:
		return
	for entry: Variant in output:
		var text := str( entry ).strip_edges()
		if text != "":
			print( text )
	_toast( "%s exit %d" % [ which, code ] )


func _run_script_host( paths: PackedStringArray ) -> void:
	var args := PackedStringArray()
	args = _arg( args, "--headless" )
	args = _arg( args, "--path" )
	args = _arg( args, ProjectSettings.globalize_path( "res://" ) )
	args = _arg( args, "-s" )
	args = _arg( args, SCRIPT_HOST )
	args = _arg( args, "--" )
	for path: String in paths:
		args = _arg( args, path )

	var output: Array = []
	var code := OS.execute( OS.get_executable_path(), args, output, true )
	var reported := false
	for entry: Variant in output:
		var text := str( entry ).strip_edges()
		if not text.begins_with( "case " ):
			continue
		reported = true
		print( text )
		_toast( text )

	if reported:
		return
	_toast( "script host exit %d" % code )


func _arg( args: PackedStringArray, item: String ) -> PackedStringArray:
	# append returns the Error. OK is 0, so false means the argument was stored.
	if args.append( item ):
		push_error( "menu._arg: append failed" )
	return args


func _case_paths_in( paths: PackedStringArray ) -> PackedStringArray:
	var cases := PackedStringArray()
	for path: String in paths:
		var trimmed := path.trim_suffix( "/" )
		if trimmed.ends_with( ".gd" ):
			if _in_case_root( trimmed ) and TR_CaseSession.is_case_path( trimmed ):
				cases = _take_case( cases, trimmed )
			continue
		if _in_case_root( trimmed ):
			cases = _collect_cases( trimmed, cases )
	return cases


func _in_case_root( path: String ) -> bool:
	var root: String = TR_Opts.cases_root()
	return path == root or path.begins_with( root + "/" )


func _collect_cases( dir_path: String, cases: PackedStringArray ) -> PackedStringArray:
	var files := DirAccess.get_files_at( dir_path )
	files.sort()
	for file_name: String in files:
		if not file_name.ends_with( ".gd" ):
			continue
		var path := dir_path.path_join( file_name )
		if TR_CaseSession.is_case_path( path ):
			cases = _take_case( cases, path )

	var folders := DirAccess.get_directories_at( dir_path )
	folders.sort()
	for folder: String in folders:
		if folder.begins_with( "." ):
			continue
		cases = _collect_cases( dir_path.path_join( folder ), cases )
	return cases


func _take_case( cases: PackedStringArray, path: String ) -> PackedStringArray:
	if cases.has( path ):
		return cases
	return _arg( cases, path )


func _report() -> void:
	var text := _live.line()
	print( text )
	_toast( text )


func _toast( text: String ) -> void:
	if DisplayServer.get_name() == "headless":
		return
	EditorInterface.get_editor_toaster().push_toast( text )

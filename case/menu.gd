@tool
extends EditorContextMenuPlugin

## Run Case With submenu. FileSystem dock and script tabs only.
##
## EditorScript runs in this process. Play launches the player scene on the
## editor binary, or on a template binary with the reused pack. Headless -s
## starts the editor executable with `-s` and waits for its line. The
## code-editor slot stays empty. Scripts and folders under the configured
## cases folder are the cases. A folder runs every case script inside it.

const CaseSessionScript = preload( "CaseSession.gd" )
const PlayPack = preload( "play_pack.gd" )

const PLAYER_SCENE := "res://addons/enetheru.test-runner/case/player.tscn"
const SCRIPT_HOST := "res://addons/enetheru.test-runner/case/script_host.gd"
const PLAY_EDITOR := 10
const PLAY_DEBUG := 11
const PLAY_RELEASE := 12


# ██████  ██████   ██████  ██████  ███████ ██████  ████████ ██ ███████ ███████ #
# ██   ██ ██   ██ ██    ██ ██   ██ ██      ██   ██    ██    ██ ██      ██      #
# ██████  ██████  ██    ██ ██████  █████   ██████     ██    ██ █████   ███████ #
# ██      ██   ██ ██    ██ ██      ██      ██   ██    ██    ██ ██           ██ #
# ██      ██   ██  ██████  ██      ███████ ██   ██    ██    ██ ███████ ███████ #
func                        ________PROPERTIES_______              ()->void:pass

var slot: EditorContextMenuPlugin.ContextMenuSlot = EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM

var _live: CaseSession
var _picked: PackedStringArray = PackedStringArray()


#             ███████ ██    ██ ███████ ███    ██ ████████ ███████              #
#             ██      ██    ██ ██      ████   ██    ██    ██                   #
#             █████   ██    ██ █████   ██ ██  ██    ██    ███████              #
#             ██       ██  ██  ██      ██  ██ ██    ██         ██              #
#             ███████   ████   ███████ ██   ████    ██    ███████              #
func                        __________EVENTS_________              ()->void:pass

func _on_method( id: int ) -> void:
	var paths := _picked.duplicate()
	match id:
		CaseSession.Host.EDITOR:
			await _run_editor( paths )
		CaseSession.Host.SCRIPT:
			_run_script_host( paths )


func _on_play( id: int ) -> void:
	var paths := _picked.duplicate()
	match id:
		PLAY_EDITOR:
			_run_play( paths )
		PLAY_DEBUG:
			_run_template( paths, true )
		PLAY_RELEASE:
			_run_template( paths, false )


#      ██████  ██    ██ ███████ ██████  ██████  ██ ██████  ███████ ███████     #
#     ██    ██ ██    ██ ██      ██   ██ ██   ██ ██ ██   ██ ██      ██          #
#     ██    ██ ██    ██ █████   ██████  ██████  ██ ██   ██ █████   ███████     #
#     ██    ██  ██  ██  ██      ██   ██ ██   ██ ██ ██   ██ ██           ██     #
#      ██████    ████   ███████ ██   ██ ██   ██ ██ ██████  ███████ ███████     #
func                        ________OVERRIDES________              ()->void:pass

func _popup_menu( paths: PackedStringArray ) -> void:
	var cases := _case_paths_in( paths )
	if cases.is_empty():
		return

	_picked = cases
	var popup := PopupMenu.new()
	var play := PopupMenu.new()
	play.add_item( "Editor", PLAY_EDITOR )
	play.add_item( "template_debug", PLAY_DEBUG )
	play.add_item( "template_release", PLAY_RELEASE )
	var play_err := play.id_pressed.connect( _on_play )
	if play_err != OK:
		push_error( "menu._popup_menu: play connect failed (%s)" % error_string( play_err ) )
	popup.add_item( "EditorScript", CaseSession.Host.EDITOR )
	popup.add_submenu_node_item( "Play", play )
	popup.add_item( "Headless -s", CaseSession.Host.SCRIPT )
	var err := popup.id_pressed.connect( _on_method )
	if err != OK:
		push_error( "menu._popup_menu: connect failed (%s)" % error_string( err ) )
	add_context_submenu_item( "Run Case With", popup )


#         ███    ███ ███████ ████████ ██   ██  ██████  ██████  ███████         #
#         ████  ████ ██         ██    ██   ██ ██    ██ ██   ██ ██              #
#         ██ ████ ██ █████      ██    ███████ ██    ██ ██   ██ ███████         #
#         ██  ██  ██ ██         ██    ██   ██ ██    ██ ██   ██      ██         #
#         ██      ██ ███████    ██    ██   ██  ██████  ██████  ███████         #
func                        _________METHODS_________              ()->void:pass

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

	var case: Case = _live.instantiate( scr )
	if case == null:
		_live.refuse( "not a case", scr.resource_path )
		_report()
		return

	await _live.run_await( case )
	_report()


#       ██ ███    ██ ████████ ███████ ██████  ███    ██  █████  ██             #
#       ██ ████   ██    ██    ██      ██   ██ ████   ██ ██   ██ ██             #
#       ██ ██ ██  ██    ██    █████   ██████  ██ ██  ██ ███████ ██             #
#       ██ ██  ██ ██    ██    ██      ██   ██ ██  ██ ██ ██   ██ ██             #
#       ██ ██   ████    ██    ███████ ██   ██ ██   ████ ██   ██ ███████        #
func                        ________INTERNAL_________              ()->void:pass

func _run_editor( paths: PackedStringArray ) -> void:
	for path: String in paths:
		await run_path( path )


func _run_play( paths: PackedStringArray ) -> void:
	OS.set_environment( CaseSession.PATH_ENV, ";".join( paths ) )
	EditorInterface.play_custom_scene( PLAYER_SCENE )
	OS.unset_environment( CaseSession.PATH_ENV )


func _run_template( paths: PackedStringArray, debug: bool ) -> void:
	var opts := TestRunnerOpts.shared()
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
			if _in_case_root( trimmed ) and CaseSession.is_case_path( trimmed ):
				cases = _take_case( cases, trimmed )
			continue
		if _in_case_root( trimmed ):
			cases = _collect_cases( trimmed, cases )
	return cases


func _in_case_root( path: String ) -> bool:
	var root: String = TestRunnerOpts.cases_root()
	return path == root or path.begins_with( root + "/" )


func _collect_cases( dir_path: String, cases: PackedStringArray ) -> PackedStringArray:
	var files := DirAccess.get_files_at( dir_path )
	files.sort()
	for file_name: String in files:
		if not file_name.ends_with( ".gd" ):
			continue
		var path := dir_path.path_join( file_name )
		if CaseSession.is_case_path( path ):
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

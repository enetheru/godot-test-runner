@tool
extends RefCounted

## One pack for the play host, built from this project.
##
## The pack's main scene is the player scene. A file under [code]res://[/code]
## that is newer than the pack builds it again. The template binary stays
## outside the pack and is chosen when the pack is launched.


const _MAIN := "application/run/main_scene"
const _DIR := "user://case_play"


#                 ███████ ████████  █████  ████████ ██  ██████                 #
#                 ██         ██    ██   ██    ██    ██ ██                      #
#                 ███████    ██    ███████    ██    ██ ██                      #
#                      ██    ██    ██   ██    ██    ██ ██                      #
#                 ███████    ██    ██   ██    ██    ██  ██████                 #
func                        __________STATIC_________              ()->void:pass

## Global path of the debug or release pack. Empty when the export fails.
static func ensure( debug: bool, main_scene: String ) -> String:
	var pack := _pack_path( debug )
	var global := ProjectSettings.globalize_path( pack )
	if FileAccess.file_exists( pack ) and FileAccess.get_modified_time( pack ) >= _newest( "res://" ):
		return global

	var made := DirAccess.make_dir_recursive_absolute( ProjectSettings.globalize_path( _DIR ) )
	if made != OK and made != ERR_ALREADY_EXISTS:
		push_error( "play_pack.ensure: directory failed (%s)" % error_string( made ) )
		return ""

	if not _export( debug, global, main_scene ):
		return ""
	return global


static func _pack_path( debug: bool ) -> String:
	var leaf := "debug.pck" if debug else "release.pck"
	return _DIR.path_join( leaf )


static func _export( debug: bool, global: String, main_scene: String ) -> bool:
	if not ClassDB.class_exists( &"EditorExportPlatformWindows" ):
		push_error( "play_pack._export: Windows export platform is missing" )
		return false

	var platform := EditorExportPlatformWindows.new()
	var preset: EditorExportPreset = platform.create_preset()
	var previous: Variant = ProjectSettings.get_setting( _MAIN )
	ProjectSettings.set_setting( _MAIN, main_scene )
	var err := platform.export_pack( preset, debug, global )
	ProjectSettings.set_setting( _MAIN, previous )
	if err != OK:
		push_error( "play_pack._export: export failed (%s)" % error_string( err ) )
		return false
	return true


static func _newest( root: String ) -> int:
	var dir := DirAccess.open( root )
	if dir == null:
		return 0

	var newest := 0
	for folder: String in dir.get_directories():
		if folder.begins_with( "." ):
			continue
		var below := _newest( root.path_join( folder ) )
		if below > newest:
			newest = below

	for file_name: String in dir.get_files():
		var stamp := FileAccess.get_modified_time( root.path_join( file_name ) )
		if stamp > newest:
			newest = stamp
	return newest

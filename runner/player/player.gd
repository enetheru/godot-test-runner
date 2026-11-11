extends Node

## Play host. Run this scene and pass case paths after `--`.
##
## The tree is the game tree. Hint follows the executable, so an editor
## binary playing this scene reports hint false.

const CaseSessionScript = preload( "uid://blrcpfnrs606p" )


#      ██████  ██    ██ ███████ ██████  ██████  ██ ██████  ███████ ███████     #
#     ██    ██ ██    ██ ██      ██   ██ ██   ██ ██ ██   ██ ██      ██          #
#     ██    ██ ██    ██ █████   ██████  ██████  ██ ██   ██ █████   ███████     #
#     ██    ██  ██  ██  ██      ██   ██ ██   ██ ██ ██   ██ ██           ██     #
#      ██████    ████   ███████ ██   ██ ██   ██ ██ ██████  ███████ ███████     #
func                        ________OVERRIDES________              ()->void:pass

func _ready() -> void:
	# The root is still entering the tree. A timer added now is rejected.
	await get_tree().process_frame

	var paths: PackedStringArray = CaseSessionScript.case_paths()
	if paths.is_empty():
		var session := CaseSessionScript.new()
		session.host = CaseSessionScript.Host.PLAY
		session.refuse( "no path" )
		CaseSessionScript.report( session.line() )
		get_tree().quit()
		return

	for path: String in paths:
		await _run_path( path )
	get_tree().quit()


#       ██ ███    ██ ████████ ███████ ██████  ███    ██  █████  ██             #
#       ██ ████   ██    ██    ██      ██   ██ ████   ██ ██   ██ ██             #
#       ██ ██ ██  ██    ██    █████   ██████  ██ ██  ██ ███████ ██             #
#       ██ ██  ██ ██    ██    ██      ██   ██ ██  ██ ██ ██   ██ ██             #
#       ██ ██   ████    ██    ███████ ██   ██ ██   ████ ██   ██ ███████        #
func                        ________INTERNAL_________              ()->void:pass

func _run_path( path: String ) -> void:
	var session := CaseSessionScript.new()
	session.host = CaseSessionScript.Host.PLAY
	session.attach_tree( get_tree() )

	var loaded: Resource = load( path )
	if not loaded is GDScript:
		session.refuse( "not a script", path )
		CaseSessionScript.report( session.line() )
		return

	var scr: GDScript = loaded
	var case: TR_Case = session.instantiate( scr )
	if case == null:
		session.refuse( "not a case", path )
		CaseSessionScript.report( session.line() )
		return

	await session.run_await( case )
	CaseSessionScript.report( session.line() )

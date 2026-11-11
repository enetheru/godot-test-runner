extends MainLoop

## Script host. Point `-s` here, and pass case paths after `--`.
##
## This process has a loop and no scene tree. A case marked `NEEDS_TREE`
## is refused before its body starts.

const CaseSessionScript = preload( "uid://blrcpfnrs606p" )


# ██████  ██████   ██████  ██████  ███████ ██████  ████████ ██ ███████ ███████ #
# ██   ██ ██   ██ ██    ██ ██   ██ ██      ██   ██    ██    ██ ██      ██      #
# ██████  ██████  ██    ██ ██████  █████   ██████     ██    ██ █████   ███████ #
# ██      ██   ██ ██    ██ ██      ██      ██   ██    ██    ██ ██           ██ #
# ██      ██   ██  ██████  ██      ███████ ██   ██    ██    ██ ███████ ███████ #
func                        ________PROPERTIES_______              ()->void:pass

# TR_Case paths after `--`. _initialize reads them.
var _paths: PackedStringArray = PackedStringArray()

# Next path. _process advances it.
var _index: int = 0

# True when no case path was passed.
var _empty: bool = false


#      ██████  ██    ██ ███████ ██████  ██████  ██ ██████  ███████ ███████     #
#     ██    ██ ██    ██ ██      ██   ██ ██   ██ ██ ██   ██ ██      ██          #
#     ██    ██ ██    ██ █████   ██████  ██████  ██ ██   ██ █████   ███████     #
#     ██    ██  ██  ██  ██      ██   ██ ██   ██ ██ ██   ██ ██           ██     #
#      ██████    ████   ███████ ██   ██ ██   ██ ██ ██████  ███████ ███████     #
func                        ________OVERRIDES________              ()->void:pass

func _initialize() -> void:
	_paths = CaseSessionScript.case_paths()
	_empty = _paths.is_empty()
	if not _empty:
		return

	var session := CaseSessionScript.new()
	session.host = CaseSessionScript.Host.SCRIPT
	session.refuse( "no path" )
	CaseSessionScript.report( session.line() )


func _process( delta: float ) -> bool:
	if _empty or _index >= _paths.size():
		return true

	var path: String = _paths[ _index ]
	_index += 1
	var session := CaseSessionScript.new()
	session.host = CaseSessionScript.Host.SCRIPT
	session.attach_loop()
	session.clock.tick( delta )

	var loaded: Resource = load( path )
	if loaded is GDScript:
		var scr: GDScript = loaded
		var case: TR_Case = session.instantiate( scr )
		if case == null:
			session.refuse( "not a case", path )
		else:
			session.run_sync( case )
	else:
		session.refuse( "not a script", path )

	CaseSessionScript.report( session.line() )
	return _index >= _paths.size()

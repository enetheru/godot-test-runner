@tool
extends RefCounted

## Depth of in-flight test runs.
##
## [method enter] returns a hold. [method leave] drops it.
## [signal running_changed] fires when the depth leaves zero and when the
## last hold is gone. This script does not know about Command Server.


const _UID := "uid://c8rungatehold1"

signal running_changed( running:bool )

# Process-wide gate. shared creates it on first use.
static var _shared:RefCounted

# In-flight holds. Zero means idle.
var _depth:int = 0


static func shared() -> RefCounted:
	if _shared == null:
		var scr:GDScript = load( _UID ) as GDScript
		_shared = scr.new()
	return _shared


static func create_hold() -> Hold:
	return Hold.new( shared() )


func is_running() -> bool:
	return _depth > 0


func push() -> void:
	_depth += 1
	if _depth == 1:
		running_changed.emit( true )


func pop() -> void:
	if _depth == 0:
		return
	_depth -= 1
	if _depth == 0:
		running_changed.emit( false )


class Hold extends RefCounted:
	# Gate this hold drops on leave or when it is freed.
	var _push:Callable
	var _pop:Callable
	# False after leave. The predelete notice pops only while this is true.
	var _open:bool = true

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			if _open:
				_pop.call()


	func _init( gate:Object ) -> void:
		_push = Callable( gate, &"push" )
		_pop = Callable( gate, &"pop" )


	func open() -> void:
		if _open:
			return
		_open = true
		_push.call()


	## Pop while this hold is still alive.
	## RefCounted predelete cannot call back into this object.
	func close() -> void:
		if _open:
			_open = false
			_pop.call()

@tool
class_name RunGate
extends RefCounted

## Depth of in-flight test runs.
##
## [method enter] returns a hold. [method leave] drops it.
## [signal running_changed] fires when the depth leaves zero and when the
## last hold is gone. This script does not know about Command Server.


signal running_changed( running:bool )

static var _shared:RunGate

var _depth:int = 0


static func shared() -> RunGate:
	if _shared == null:
		_shared = RunGate.new()
	return _shared


static func enter() -> RefCounted:
	return Hold.new( shared() )


static func leave( hold:RefCounted ) -> void:
	if hold == null:
		return
	hold.call( &"close" )


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
	var _gate:RunGate
	var _open:bool = true


	func _init( gate:RunGate ) -> void:
		_gate = gate
		_gate.push()


	## Pop while this hold is still alive.
	## RefCounted predelete cannot call back into this object.
	func close() -> void:
		if not _open:
			return
		_open = false
		var gate:RunGate = _gate
		_gate = null
		if gate != null:
			gate.pop()

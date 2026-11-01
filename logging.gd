@tool
extends Object
##[codeblock lang=text]
##│ _
##│| |   ___  __ _
##│| |__/ _ \/ _` |
##│|____\___/\__, |
##╰──────────|___/───
##[/codeblock] Generic logging facade. Binds a backend's [code]trace[/code],
## [code]lvl[/code], and [code]rich[/code]. Level checks stay here.
## [code]stack[/code] is passed through and not filled. [method rich] falls
## back to [method print_rich]. [method err] and [method wrn] are [method lvl]
## at [constant Level.ERROR] and [constant Level.WARNING].
##
## No [code]class_name[/code], no autoload. The host calls
## [method set_backend] if it has a logger. Missing methods stay on the
## [Bound] fallbacks. [code]object[/code] is the identity, usually
## [code]self[/code].
##[br][color=goldenrod]TODO[/color]:


## Bitmask verbosity. Bare names are inclusive (the usual setting).
## [code]EXCLUSIVE_*[/code] is one bit, for an event check.
enum Level {
	SILENT = 0x00, ## No output.
	CRITICAL = 0x01, ## Through critical.
	ERROR = 0x03, ## Through error.
	WARNING = 0x07, ## Through warning.
	NOTICE = 0x0F, ## Through notice.
	INFO = 0x1F, ## Through info.
	DEBUG = 0x3F, ## Through debug.
	TRACE = 0x7F, ## Through trace.
	MASK = 0xFF, ## All bits.
	EXCLUSIVE_CRITICAL = 0x01, ## Critical bit.
	EXCLUSIVE_ERROR = 0x02, ## Error bit.
	EXCLUSIVE_WARNING = 0x04, ## Warning bit.
	EXCLUSIVE_NOTICE = 0x08, ## Notice bit.
	EXCLUSIVE_INFO = 0x10, ## Info bit.
	EXCLUSIVE_DEBUG = 0x20, ## Debug bit.
	EXCLUSIVE_TRACE = 0x40, ## Trace bit.
	DEFAULT = NOTICE, ## Alias of [constant NOTICE].
}

static var Names:Dictionary = {
	0x00: &"SILENT",
	0xFF: &"MASK",
	0x01: &"CRITICAL",
	0x02: &"ERROR",
	0x04: &"WARNING",
	0x08: &"NOTICE",
	0x10: &"INFO",
	0x20: &"DEBUG",
	0x40: &"TRACE",
}


## Bound backend. Created by [method set_backend].
class Bound extends RefCounted:
	const Shim = preload( "logging.gd" )

	## Local mute when [member source] has no [code]disabled[/code].
	var _disabled:bool = false
	## Live backend, or null.
	var source:Object = null
	## Fallback verbosity for [method can_log].
	var default_lvl:int = Level.DEFAULT
	## [code]trace(args, object, stack)[/code] when the backend has it.
	var fn_trace:Callable = _fallback_trace
	## [code]lvl(lvl, content, object, stack)[/code] when the backend has it.
	var fn_lvl:Callable = _fallback_lvl
	## [code]rich(lvl, text, object, stack)[/code] when the backend has it.
	var fn_rich:Callable = _fallback_rich

	## Mute. Forwards to source [code]disabled[/code] when present.
	var disabled:bool:
		get = _get_disabled,
		set = _set_disabled


	func _get_disabled() -> bool:
		if is_instance_valid( source ) \
		and &"disabled" in source:
			var flag:Variant = source.get( &"disabled" )
			if flag is bool:
				return flag
		return _disabled


	func _set_disabled( value:bool ) -> void:
		_disabled = value
		if is_instance_valid( source ) \
		and &"disabled" in source:
			source.set( &"disabled", value )


	## Point at [param p_source] and bind [code]trace[/code], [code]lvl[/code],
	## and [code]rich[/code] when those methods exist.
	func bind( p_source:Object ) -> void:
		if not is_instance_valid( p_source ):
			return
		source = p_source
		if p_source.has_method( &"trace" ):
			fn_trace = Callable( p_source, &"trace" )
		if p_source.has_method( &"lvl" ):
			fn_lvl = Callable( p_source, &"lvl" )
		if p_source.has_method( &"rich" ):
			fn_rich = Callable( p_source, &"rich" )


	## True when [param object] may emit [param what_lvl].
	func can_log( what_lvl:int, object:Object ) -> bool:
		if disabled:
			return false
		var class_lvl:int = default_lvl
		var local_lvl:int = default_lvl
		if is_instance_valid( object ):
			var variant:Variant = object.get( &"class_lvl" )
			if variant is int:
				class_lvl = variant
			variant = object.get( &"local_lvl" )
			if variant is int:
				local_lvl = variant
		var enabled:int = default_lvl | class_lvl | local_lvl
		return ( enabled & Shim.event_bit( what_lvl ) ) != 0


	## Prints [param args]. [param object] is prefixed when set.
	func _fallback_trace( args:Dictionary, _object:Object, stack:Array ) -> void:
		var frame:Dictionary = stack[-1] if not stack.is_empty() else Shim.get_stack_popped(0)[-1]
		var _args:String = "()" if args.is_empty() else "(%s)" % str( args )
		print_rich( Shim.link("{source}:{line}".format(frame), str(frame.function)) + _args )


	## Prints [param content]. The event bit chooses [method push_error],
	## [method push_warning], or [method print].
	func _fallback_lvl( p_lvl:int, content:Variant, object:Object, _stack:Array ) -> void:
		var msg:String = (str( object ) + " ") if is_instance_valid( object ) else ""

		if p_lvl < Level.DEFAULT:
			var key:Variant = Level.find_key( p_lvl )
			if key != null:
				msg += str( key ) + ": "

		if content is Array:
			var arr:Array = content
			msg += " ".join( arr.map( str ) )
		elif content is Dictionary:
			msg += JSON.stringify( content, "  " )
		else:
			msg += str(content)

		var bit:int = Shim.event_bit( p_lvl )
		if bit & (Level.EXCLUSIVE_CRITICAL | Level.EXCLUSIVE_ERROR):
			if Engine.is_editor_hint():
				printerr( msg )
			else:
				push_error( msg )
		elif bit & Level.EXCLUSIVE_WARNING:
			if Engine.is_editor_hint():
				print( msg )
			else:
				push_warning( msg )
		else:
			print_rich( msg )


	## Level already passed. Print [param text] as BBCode, with no object prefix.
	func _fallback_rich( _p_lvl:int, content:Variant, _object:Object, _stack:Array ) -> void:
		print_rich( str(content) )


## Active [Bound]. Created on first use.
static var _bound:Bound


## Current backend object (null = print fallbacks).
static var backend:Object:
	get: return _session().source


## Active [Bound], creating an empty one if needed.
static func _session() -> Bound:
	if _bound == null:
		_bound = Bound.new()
	return _bound


## Allow log output.
static func enable() -> void:
	_session().disabled = false


## Mute all log output.
static func disable() -> void:
	_session().disabled = true


## True when output is muted.
static func is_disabled() -> bool:
	return _session().disabled


## Bind [param new_backend] (or fall back to print if it is invalid).
static func set_backend( new_backend:Object ) -> void:
	_bound = Bound.new()
	_bound.bind( new_backend )


## Drop the backend and return to print fallbacks.
static func clear_backend() -> void:
	_bound = Bound.new()


## Highest set bit of [param what_lvl], so inclusive [constant Level.INFO]
## still means an INFO event.
static func event_bit( what_lvl:int ) -> int:
	if what_lvl <= 0:
		return 0
	var shift:int = 0
	var v:int = what_lvl
	while v > 1:
		v >>= 1
		shift += 1
	return 1 << shift


## Returns a BBCode URL link string.
static func link( url:String, text:String = "" ) -> String:
	return "[url='{url}'][color=57b3ff]{text}[/color][/url]".format({
		&'url':url, &'text':(url if text.is_empty() else text) })


## [method get_stack] with the top [param n] frames plus this wrapper removed.
static func get_stack_popped( n:int = 0 ) -> Array:
	var stack:Array = get_stack()
	for _i:int in mini( n + 1, maxi( stack.size() - 1, 0 ) ):
		stack.pop_front()
	return stack


## Call-site trace. [param object] is the identity (usually [code]self[/code]).
## [param stack] is passed through and not filled here.
static func trace( args:Dictionary = {}, object:Object = null, stack:Array = [] ) -> void:
	var bound:Bound = _session()
	if bound.can_log( Level.TRACE, object ):
		bound.fn_trace.call( args, object, stack )


## Message at [param p_lvl]. [param object] is the identity.
## [param stack] is passed through and not filled here.
static func lvl( p_lvl:int, content:Variant, object:Object = null, stack:Array = [] ) -> void:
	var bound:Bound = _session()
	if bound.can_log( p_lvl, object ):
		bound.fn_lvl.call( p_lvl, content, object, stack )


## [method print_rich] of [param text] when [param p_lvl] passes.
## [param object] is the identity. [param stack] is passed through and not
## filled here. A backend [code]rich[/code] is used when it exists; otherwise
## the line is printed as BBCode with no extra prefix.
static func rich( p_lvl:int, content:Variant, object:Object = null, stack:Array = [] ) -> void:
	var bound:Bound = _session()
	if bound.can_log( p_lvl, object ):
		bound.fn_rich.call( p_lvl, content, object, stack )


## ERROR message. [param object] is the identity.
## [param stack] is passed through and not filled here.
static func err( content:Variant, object:Object = null, stack:Array = [] ) -> void:
	var bound:Bound = _session()
	if bound.can_log( Level.ERROR, object ):
		bound.fn_lvl.call( Level.ERROR, content, object, stack )


## WARNING message. [param object] is the identity.
## [param stack] is passed through and not filled here.
static func wrn( content:Variant, object:Object = null, stack:Array = [] ) -> void:
	var bound:Bound = _session()
	if bound.can_log( Level.WARNING, object ):
		bound.fn_lvl.call( Level.WARNING, content, object, stack )

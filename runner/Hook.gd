@tool
@abstract
class_name TR_Hook
extends RefCounted

##[codeblock lang=text]
##│ _  _          _
##│| || |___  ___| |__
##│| __ / _ \/ _ \ / /
##│|_||_\___/\___/_\_\
##╰─────────────────────
##[/codeblock]Work around one test run.
##
## The runner calls [method pre] and [method post], then waits on
## [signal settled]. It does not name the subclass. [method _message] is a
## timeline mark and does nothing until a subclass writes it.
## [method _hook_opts] names the options script, or returns null.
## A case constant [code]HOOK[/code] or [code]HOOKS[/code] names
## extra scripts for that run alone.


#            ███████ ██  ██████  ███    ██  █████  ██      ███████             #
#            ██      ██ ██       ████   ██ ██   ██ ██      ██                  #
#            ███████ ██ ██   ███ ██ ██  ██ ███████ ██      ███████             #
#                 ██ ██ ██    ██ ██  ██ ██ ██   ██ ██           ██             #
#            ███████ ██  ██████  ██   ████ ██   ██ ███████ ███████             #
func                        _________SIGNALS_________              ()->void:pass

## The hook finished [method _pre] or [method _post]. [constant OK] continues the run.
signal settled( retcode:Error )


# ██████  ██████   ██████  ██████  ███████ ██████  ████████ ██ ███████ ███████ #
# ██   ██ ██   ██ ██    ██ ██   ██ ██      ██   ██    ██    ██ ██      ██      #
# ██████  ██████  ██    ██ ██████  █████   ██████     ██    ██ █████   ███████ #
# ██      ██   ██ ██    ██ ██      ██      ██   ██    ██    ██ ██           ██ #
# ██      ██   ██  ██████  ██      ███████ ██   ██    ██    ██ ███████ ███████ #
func                        ________PROPERTIES_______              ()->void:pass

## Case record, when the owner is a [TR_CaseSession].
var session:TR_CaseSession

# Owner that is not a case session.
var _host:Object

# Return code from the last [signal settled].
var _retcode:Error = OK

# True once [signal settled] has fired for this call.
var _done:bool = false

# One-shot listener installed by [method _arm].
var _on_settled:Callable = Callable()


#            ██    ██ ██ ██████  ████████ ██    ██  █████  ██                  #
#            ██    ██ ██ ██   ██    ██    ██    ██ ██   ██ ██                  #
#            ██    ██ ██ ██████     ██    ██    ██ ███████ ██                  #
#             ██  ██  ██ ██   ██    ██    ██    ██ ██   ██ ██                  #
#              ████   ██ ██   ██    ██     ██████  ██   ██ ███████             #
func                        _________VIRTUAL_________              ()->void:pass

## False leaves this script out of the options list. A case constant still runs it.
func _accept() -> bool:
	return true


## Before setup. Return the [enum Error]. [method pre] emits [signal settled].
@abstract
func _pre() -> Error


## After the procedure, including a timeout. Return the [enum Error]. [method post] emits [signal settled].
@abstract
func _post() -> Error


## Timeline mark. The default does nothing.
func _message( _text:String ) -> void:
	pass


## Options script for this hook. Null when the hook has no options.
static func _hook_opts() -> GDScript:
	return null


#         ███    ███ ███████ ████████ ██   ██  ██████  ██████  ███████         #
#         ████  ████ ██         ██    ██   ██ ██    ██ ██   ██ ██              #
#         ██ ████ ██ █████      ██    ███████ ██    ██ ██   ██ ███████         #
#         ██  ██  ██ ██         ██    ██   ██ ██    ██ ██   ██      ██         #
#         ██      ██ ███████    ██    ██   ██  ██████  ██████  ███████         #
func                        _________METHODS_________              ()->void:pass

## Store [param owner]. A [TR_CaseSession] is also [member session].
func bind_host( owner:Object ) -> void:
	_host = owner
	session = owner as TR_CaseSession


## Run [method _pre], then emit [signal settled] with its return code.
func pre() -> void:
	_arm()
	# An override may await. The base declaration cannot say so.
	@warning_ignore( "redundant_await" )
	var code:Error = await _pre()
	settled.emit( code )


## Run [method _post], then emit [signal settled] with its return code.
func post() -> void:
	_arm()
	# An override may await. The base declaration cannot say so.
	@warning_ignore( "redundant_await" )
	var code:Error = await _post()
	settled.emit( code )


## True when the call in progress has emitted [signal settled].
func is_finished() -> bool:
	return _done


## Return code from [signal settled] for the call in progress.
func get_retcode() -> Error:
	return _retcode


## Drop a wait that the runner will not finish.
func drop_wait() -> void:
	if _on_settled.is_valid() \
	and settled.is_connected( _on_settled ):
		settled.disconnect( _on_settled )


## Drop the owner so a hook and a session do not keep each other alive.
func release() -> void:
	drop_wait()
	session = null
	_host = null


#                 ███████ ████████  █████  ████████ ██  ██████                 #
#                 ██         ██    ██   ██    ██    ██ ██                      #
#                 ███████    ██    ███████    ██    ██ ██                      #
#                      ██    ██    ██   ██    ██    ██ ██                      #
#                 ███████    ██    ██   ██    ██    ██  ██████                 #
func                        __________STATIC_________              ()->void:pass

## [code]HOOK[/code] and [code]HOOKS[/code] on [param scr].
static func const_paths( scr:Script ) -> PackedStringArray:
	var out:PackedStringArray = PackedStringArray()
	if scr == null:
		return out

	var one:Variant = _const( scr, "HOOK" )
	if one is String:
		var path:String = one
		if _append_unique( out, path ):
			push_error( "TR_Hook.const_paths: append failed" )

	var many:Variant = _const( scr, "HOOKS" )
	if many is PackedStringArray:
		var listed:PackedStringArray = many
		for entry:String in listed:
			if _append_unique( out, entry ):
				push_error( "TR_Hook.const_paths: append failed" )
				break
	return out


#       ██ ███    ██ ████████ ███████ ██████  ███    ██  █████  ██             #
#       ██ ████   ██    ██    ██      ██   ██ ████   ██ ██   ██ ██             #
#       ██ ██ ██  ██    ██    █████   ██████  ██ ██  ██ ███████ ██             #
#       ██ ██  ██ ██    ██    ██      ██   ██ ██  ██ ██ ██   ██ ██             #
#       ██ ██   ████    ██    ███████ ██   ██ ██   ████ ██   ██ ███████        #
func                        ________INTERNAL_________              ()->void:pass

func _arm() -> void:
	_done = false
	_retcode = OK
	drop_wait()
	_on_settled = _mark_settled
	var err:int = settled.connect( _on_settled, CONNECT_ONE_SHOT )
	if err != OK:
		push_error( "TR_Hook: settled connect failed (%s)" % error_string( err ) )


func _mark_settled( result:Error ) -> void:
	_retcode = result
	_done = true


static func _const( scr:Script, key:String ) -> Variant:
	var current:Script = scr
	while current != null:
		var found:Dictionary = current.get_script_constant_map()
		if found.has( key ):
			return found[ key ]
		current = current.get_base_script()
	return null


## Append a trimmed path once. False when it was stored or skipped.
static func _append_unique( out:PackedStringArray, raw:String ) -> bool:
	var cleaned:String = raw.strip_edges()
	if cleaned.is_empty() \
	or out.has( cleaned ):
		return false
	return out.append( cleaned )

@tool
class_name Case
extends RefCounted

##[codeblock lang=text]
##│  ___
##│ / __|__ _ ___ ___
##│| (__/ _` (_-</ -_)
##│ \___\__,_/__/\___|
##╰─────────────────────
##[/codeblock]The body of one run.
##
## The session owns the result, the budget, and the hooks. The host owns
## the clock. This script is not an editor script, a node, or a main loop.
## `@tool` is only the editor's permission to call the body. Without it the
## editor builds a placeholder and the session refuses the case.
##[br][br]
## A case that needs a different host declares that as a constant the
## session can read: NEEDS_TREE, EDITOR_ONLY, NEEDS_MAIN_SCENE, NATIVE,
## BUDGET_S. Absent means no, empty, or five seconds.
##[br][br]
## [method _configure] assigns [member CaseSession.budget_s] and
## [member CaseSession.hooks]. It does not await. A tree host may then
## install [TracyCapture] when hooks is still empty. [method RunHooks.pre]
## runs next, then the clock, then the three calls below.
## [method RunHooks.post] runs after those calls, including a timeout.
## A non-OK post fails a passing run.


# ██████  ██████   ██████  ██████  ███████ ██████  ████████ ██ ███████ ███████ #
# ██   ██ ██   ██ ██    ██ ██   ██ ██      ██   ██    ██    ██ ██      ██      #
# ██████  ██████  ██    ██ ██████  █████   ██████     ██    ██ █████   ███████ #
# ██      ██   ██ ██    ██ ██      ██      ██   ██    ██    ██ ██           ██ #
# ██      ██   ██  ██████  ██      ███████ ██   ██    ██    ██ ███████ ███████ #
func                        ________PROPERTIES_______              ()->void:pass

var session: CaseSession


#            ██    ██ ██ ██████  ████████ ██    ██  █████  ██                  #
#            ██    ██ ██ ██   ██    ██    ██    ██ ██   ██ ██                  #
#            ██    ██ ██ ██████     ██    ██    ██ ███████ ██                  #
#             ██  ██  ██ ██   ██    ██    ██    ██ ██   ██ ██                  #
#              ████   ██ ██   ██    ██     ██████  ██   ██ ███████             #
func                        _________VIRTUAL_________              ()->void:pass

## Assign [member CaseSession.budget_s] and [member CaseSession.hooks] here. No await.
func _configure() -> void:
	pass


func _setup() -> Error:
	return OK


func _run_test() -> int:
	return CaseSession.TEST_OK


func _cleanup() -> Error:
	return OK

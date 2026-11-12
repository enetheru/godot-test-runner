@tool
class_name TR_Case
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
## BUDGET_S. Absent means no, empty, or five seconds. [code]DESCRIPTION[/code]
## is the text the result card header opens.
##[br][br]
## [method _configure] assigns [member TR_CaseSession.budget_s] and may
## append to [member TR_CaseSession.hooks]. It does not await. The session
## loads hook scripts from the options list and from the constants
## [code]HOOK[/code] and [code]HOOKS[/code] before that call.
## [method TR_Hook.pre] runs next. The session waits on
## [signal TR_Hook.settled]. The clock starts after pre, then the three
## calls below. [method TR_Hook.post] runs after those calls, including a
## timeout. A non-OK post fails a passing run.


# ██████  ██████   ██████  ██████  ███████ ██████  ████████ ██ ███████ ███████ #
# ██   ██ ██   ██ ██    ██ ██   ██ ██      ██   ██    ██    ██ ██      ██      #
# ██████  ██████  ██    ██ ██████  █████   ██████     ██    ██ █████   ███████ #
# ██      ██   ██ ██    ██ ██      ██      ██   ██    ██    ██ ██           ██ #
# ██      ██   ██  ██████  ██      ███████ ██   ██    ██    ██ ███████ ███████ #
func                        ________PROPERTIES_______              ()->void:pass

## Record that built this case. Assigned before [method _configure].
var session: TR_CaseSession


#            ██    ██ ██ ██████  ████████ ██    ██  █████  ██                  #
#            ██    ██ ██ ██   ██    ██    ██    ██ ██   ██ ██                  #
#            ██    ██ ██ ██████     ██    ██    ██ ███████ ██                  #
#             ██  ██  ██ ██   ██    ██    ██    ██ ██   ██ ██                  #
#              ████   ██ ██   ██    ██     ██████  ██   ██ ███████             #
func                        _________VIRTUAL_________              ()->void:pass

## Assign [member TR_CaseSession.budget_s] here. Append to [member TR_CaseSession.hooks] for a hook built in this script. No await.
func _configure() -> void:
	pass


func _setup() -> Error:
	return OK


func _run_test() -> int:
	return TR_CaseSession.TEST_OK


func _cleanup() -> Error:
	return OK

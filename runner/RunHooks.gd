@tool
@abstract
class_name TR_Hooks
extends RefCounted

## Work around one test run.
##
## [TR_Base] and [TR_CaseSession] await [method pre] and [method post]. They do
## not name the subclass methods. Null skips the hooks. [method message] is a
## timeline mark and does nothing until a subclass writes it.


## Before [method TR_Base._setup]. [constant OK] continues the run.
@abstract
func pre() -> Error


## After the procedure, including a timeout. A non-OK result fails a passing run.
@abstract
func post() -> Error


## Timeline mark. The default does nothing.
func message( _text:String ) -> void:
	pass

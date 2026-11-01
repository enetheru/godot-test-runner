@tool
@abstract
class_name RunHooks
extends RefCounted

## Work around one test run.
##
## [TestBase] awaits [method pre] and [method post]. It does not name the
## subclass methods. Null on the test skips the hooks. [method message] is a
## timeline mark and does nothing until a subclass writes it.


## Before [method TestBase._setup]. [constant OK] continues the run.
@abstract
func pre() -> Error


## After the procedure, including a timeout. A non-OK result fails a passing run.
@abstract
func post() -> Error


## Timeline mark. The default does nothing.
func message( _text:String ) -> void:
	pass

@tool
extends RefCounted

## Rows the test list keeps for one run.
##
## [code]TestDef[/code] is a folder. [code]TestResult[/code] is the latest
## run of one file, shown in an [InfoBox].

const InfoBox = preload( "uid://gli414sa5hot" )


class TestDef extends RefCounted:
	var name:String
	var folder_path:String
	var test_scripts:Array
	## Nested folders. Empty when this folder has only scripts.
	var children:Array = []
	var results:Dictionary[TreeItem, TestResult]


class TestResult extends RefCounted:
	## Panel widget for this run.
	var latest:InfoBox
	var retcode:TR_Base.RetCode
	var output:Array

	func _to_string() -> String:
		return JSON.stringify( {
			"latest": latest,
			"retcode": retcode,
			"output": output,
		}, "  ", false )

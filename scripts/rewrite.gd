@tool
extends EditorScript

var test_base_path : String = 'res://addons/test_runner/TestBase.gd'

var header_replacement ="# This script is a copy of TestBase.gd
class_name PlayBase
extends Node
var cycleref : Node

"

func _run()->void:
	var test_base = FileAccess.open(test_base_path, FileAccess.READ)
	var play_base_path = test_base_path.get_base_dir() + "/PlayBase_generated.gd"
	var play_base = FileAccess.open( play_base_path, FileAccess.WRITE)

	# first few lines can suck it.
	test_base.get_line()
	test_base.get_line()
	test_base.get_line()

	play_base.store_string(header_replacement)
	EditorInterface.notification(EditorFileSystem.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	EditorInterface.notification(EditorFileSystem.NOTIFICATION_WM_WINDOW_FOCUS_IN)

	while not test_base.eof_reached():
		var line : String = test_base.get_line()
		if "EditorInterface.get_base_control()." in line:
			line = line.replace("EditorInterface.get_base_control().", "")
		play_base.store_string(line + "\n")

@tool
extends EditorPlugin

const MainPanel = preload('main_panel.tscn')
const CHECKLIST = preload('res/checklist.svg')

var main_panel_instance : Control

func _enter_tree() -> void:
	main_panel_instance = MainPanel.instantiate()
	# Add the main panel to the editor's main viewport.
	EditorInterface.get_editor_main_screen().add_child(main_panel_instance)
	# Hide the main panel. Very much required.
	_make_visible(false)


func _exit_tree() -> void:
	if main_panel_instance:
		main_panel_instance.queue_free()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible : bool) -> void:
	if main_panel_instance:
		main_panel_instance.visible = visible


func _get_plugin_name() -> String:
	return "TestRunner"


func _get_plugin_icon() -> Texture2D:
	return CHECKLIST

@tool
extends PanelContainer

var title : String

@onready var stylebox : StyleBoxFlat = preload('res/info_style_box.tres').duplicate()
@onready var label: RichTextLabel = $Elements/Label
@onready var rtl: RichTextLabel = $Elements/RichTextLabel


func _on_focus_entered() -> void:
	stylebox.bg_color = Color(0.275, 0.439, 0.584)


func _on_focus_exited() -> void:
	stylebox.bg_color = Color(0.216, 0.31, 0.4)


func _ready() -> void:
	focus_mode = Control.FOCUS_CLICK
	add_theme_stylebox_override("panel", stylebox)
	label.add_theme_stylebox_override("normal", stylebox)


func set_title( new_title : String ) -> void:
	title = new_title
	label.clear()
	label.append_text(new_title)


func set_content(
			border_color : Color,
			icon : Texture2D,
			text : String
			) -> void:
	stylebox.border_color = border_color
	label.clear()
	label.add_image(icon, 23, 23, border_color.lightened(0.3) )
	label.append_text(title)
	rtl.clear()
	rtl.append_text(text)

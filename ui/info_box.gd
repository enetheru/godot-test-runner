@tool
extends PanelContainer

var title:String

@onready var label:RichTextLabel = $Elements/Label
@onready var rtl:RichTextLabel = $Elements/Log/RichTextLabel


func set_title( new_title:String ) -> void:
	title = new_title
	label.clear()
	label.add_text( new_title )


## Status word on the card, log in the well under it.
func set_content( status:String, text:String ) -> void:
	label.clear()
	label.push_color( _status_color( status ) )
	label.add_text( status )
	label.pop()
	label.add_text( "  %s" % title )
	_write_log( text )


func _write_log( text:String ) -> void:
	rtl.clear()
	if text.is_empty():
		return
	var dim := rtl.get_theme_color( &"dim_line" )
	var lines:PackedStringArray = text.split( "\n" )
	for i:int in lines.size():
		if i > 0:
			rtl.add_text( "\n" )
		if i % 2 == 1:
			rtl.push_color( dim )
			rtl.add_text( lines[i] )
			rtl.pop()
		else:
			rtl.add_text( lines[i] )


func _status_color( status:String ) -> Color:
	var item := &"default_color"
	match status:
		"OK":
			item = &"ok"
		"WARNING":
			item = &"warning"
		"FAILED":
			item = &"failed"
	return label.get_theme_color( item )

@tool
extends PanelContainer

# Card title. [method set_title] stores it and [method set_content] prints it.
var _title:String

# Status line. Assigned when the card is ready.
@onready var _label:RichTextLabel = $Elements/Label

# Log well under the status line.
@onready var _rtl:RichTextLabel = $Elements/Log/RichTextLabel


func _ready() -> void:
	if not _rtl.meta_clicked.is_connected( _on_log_meta ):
		@warning_ignore( "return_value_discarded" )
		_rtl.meta_clicked.connect( _on_log_meta )


func set_title( new_title:String ) -> void:
	_title = new_title
	_label.clear()
	_label.add_text( new_title )


## Status word on the card, log in the well under it.
func set_content( status:String, text:String ) -> void:
	_label.clear()
	_label.push_color( _status_color( status ) )
	_label.add_text( status )
	_label.pop()
	_label.add_text( "  %s" % _title )
	_write_log( text )


func _write_log( text:String ) -> void:
	_rtl.clear()
	if text.is_empty():
		return
	_rtl.append_text( _tint_level_labels( text ) )


## Level labels from the log. A line that already has a color tag is left as written.
func _tint_level_labels( text:String ) -> String:
	var error_bb := _bb_color( _rtl.get_theme_color( &"error" ) )
	var warning_bb := _bb_color( _rtl.get_theme_color( &"warning" ) )
	var lines:PackedStringArray = text.split( "\n" )
	var out := PackedStringArray()
	for line:String in lines:
		if out.append( _tint_level_line( line, error_bb, warning_bb ) ):
			push_error( "info_box._tint_level_labels: append failed" )
	return "\n".join( out )


func _tint_level_line( line:String, error_bb:String, warning_bb:String ) -> String:
	if line.contains( "[color" ):
		return line
	var body := line.lstrip( " \t" )
	var pad := line.substr( 0, line.length() - body.length() )
	if body.begins_with( "ERROR:" ):
		return "%s[color=%s]ERROR[/color]%s" % [ pad, error_bb, body.substr( 5 ) ]
	if body.begins_with( "WARNING:" ):
		return "%s[color=%s]WARNING[/color]%s" % [ pad, warning_bb, body.substr( 7 ) ]
	return line


func _bb_color( color:Color ) -> String:
	return "#" + color.to_html( false )


## [param meta] is [code]res://path:line[/code] from the failure markup.
func _on_log_meta( meta:Variant ) -> void:
	var link := str( meta )
	var parts:PackedStringArray = link.rsplit( ":", true, 1 )
	if parts.size() != 2 or not parts[0].begins_with( "res://" ):
		return
	if not Engine.is_editor_hint():
		return
	var opened:Resource = load( parts[0] )
	if opened is Script:
		EditorInterface.edit_script( opened, parts[1].to_int(), 0, true )


func _status_color( status:String ) -> Color:
	var item := &"default_color"
	match status:
		"OK":
			item = &"ok"
		"WARNING":
			item = &"warning"
		"FAILED":
			item = &"failed"
	return _label.get_theme_color( item )

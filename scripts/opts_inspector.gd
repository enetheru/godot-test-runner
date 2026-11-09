@tool
extends EditorInspectorPlugin

## Custom inspector for the shared Test Runner options resource.
##
## Level lists every ceiling. Tracy and its pad stay disabled until capture is configured.

const OptsScript = preload( "test_runner_opts.gd" )

const _READY_TIP:String = "Capture a Tracy trace for each run."
const _LOCKED_TIP:String = "Set the Tracy capture executable, Python, and crop scripts before this can be enabled."
const _NO_PROFILER_TIP:String = "This editor has no Profiler, so Tracy capture is unavailable."


func _can_handle( object:Object ) -> bool:
	return object is OptsScript


func _parse_begin( _object:Object ) -> void:
	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.text = "This resource is the shared Test Runner options. The dock and the case menu read it."
	add_custom_control( hint )


func _parse_property(
		_object:Object,
		_type:Variant.Type,
		prop:String,
		_hint_type:PropertyHint,
		_hint_string:String,
		_usage:int,
		_wide:bool,
	) -> bool:
	if prop == "lvl":
		add_property_editor( "lvl", LevelEditor.new() )
		return true
	if prop == "tracy":
		add_property_editor( "tracy", TracyEditor.new() )
		return true
	if prop == "tracy_pad_s":
		add_property_editor( "tracy_pad_s", PadEditor.new() )
		return true
	return false


## Full ceiling list. The exported enum only has Notice and above.
class LevelEditor extends EditorProperty:
	const _Log = preload( "../logging.gd" )

	var _option:OptionButton


	func _init() -> void:
		_option = OptionButton.new()
		_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for mask:int in _Log.CEILINGS:
			_option.add_item( _Log.level_label( mask ) )
		add_child( _option )
		add_focusable( _option )
		var err := _option.item_selected.connect( _on_selected )
		if err != OK:
			push_error( "opts_inspector.LevelEditor: select connect failed (%s)" % error_string( err ) )


	func _update_property() -> void:
		var opts:TestRunnerOpts = get_edited_object() as TestRunnerOpts
		if opts == null:
			return
		var idx:int = _Log.CEILINGS.find( opts.lvl )
		if idx < 0:
			idx = 0
		_option.set_block_signals( true )
		_option.select( idx )
		_option.set_block_signals( false )


	func _on_selected( index:int ) -> void:
		if index < 0 or index >= _Log.CEILINGS.size():
			return
		emit_changed( &"lvl", _Log.CEILINGS[ index ] )


## Same gate as the dock. No Profiler hides the switch. A missing capture setup disables it.
class TracyEditor extends EditorProperty:
	const _Capture = preload( "../runner/TracyCapture.gd" )

	var _check:CheckButton
	var _listening:bool = false


	func _init() -> void:
		_check = CheckButton.new()
		_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child( _check )
		add_focusable( _check )
		var err := _check.toggled.connect( _on_toggled )
		if err != OK:
			push_error( "opts_inspector.TracyEditor: toggle connect failed (%s)" % error_string( err ) )


	func _update_property() -> void:
		_listen()
		_sync()


	func _listen() -> void:
		if _listening:
			return
		var opts:OptsScript = get_edited_object()
		if opts == null:
			return
		var err:int = opts.changed.connect( _sync )
		if err != OK:
			push_error( "opts_inspector.TracyEditor: changed connect failed (%s)" % error_string( err ) )
			return
		_listening = true


	func _sync() -> void:
		var opts:TestRunnerOpts = get_edited_object() as TestRunnerOpts
		if opts == null:
			return
		var supported:bool = Engine.has_singleton( &"Profiler" )
		var capture_ready:bool = supported and _Capture.is_configured()
		_check.visible = supported
		_check.disabled = not capture_ready
		if not supported:
			_check.tooltip_text = _NO_PROFILER_TIP
			_check.set_pressed_no_signal( false )
			return
		if capture_ready:
			_check.tooltip_text = _READY_TIP
			_check.set_pressed_no_signal( opts.tracy )
			return
		_check.tooltip_text = _LOCKED_TIP
		_check.set_pressed_no_signal( false )


	func _on_toggled( pressed:bool ) -> void:
		emit_changed( &"tracy", pressed )


## Pad slider. Locked by the same capture gate as the Tracy switch.
class PadEditor extends EditorProperty:
	const _Capture = preload( "../runner/TracyCapture.gd" )

	var _slider:EditorSpinSlider
	var _listening:bool = false


	func _init() -> void:
		_slider = EditorSpinSlider.new()
		_slider.min_value = 0.0
		_slider.max_value = 120.0
		_slider.step = 0.01
		_slider.suffix = "s"
		_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child( _slider )
		add_focusable( _slider )
		var err := _slider.value_changed.connect( _on_value )
		if err != OK:
			push_error( "opts_inspector.PadEditor: value connect failed (%s)" % error_string( err ) )
		var grab_err := _slider.ungrabbed.connect( _on_ungrabbed )
		if grab_err != OK:
			push_error( "opts_inspector.PadEditor: ungrab connect failed (%s)" % error_string( grab_err ) )


	func _update_property() -> void:
		_listen()
		_sync()


	func _listen() -> void:
		if _listening:
			return
		var opts:OptsScript = get_edited_object()
		if opts == null:
			return
		var err:int = opts.changed.connect( _sync )
		if err != OK:
			push_error( "opts_inspector.PadEditor: changed connect failed (%s)" % error_string( err ) )
			return
		_listening = true


	func _sync() -> void:
		var opts:TestRunnerOpts = get_edited_object() as TestRunnerOpts
		if opts == null:
			return
		var capture_ready:bool = Engine.has_singleton( &"Profiler" ) and _Capture.is_configured()
		_slider.read_only = not capture_ready
		_slider.tooltip_text = _READY_TIP if capture_ready else _LOCKED_TIP
		_slider.set_value_no_signal( opts.tracy_pad_s )


	func _on_value( value:float ) -> void:
		if _slider.read_only:
			return
		emit_changed( &"tracy_pad_s", value, &"", true )


	func _on_ungrabbed() -> void:
		if _slider.read_only:
			return
		emit_changed( &"tracy_pad_s", _slider.value )

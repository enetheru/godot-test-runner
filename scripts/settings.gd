@tool

## │ ___      _   _   _                _  _     _                  [br]
## │/ __| ___| |_| |_(_)_ _  __ _ ___ | || |___| |_ __  ___ _ _    [br]
## │\__ \/ -_)  _|  _| | ' \/ _` (_-< | __ / -_) | '_ \/ -_) '_|   [br]
## │|___/\___|\__|\__|_|_||_\__, /__/ |_||_\___|_| .__/\___|_|     [br]
## ╰────────────────────────|___/────────────────|_|────────────── [br]
## Bridge `@export` properties on a target object into [ProjectSettings].
##
## Walks [method Object.get_property_list], maps [code]PROPERTY_USAGE_*[/code]
## groups, and keeps the target in sync when ProjectSettings change.[br]
## Intended for [EditorPlugin] (or similar) + options [Resource].[br]
## [br]
## [b]== Usage ==[/b][br]
## [codeblock]
## func _enter_tree() -> void:
##     settings_mgr = SettingsHelper.new(opts, "plugin/my_plugin_name")
## [/codeblock]
## [br]
## [b]== Examples ==[/b][br]
## [codeblock]
## @export_custom( PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR_BASIC_SETTING)
## var example:bool
## [/codeblock]
## Group / subgroup via [code]PROPERTY_USAGE_GROUP[/code] /
## [code]PROPERTY_USAGE_SUBGROUP[/code] (two layers). Underscores in names
## become path segments when prefixes match.[br]
## [br]
## Not all property hints map 1:1 to Project Settings inspector widgets.[br]
## [br]
## [method ProjectSettings.add_property_info] expects
## [code]name[/code], [code]type[/code], [code]hint[/code],
## [code]hint_string[/code].[br]
## [br]
## 11/11/2025 10:41am ACT+930 - Created[br]
## 09/02/2026 12:58am ACT+930 - Re-added settings_changed; docs[br]
## 24/02/2026 2:45am ACT+930 - Usage-flag notes; tooltip link; removed erase
## on exit (wiped EditorSettings risk); merged editor-tweaks / flatbuffers
## differences (buttons, enabled_plugins)[br]
## 2026-02-27 - ProjectSettings (was EditorSettings)[br]
## 2026-03-08 - settings_changed emits new value, not old[br]
## 2026-06-09 - Docs pass[br]
## 24/07/2026 1:49am ACT+930 - Consolidated editor-tweaks + flatbuffers copies:
## rename handler to ProjectSettings; fuller get_all_plugins_info docs; tool
## buttons use full setting path; enabled flag checks plugin.cfg path; typed
## script path for target; keep local Print preload per host addon[br]
##
## Tooltip idea (brute force):[br]
## https://github.com/PiCode9560/Godot-Editor-Settings-Description/blob/main/editor_settings_description.gd
##[br][color=goldenrod]TODO[/color]: have a URL we can point to and verify we
## have the latest version.

const Log = preload( "../logging.gd" )

## [enum PropertyHint] value to its global constant name.
## This build keeps global enums off ClassDB.
const _HINT_NAMES:Dictionary = {
	PROPERTY_HINT_NONE: &"PROPERTY_HINT_NONE",
	PROPERTY_HINT_RANGE: &"PROPERTY_HINT_RANGE",
	PROPERTY_HINT_ENUM: &"PROPERTY_HINT_ENUM",
	PROPERTY_HINT_ENUM_SUGGESTION: &"PROPERTY_HINT_ENUM_SUGGESTION",
	PROPERTY_HINT_EXP_EASING: &"PROPERTY_HINT_EXP_EASING",
	PROPERTY_HINT_LINK: &"PROPERTY_HINT_LINK",
	PROPERTY_HINT_FLAGS: &"PROPERTY_HINT_FLAGS",
	PROPERTY_HINT_LAYERS_2D_RENDER: &"PROPERTY_HINT_LAYERS_2D_RENDER",
	PROPERTY_HINT_LAYERS_2D_PHYSICS: &"PROPERTY_HINT_LAYERS_2D_PHYSICS",
	PROPERTY_HINT_LAYERS_2D_NAVIGATION: &"PROPERTY_HINT_LAYERS_2D_NAVIGATION",
	PROPERTY_HINT_LAYERS_3D_RENDER: &"PROPERTY_HINT_LAYERS_3D_RENDER",
	PROPERTY_HINT_LAYERS_3D_PHYSICS: &"PROPERTY_HINT_LAYERS_3D_PHYSICS",
	PROPERTY_HINT_LAYERS_3D_NAVIGATION: &"PROPERTY_HINT_LAYERS_3D_NAVIGATION",
	PROPERTY_HINT_FILE: &"PROPERTY_HINT_FILE",
	PROPERTY_HINT_DIR: &"PROPERTY_HINT_DIR",
	PROPERTY_HINT_GLOBAL_FILE: &"PROPERTY_HINT_GLOBAL_FILE",
	PROPERTY_HINT_GLOBAL_DIR: &"PROPERTY_HINT_GLOBAL_DIR",
	PROPERTY_HINT_RESOURCE_TYPE: &"PROPERTY_HINT_RESOURCE_TYPE",
	PROPERTY_HINT_MULTILINE_TEXT: &"PROPERTY_HINT_MULTILINE_TEXT",
	PROPERTY_HINT_EXPRESSION: &"PROPERTY_HINT_EXPRESSION",
	PROPERTY_HINT_PLACEHOLDER_TEXT: &"PROPERTY_HINT_PLACEHOLDER_TEXT",
	PROPERTY_HINT_COLOR_NO_ALPHA: &"PROPERTY_HINT_COLOR_NO_ALPHA",
	PROPERTY_HINT_OBJECT_ID: &"PROPERTY_HINT_OBJECT_ID",
	PROPERTY_HINT_TYPE_STRING: &"PROPERTY_HINT_TYPE_STRING",
	PROPERTY_HINT_NODE_PATH_TO_EDITED_NODE: &"PROPERTY_HINT_NODE_PATH_TO_EDITED_NODE",
	PROPERTY_HINT_OBJECT_TOO_BIG: &"PROPERTY_HINT_OBJECT_TOO_BIG",
	PROPERTY_HINT_NODE_PATH_VALID_TYPES: &"PROPERTY_HINT_NODE_PATH_VALID_TYPES",
	PROPERTY_HINT_SAVE_FILE: &"PROPERTY_HINT_SAVE_FILE",
	PROPERTY_HINT_GLOBAL_SAVE_FILE: &"PROPERTY_HINT_GLOBAL_SAVE_FILE",
	PROPERTY_HINT_INT_IS_OBJECTID: &"PROPERTY_HINT_INT_IS_OBJECTID",
	PROPERTY_HINT_INT_IS_POINTER: &"PROPERTY_HINT_INT_IS_POINTER",
	PROPERTY_HINT_ARRAY_TYPE: &"PROPERTY_HINT_ARRAY_TYPE",
	PROPERTY_HINT_LOCALE_ID: &"PROPERTY_HINT_LOCALE_ID",
	PROPERTY_HINT_LOCALIZABLE_STRING: &"PROPERTY_HINT_LOCALIZABLE_STRING",
	PROPERTY_HINT_NODE_TYPE: &"PROPERTY_HINT_NODE_TYPE",
	PROPERTY_HINT_HIDE_QUATERNION_EDIT: &"PROPERTY_HINT_HIDE_QUATERNION_EDIT",
	PROPERTY_HINT_PASSWORD: &"PROPERTY_HINT_PASSWORD",
	PROPERTY_HINT_LAYERS_AVOIDANCE: &"PROPERTY_HINT_LAYERS_AVOIDANCE",
	PROPERTY_HINT_DICTIONARY_TYPE: &"PROPERTY_HINT_DICTIONARY_TYPE",
	PROPERTY_HINT_TOOL_BUTTON: &"PROPERTY_HINT_TOOL_BUTTON",
	PROPERTY_HINT_ONESHOT: &"PROPERTY_HINT_ONESHOT",
	PROPERTY_HINT_GROUP_ENABLE: &"PROPERTY_HINT_GROUP_ENABLE",
	PROPERTY_HINT_INPUT_NAME: &"PROPERTY_HINT_INPUT_NAME",
	PROPERTY_HINT_FILE_PATH: &"PROPERTY_HINT_FILE_PATH",
}

## Single-bit [enum PropertyUsageFlags] value to its global constant name.
## Combined flags such as [constant PROPERTY_USAGE_DEFAULT] are left out.
const _USAGE_BITS:Dictionary = {
	PROPERTY_USAGE_STORAGE: &"PROPERTY_USAGE_STORAGE",
	PROPERTY_USAGE_EDITOR: &"PROPERTY_USAGE_EDITOR",
	PROPERTY_USAGE_INTERNAL: &"PROPERTY_USAGE_INTERNAL",
	PROPERTY_USAGE_CHECKABLE: &"PROPERTY_USAGE_CHECKABLE",
	PROPERTY_USAGE_CHECKED: &"PROPERTY_USAGE_CHECKED",
	PROPERTY_USAGE_GROUP: &"PROPERTY_USAGE_GROUP",
	PROPERTY_USAGE_CATEGORY: &"PROPERTY_USAGE_CATEGORY",
	PROPERTY_USAGE_SUBGROUP: &"PROPERTY_USAGE_SUBGROUP",
	PROPERTY_USAGE_CLASS_IS_BITFIELD: &"PROPERTY_USAGE_CLASS_IS_BITFIELD",
	PROPERTY_USAGE_NO_INSTANCE_STATE: &"PROPERTY_USAGE_NO_INSTANCE_STATE",
	PROPERTY_USAGE_RESTART_IF_CHANGED: &"PROPERTY_USAGE_RESTART_IF_CHANGED",
	PROPERTY_USAGE_SCRIPT_VARIABLE: &"PROPERTY_USAGE_SCRIPT_VARIABLE",
	PROPERTY_USAGE_STORE_IF_NULL: &"PROPERTY_USAGE_STORE_IF_NULL",
	PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED: &"PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED",
	PROPERTY_USAGE_SCRIPT_DEFAULT_VALUE: &"PROPERTY_USAGE_SCRIPT_DEFAULT_VALUE",
	PROPERTY_USAGE_CLASS_IS_ENUM: &"PROPERTY_USAGE_CLASS_IS_ENUM",
	PROPERTY_USAGE_NIL_IS_VARIANT: &"PROPERTY_USAGE_NIL_IS_VARIANT",
	PROPERTY_USAGE_ARRAY: &"PROPERTY_USAGE_ARRAY",
	PROPERTY_USAGE_ALWAYS_DUPLICATE: &"PROPERTY_USAGE_ALWAYS_DUPLICATE",
	PROPERTY_USAGE_NEVER_DUPLICATE: &"PROPERTY_USAGE_NEVER_DUPLICATE",
	PROPERTY_USAGE_HIGH_END_GFX: &"PROPERTY_USAGE_HIGH_END_GFX",
	PROPERTY_USAGE_NODE_PATH_FROM_SCENE_ROOT: &"PROPERTY_USAGE_NODE_PATH_FROM_SCENE_ROOT",
	PROPERTY_USAGE_RESOURCE_NOT_PERSISTENT: &"PROPERTY_USAGE_RESOURCE_NOT_PERSISTENT",
	PROPERTY_USAGE_KEYING_INCREMENTS: &"PROPERTY_USAGE_KEYING_INCREMENTS",
	PROPERTY_USAGE_DEFERRED_SET_RESOURCE: &"PROPERTY_USAGE_DEFERRED_SET_RESOURCE",
	PROPERTY_USAGE_EDITOR_INSTANTIATE_OBJECT: &"PROPERTY_USAGE_EDITOR_INSTANTIATE_OBJECT",
	PROPERTY_USAGE_EDITOR_BASIC_SETTING: &"PROPERTY_USAGE_EDITOR_BASIC_SETTING",
	PROPERTY_USAGE_READ_ONLY: &"PROPERTY_USAGE_READ_ONLY",
	PROPERTY_USAGE_SECRET: &"PROPERTY_USAGE_SECRET",
}


# ██████  ██████   ██████  ██████  ███████ ██████  ████████ ██ ███████ ███████ #
# ██   ██ ██   ██ ██    ██ ██   ██ ██      ██   ██    ██    ██ ██      ██      #
# ██████  ██████  ██    ██ ██████  █████   ██████     ██    ██ █████   ███████ #
# ██      ██   ██ ██    ██ ██      ██      ██   ██    ██    ██ ██           ██ #
# ██      ██   ██  ██████  ██      ███████ ██   ██    ██    ██ ███████ ███████ #
func                        ________PROPERTIES_______              ()->void:pass

var _prefix:String
var _target:Object
## Script filename used as the category marker for exported props.
var _target_file:String

## Full ProjectSettings path → target property name (grouping prefixes).
var setting_prop_map:Dictionary = {}

## TODO: per-setting callables when a setting changes.
#var setting_func_map:Dictionary = {}

signal settings_changed( setting_name:StringName, value:Variant )


#             ███████ ██    ██ ███████ ███    ██ ████████ ███████              #
#             ██      ██    ██ ██      ████   ██    ██    ██                   #
#             █████   ██    ██ █████   ██ ██  ██    ██    ███████              #
#             ██       ██  ██  ██      ██  ██ ██    ██         ██              #
#             ███████   ████   ███████ ██   ████    ██    ███████              #
func                        __________EVENTS_________              ()->void:pass

func _on_project_settings_changed() -> void:
	Log.lvl( Log.Level.TRACE, "_on_project_settings_changed", self )
	update_target.call_deferred()


#      ██████  ██    ██ ███████ ██████  ██████  ██ ██████  ███████ ███████     #
#     ██    ██ ██    ██ ██      ██   ██ ██   ██ ██ ██   ██ ██      ██          #
#     ██    ██ ██    ██ █████   ██████  ██████  ██ ██   ██ █████   ███████     #
#     ██    ██  ██  ██  ██      ██   ██ ██   ██ ██ ██   ██ ██           ██     #
#      ██████    ████   ███████ ██   ██ ██   ██ ██ ██████  ███████ ███████     #
func                        ________OVERRIDES________              ()->void:pass

func _init( target:Object, prefix:String = "plugin/un-named" ) -> void:
	_prefix = prefix
	_target = target

	var script_var:Variant = _target.get_script()
	if not script_var is Script:
		push_error("SettingsHelper._init: target needs a Script")
		return
	@warning_ignore("unsafe_cast")
	_target_file = (script_var as Script).resource_path.get_file()

	add_target_properties()

	@warning_ignore_start("return_value_discarded")
	ProjectSettings.settings_changed.connect(_on_project_settings_changed)
	@warning_ignore_restore("return_value_discarded")


#         ███    ███ ███████ ████████ ██   ██  ██████  ██████  ███████         #
#         ████  ████ ██         ██    ██   ██ ██    ██ ██   ██ ██              #
#         ██ ████ ██ █████      ██    ███████ ██    ██ ██   ██ ███████         #
#         ██  ██  ██ ██         ██    ██   ██ ██    ██ ██   ██      ██         #
#         ██      ██ ███████    ██    ██   ██  ██████  ██████  ███████         #
func                        _________METHODS_________              ()->void:pass

## Global constant name for [param hint].
func _hint_name( hint:int ) -> String:
	# Unknown hints stay as the integer.
	var key:Variant = _HINT_NAMES.get( hint )
	if key == null:
		return str( hint )
	return str( key )


## Single-bit usage names set in [param usage].
func _usage_names( usage:int ) -> PackedStringArray:
	# The map holds only powers of two, so a combined flag is never named whole.
	var names := PackedStringArray()
	for bit:int in _USAGE_BITS:
		if usage & bit:
			if not names.push_back( str( _USAGE_BITS[bit] ) ):
				break
	return names


## Register target properties as ProjectSettings under [member _prefix].
func add_target_properties() -> void:
	Log.lvl( Log.Level.TRACE, "add_target_properties", self )

	var category:String
	var group:String
	var group_prefix:String
	var subgroup:String
	var subgroup_prefix:String
	var is_inside_script:bool = false

	# Inspector grouping: unused group/subgroup prefixes reset that level.
	for property:Dictionary in _target.get_property_list():
		var property_name:String = property.name
		Log.lvl( Log.Level.TRACE, ["property.name:", property_name], self )
		var property_type:int = property.type
		Log.lvl( Log.Level.TRACE, ["property.type:", type_string(property_type)], self )
		var property_hint:int = property.hint
		Log.lvl( Log.Level.TRACE,
				["property.hint:", _hint_name( property_hint )], self )
		var hint_string:String = property.hint_string
		Log.lvl( Log.Level.TRACE, ["property.hint_string:", hint_string], self )

		var usage:int = property.usage
		Log.lvl( Log.Level.TRACE,
				["property.usage:", _usage_names( usage )], self )

		var property_value:Variant = _target.get(property_name)
		Log.lvl( Log.Level.TRACE, ["value:", property_value], self )

		if property.usage & PROPERTY_USAGE_CATEGORY:
			if property_name == _target_file:
				is_inside_script = true
				category = ""
				continue
			if not is_inside_script:
				continue
			category = property_name
			group = ""
			group_prefix = ""
			subgroup = ""
			subgroup_prefix = ""
			continue

		if not is_inside_script:
			continue

		if property.usage & PROPERTY_USAGE_GROUP:
			group = property_name
			group_prefix = hint_string
			subgroup = ""
			subgroup_prefix = ""
			continue

		if property.usage & PROPERTY_USAGE_SUBGROUP:
			subgroup = property_name
			subgroup_prefix = hint_string
			continue

		if not (usage & PROPERTY_USAGE_STORAGE):
			continue

		var group_level:int = 0
		var trimmed:bool = false
		var setting_name:String

		if subgroup and subgroup_prefix:
			if property_name.begins_with(subgroup_prefix):
				Log.lvl( Log.Level.TRACE, "matched subgroup_prefix", self )
				setting_name = property_name.trim_prefix(subgroup_prefix)
				trimmed = true
				group_level = 2
			else:
				subgroup_prefix = ""
		elif subgroup:
			group_level = 2

		if group_level == 0:
			if group_prefix:
				if property_name.begins_with(group_prefix):
					Log.lvl( Log.Level.TRACE, "match group_prefix", self )
					setting_name = property_name.trim_prefix(group_prefix)
					trimmed = true
					group_level = 1
				else:
					group_prefix = ""
			elif group:
				group_level = 1

		if group_level == 0:
			setting_name = property_name

		var parts:Array = [_prefix]
		if category:
			parts.append(category)
		if group_level > 0:
			parts.append(group)
			if group_level > 1:
				parts.append(subgroup)

		var setting_path:String = "/".join(parts)
		var setting_full:String = setting_path.path_join(setting_name)

		Log.lvl( Log.Level.TRACE, ["Category:", category], self )
		Log.lvl( Log.Level.TRACE, ["Group:", group, group_prefix], self )
		Log.lvl( Log.Level.TRACE, ["SubGroup:", subgroup, subgroup_prefix], self )
		Log.lvl( Log.Level.TRACE, ["group_level:", group_level], self )
		Log.lvl( Log.Level.TRACE, ["Trimmed:", trimmed], self )
		Log.lvl( Log.Level.TRACE, ["Setting Path:", setting_path], self )
		Log.lvl( Log.Level.TRACE, ["Setting Name:", setting_name], self )
		Log.lvl( Log.Level.TRACE, ["Setting_full:", setting_full], self )

		if property_value \
		and property_type == TYPE_CALLABLE \
		and property_hint & PROPERTY_HINT_TOOL_BUTTON:
			Log.lvl( Log.Level.TRACE, "is button", self )
			var button_func:Callable = property_value
			# Full path so buttons sit under the same prefix as other settings.
			add_callable_as_button(setting_full, button_func, hint_string)
			continue

		# Map full path → original property name (needed when prefixes trim).
		setting_prop_map[setting_full] = property_name

		var setting_info:Dictionary = {
			&"name": setting_full,
			&"type": property_type,
			&"hint": property_hint,
			&"hint_string": hint_string,
		}

		if ProjectSettings.has_setting(setting_full):
			var setting_value:Variant = ProjectSettings.get_setting(setting_full)
			ProjectSettings.add_property_info(setting_info)
			if setting_value == property_value:
				continue
			_target.set(property_name, setting_value)
		else:
			ProjectSettings.set_setting(setting_full, property_value)
			ProjectSettings.add_property_info(setting_info)


## Pull ProjectSettings values into the target; emit [signal settings_changed].
func update_target() -> void:
	Log.lvl( Log.Level.TRACE, "update_target", self )
	for setting_name:String in setting_prop_map.keys():
		var new_val:Variant = ProjectSettings.get(setting_name)
		var prop_name:StringName = setting_prop_map[setting_name]
		if new_val == _target.get(prop_name):
			continue
		Log.lvl( Log.Level.TRACE, "Updating '%s' : %s" % [setting_name, new_val], self )
		_target.set(prop_name, new_val)
		settings_changed.emit(prop_name, new_val)


func inspect_target() -> void:
	Log.lvl( Log.Level.TRACE, "inspect_target", self )
	EditorInterface.inspect_object(_target)


#                 ███████ ████████  █████  ████████ ██  ██████                 #
#                 ██         ██    ██   ██    ██    ██ ██                      #
#                 ███████    ██    ███████    ██    ██ ██                      #
#                      ██    ██    ██   ██    ██    ██ ██                      #
#                 ███████    ██    ██   ██    ██    ██  ██████                 #
func                        __________STATIC_________              ()->void:pass

## Scan project [code]addons[/code] for [code]plugin.cfg[/code] entries.[br]
## Each dict: [code]path[/code], [code]config[/code], [code]enabled[/code].[br]
##[br][color=yellow_green]NOTE[/color]: Uses engine project-root path form
## ([code]res://addons[/code]) so results match
## [code]editor_plugins/enabled[/code]. Whole-project discovery — not this
## helper's install path.
static func get_all_plugins_info( only_loaded:bool = false ) -> Array[Dictionary]:
	Log.lvl( Log.Level.TRACE, "get_all_plugins_info" )
	var enabled_plugins:PackedStringArray = ProjectSettings.get_setting(
		"editor_plugins/enabled")
	var plugins_info:Array[Dictionary] = []

	var addons_path:String = "res://addons"
	var dir:DirAccess = DirAccess.open(addons_path)
	if dir == null:
		push_error("SettingsHelper.get_all_plugins_info: cannot open project addons dir")
		return plugins_info

	var err:Error = dir.list_dir_begin()
	if err != OK:
		push_warning(
			"SettingsHelper.get_all_plugins_info: list_dir_begin failed (%s)"
			% error_string(err))
		return plugins_info

	var folder_name:String = dir.get_next()
	while folder_name != "":
		if dir.current_is_dir():
			var plugin_path:String = addons_path.path_join(folder_name)
			var cfg_path:String = plugin_path.path_join("plugin.cfg")

			if only_loaded and cfg_path not in enabled_plugins:
				folder_name = dir.get_next()
				continue

			if FileAccess.file_exists(cfg_path):
				var config:ConfigFile = ConfigFile.new()
				err = config.load(cfg_path)
				if err != OK:
					push_warning("SettingsHelper.get_all_plugins_info: load %s failed (%s)"
						% [cfg_path, error_string(err)])
					folder_name = dir.get_next()
					continue

				var config_props:Dictionary = {}
				var keys:PackedStringArray = config.get_section_keys("plugin")
				for key:String in keys:
					config_props[key] = config.get_value("plugin", key)

				plugins_info.append({
					&"path": plugin_path,
					&"config": config_props,
					&"enabled": cfg_path in enabled_plugins,
				})

		folder_name = dir.get_next()
	dir.list_dir_end()
	return plugins_info


## Register a TOOL_BUTTON callable under [param path].[br]
## FIXME: Callables do not serialise cleanly; once set they are hard to erase.
static func add_callable_as_button(
			path:String,
			callable:Callable,
			label:String = callable.get_method().capitalize() ) -> void:
	Log.lvl( Log.Level.TRACE, "add_callable_as_button" )
	ProjectSettings.set(path, callable)
	ProjectSettings.add_property_info({
		&"name": path,
		&"type": TYPE_CALLABLE,
		&"hint": PROPERTY_HINT_TOOL_BUTTON,
		&"hint_string": label,
	})


## Clear ProjectSettings under [param prefix] (skips TYPE_CALLABLE).
static func erase_prefix( prefix:String ) -> void:
	Log.lvl( Log.Level.TRACE, "erase_prefix" )
	for property:Dictionary in ProjectSettings.get_property_list():
		var setting_name:String = property.get(&"name")
		if not setting_name.begins_with(prefix):
			continue
		# Callables: cannot clear usage flags; erasing can error — skip.
		if property.type == TYPE_CALLABLE:
			continue
		ProjectSettings.set_setting(setting_name, null)

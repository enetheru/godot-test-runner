@tool
class_name TR_Opts
extends Resource

##[codeblock lang=text]
##│ _____ ___    ___       _
##│|_   _| _ \  / _ \ _ __| |_ ___
##│  | | |   / | (_) | '_ \  _(_-<
##│  |_| |_|_\  \___/| .__/\__/__/
##╰──────────────────|_|────────────
##[/codeblock]Run flags for the TestRunner dock.
##
## [method shared] is [code]res/opts.tres[/code]. The settings helper
## mirrors that resource with ProjectSettings.

const Self = preload("Opts.gd")

const Hook = preload("Hook.gd")

const HookOpts = preload("hooks/hook_opts.gd")

const Plugin = preload( "../plugin.gd" )

const Log = preload( "uid://br7jtx5cntuan" )

const PREFIX:String = "plugin/test_runner"

const DEFAULT_CASES_DIR:String = "res://cases"

# Nested hook folders stop here. The same cap as the case walk.
const _MAX_HOOK_SCAN_DEPTH:int = 32

# Path inside the addon. [method shared] joins it to the plugin folder.
const _OPTS_PATH:String = "res/opts.tres"


# ██████  ██████   ██████  ██████  ███████ ██████  ████████ ██ ███████ ███████ #
# ██   ██ ██   ██ ██    ██ ██   ██ ██      ██   ██    ██    ██ ██      ██      #
# ██████  ██████  ██    ██ ██████  █████   ██████     ██    ██ █████   ███████ #
# ██      ██   ██ ██    ██ ██      ██      ██   ██    ██    ██ ██           ██ #
# ██      ██   ██  ██████  ██      ███████ ██   ██    ██    ██ ███████ ███████ #
func                        ________PROPERTIES_______              ()->void:pass

# Last loaded options resource.
static var _shared:Self

# False after [member hook_dirs] changes, until [method scan_hooks] runs.
static var _hooks_ready:bool = false

# Path, resource path, and uid text → one scan row.
static var _hooks:Dictionary = {}

# Scanned hook paths, in folder order.
static var _hook_order:PackedStringArray = PackedStringArray()


## Collapsed test-tree rows, as row paths. Stored, and kept out of the inspector.
@export_storage var tree_folded:PackedStringArray = PackedStringArray():
	set( value ):
		if tree_folded == value:
			return
		tree_folded = value
		emit_changed()


## Left edge of the result pane, in pixels. Negative keeps the scene's split.
@export_storage var split_offset:int = -1:
	set( value ):
		if split_offset == value:
			return
		split_offset = value
		emit_changed()


@export_category( "Logging" )
## Inclusive [constant Log.Level]. Notice is quiet. The numbers are that enum.
@export_enum( "Notice:15", "Info:31", "Debug:63", "Trace:127" ) var lvl:int = Log.Level.DEFAULT:
	set( value ):
		if lvl == value:
			return
		lvl = value
		emit_changed()


@export_category( "Discovery" )
## Folders of TR_Case scripts. An empty list uses [constant DEFAULT_CASES_DIR].
@export_dir var cases_dirs:PackedStringArray = PackedStringArray( [ DEFAULT_CASES_DIR ] ):
	set( value ):
		if cases_dirs == value:
			return
		cases_dirs = value
		emit_changed()


@export_category( "Hooks" )
## Folders searched for hook scripts. Each script that extends TR_Hook is
## cached with its options script and the shared options resource.
## A case constant HOOK or HOOKS adds a script for that run alone.
@export_dir var hook_dirs:PackedStringArray = PackedStringArray():
	set( value ):
		if hook_dirs == value:
			return
		hook_dirs = value
		_hooks_ready = false
		emit_changed()


@export_category( "Play" )
@export_group( "Templates", "template_" )
## Binary that runs the reused play pack as template_debug. Empty refuses that menu item.
@export_global_file( "*.exe" ) var template_debug:String = "":
	set( value ):
		if template_debug == value:
			return
		template_debug = value
		emit_changed()


## Binary that runs the reused play pack as template_release. Empty refuses that menu item.
@export_global_file( "*.exe" ) var template_release:String = "":
	set( value ):
		if template_release == value:
			return
		template_release = value
		emit_changed()


#         ███    ███ ███████ ████████ ██   ██  ██████  ██████  ███████         #
#         ████  ████ ██         ██    ██   ██ ██    ██ ██   ██ ██              #
#         ██ ████ ██ █████      ██    ███████ ██    ██ ██   ██ ███████         #
#         ██  ██  ██ ██         ██    ██   ██ ██    ██ ██   ██      ██         #
#         ██      ██ ███████    ██    ██   ██  ██████  ██████  ███████         #
func                        _________METHODS_________              ()->void:pass

#region Saved - The cached options file.
#MARK: Saved
func                        __Saved__________________              ()->void:pass
# │ ___                  _
# │/ __| __ ___ _____ __| |
# │\__ \/ _` \ V / -_) _` |
# │|___/\__,_|\_/\___\__,_|
# ╰─────────────────────────

static func shared() -> Self:
	var loaded:Resource = load_saved( _shared, _OPTS_PATH, Self )
	if loaded is Self:
		_shared = loaded
	return _shared


## Load [param rel_path] from the addon folder. [param owner] is the script the file must use.
## [param current] is the cached resource. A missing file becomes [method GDScript.new].
static func load_saved( current:Resource, rel_path:String, owner:GDScript ) -> Resource:
	if current != null \
	and is_instance_valid( current ):
		return current

	var root:String = Plugin.addon_dir()
	var path:String = root.path_join( rel_path ) if not root.is_empty() else ""
	var loaded:Resource = load( path ) if not path.is_empty() else null
	if loaded != null \
	and loaded.get_script() == owner:
		return loaded

	push_error( "opts missing %s" % path )
	return owner.new()

#endregion Saved

#region Hooks - Hook scripts and their options resources.
#MARK: Hooks
func                        __Hooks__________________              ()->void:pass
# │ _  _          _
# │| || |___  ___| |__ ___
# │| __ / _ \/ _ \ / /(_-<
# │|_||_\___/\___/_\_\/__/
# ╰────────────────────────

## Walk [member hook_dirs]. Keep each script that extends TR_Hook, and cache
## its options script and shared resource.
static func scan_hooks() -> void:
	_hooks.clear()
	_hook_order = PackedStringArray()

	var visited:Dictionary = {}
	for root:String in _hook_roots():
		_scan_hook_dir( root, 0, visited )

	_hooks_ready = true


## Hook script paths from the last scan, in folder order.
static func hook_paths() -> PackedStringArray:
	if not _hooks_ready:
		scan_hooks()
	return _hook_order


## Cached row for [param script_path]. Empty when the scan did not keep that path.
## [code]script[/code] is the hook [GDScript]. [code]opts_script[/code] is the
## options [GDScript], or null. [code]shared[/code] is the shared [TR_HookOpts], or null.
static func hook_row( script_path:String ) -> Dictionary:
	if not _hooks_ready:
		scan_hooks()

	var key:String = script_path.strip_edges()
	if key.is_empty() or not _hooks.has( key ):
		return {}

	var found:Variant = _hooks[ key ]
	if found is Dictionary:
		return found
	return {}


## Cached hook script for [param script_path]. Null when the scan did not keep it.
static func script_for( script_path:String ) -> GDScript:
	var row:Dictionary = hook_row( script_path )
	var scr:Variant = row.get( &"script", null )
	if scr is GDScript:
		return scr
	return null


## Shared options resource for the hook script at [param script_path].
static func configuration_for( script_path:String ) -> HookOpts:
	var row:Dictionary = hook_row( script_path )
	var shared_v:Variant = row.get( &"shared", null )
	if shared_v is HookOpts:
		return shared_v
	return null

#endregion Hooks

#region Cases - Case folders from the options list.
#MARK: Cases
func                        __Cases__________________              ()->void:pass
# │  ___
# │ / __|__ _ ___ ___ ___
# │| (__/ _` (_-</ -_|_-<
# │ \___\__,_/__/\___/__/
# ╰───────────────────────

static func cases_roots() -> PackedStringArray:
	var opts:Self = shared()
	var found:PackedStringArray = PackedStringArray()
	if opts != null:
		found = opts.cases_dirs

	var out:PackedStringArray = PackedStringArray()
	for entry:String in found:
		var cleaned:String = _clean_dir( entry, "" )
		if cleaned.is_empty() or out.has( cleaned ):
			continue
		if out.append( cleaned ):
			push_error( "TR_Opts.cases_roots: append failed" )
			break

	if out.is_empty():
		if out.append( DEFAULT_CASES_DIR ):
			push_error( "TR_Opts.cases_roots: append failed" )
	return out


## Last path segment. The full path when two folders share that name.
static func case_leaf( root:String, roots:PackedStringArray ) -> String:
	var leaf:String = root.get_file()
	if leaf.is_empty():
		return root

	var copies:int = 0
	for other:String in roots:
		if other.get_file() == leaf:
			copies += 1

	if copies > 1:
		return root
	return leaf

#endregion Cases

#       ██ ███    ██ ████████ ███████ ██████  ███    ██  █████  ██             #
#       ██ ████   ██    ██    ██      ██   ██ ████   ██ ██   ██ ██             #
#       ██ ██ ██  ██    ██    █████   ██████  ██ ██  ██ ███████ ██             #
#       ██ ██  ██ ██    ██    ██      ██   ██ ██  ██ ██ ██   ██ ██             #
#       ██ ██   ████    ██    ███████ ██   ██ ██   ████ ██   ██ ███████        #
func                        ________INTERNAL_________              ()->void:pass

#region Scripts - Load a script and test its base.
#MARK: Scripts
func                        __Scripts________________              ()->void:pass
# │ ___         _      _
# │/ __| __ _ _(_)_ __| |_ ___
# │\__ \/ _| '_| | '_ \  _(_-<
# │|___/\__|_| |_| .__/\__/__/
# ╰──────────────|_|───────────

static func _load_gd( script_path:String ) -> GDScript:
	if script_path.is_empty() \
	or not ResourceLoader.exists( script_path ):
		return null

	var loaded:Resource = load( script_path )
	if loaded is GDScript:
		return loaded
	return null


static func _extends_script( scr:Script, base:Script ) -> bool:
	var current:Script = scr
	while current != null:
		if current == base:
			return true
		current = current.get_base_script()
	return false


static func _hook_roots() -> PackedStringArray:
	var out:PackedStringArray = PackedStringArray()
	var opts:Self = shared()
	if opts == null:
		return out

	for entry:String in opts.hook_dirs:
		var cleaned:String = _clean_dir( entry, "" )
		if cleaned.is_empty() or out.has( cleaned ):
			continue
		if out.append( cleaned ):
			push_error( "TR_Opts.scan_hooks: append failed" )
			break
	return out


static func _scan_hook_dir( folder_path:String, depth:int, visited:Dictionary ) -> void:
	if depth > _MAX_HOOK_SCAN_DEPTH:
		return

	var key:String = _visit_key( folder_path )
	if key.is_empty() or visited.has( key ):
		return
	visited[ key ] = true

	var opened:DirAccess = DirAccess.open( folder_path )
	if opened == null:
		push_error( "TR_Opts.scan_hooks: missing %s" % folder_path )
		return

	var file_names:PackedStringArray = DirAccess.get_files_at( folder_path )
	file_names.sort()
	for file_name:String in file_names:
		if not file_name.ends_with( ".gd" ):
			continue
		_consider_hook( folder_path.path_join( file_name ) )

	if depth == _MAX_HOOK_SCAN_DEPTH:
		return

	var folder_names:PackedStringArray = DirAccess.get_directories_at( folder_path )
	folder_names.sort()
	for folder_name:String in folder_names:
		if folder_name.is_empty() or folder_name.begins_with( "." ):
			continue
		_scan_hook_dir( folder_path.path_join( folder_name ), depth + 1, visited )


static func _consider_hook( script_path:String ) -> void:
	var gd:GDScript = _load_gd( script_path )
	if gd == null:
		push_error( "TR_Opts.scan_hooks: not a script %s" % script_path )
		return
	if not _extends_script( gd, Hook ):
		return
	if not gd.can_instantiate():
		push_error( "TR_Opts.scan_hooks: cannot instantiate %s" % script_path )
		return

	var opts_gd:GDScript = null
	var shared_opts:HookOpts = null
	# The loaded script is a [TR_Hook]. The analyzer only sees [GDScript].
	@warning_ignore( "unsafe_method_access" )
	var named:Variant = gd._hook_opts()
	if named != null and not named is GDScript:
		push_error( "TR_Opts.scan_hooks: options script is not a script %s" % script_path )
	elif named is GDScript:
		var named_gd:GDScript = named
		if not _extends_script( named_gd, HookOpts ):
			push_error( "TR_Opts.scan_hooks: options script does not extend TR_HookOpts %s" % script_path )
		else:
			opts_gd = named_gd
			@warning_ignore( "unsafe_method_access" )
			var shared_v:Variant = opts_gd.shared()
			if shared_v is HookOpts:
				shared_opts = shared_v
			elif shared_v != null:
				push_error( "TR_Opts.scan_hooks: shared options are not TR_HookOpts %s" % script_path )

	var row:Dictionary = {
		&"script": gd,
		&"opts_script": opts_gd,
		&"shared": shared_opts,
	}
	_remember_hook( script_path, gd, row )


static func _remember_hook( script_path:String, gd:GDScript, row:Dictionary ) -> void:
	var res_path:String = gd.resource_path
	if _hooks.has( script_path ) \
	or ( not res_path.is_empty() and _hooks.has( res_path ) ):
		return

	if _hook_order.append( script_path ):
		push_error( "TR_Opts.scan_hooks: append failed" )
		return

	_hooks[ script_path ] = row
	if not res_path.is_empty() and res_path != script_path:
		_hooks[ res_path ] = row

	var uid:int = ResourceLoader.get_resource_uid( script_path )
	if uid == -1 and not res_path.is_empty():
		uid = ResourceLoader.get_resource_uid( res_path )
	if uid == -1:
		return

	var uid_text:String = ResourceUID.id_to_text( uid )
	if uid_text.is_empty() or uid_text == script_path:
		return
	_hooks[ uid_text ] = row

#endregion Scripts

#region Paths - Clean a path list.
#MARK: Paths
func                        __Paths__________________              ()->void:pass
# │ ___      _   _
# │| _ \__ _| |_| |_  ___
# │|  _/ _` |  _| ' \(_-<
# │|_| \__,_|\__|_||_/__/
# ╰───────────────────────

static func _clean_dir( raw:String, fallback:String ) -> String:
	var text:String = raw.strip_edges()
	if text.is_empty():
		return fallback

	while text.ends_with( "/" ) and text != "res://":
		text = text.trim_suffix( "/" )
	return text


static func _visit_key( folder_path:String ) -> String:
	var abs_path:String = ProjectSettings.globalize_path( folder_path )
	return abs_path.simplify_path().replace( "\\", "/" ).to_lower()

#endregion Paths

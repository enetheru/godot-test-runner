@tool
extends EditorExportPlugin
## Skip paths listed in this addon's [code].exportignore[/code] during export.
##
## Patterns are [method String.match] globs relative to the addon, or path
## prefixes when they end with [code]/[/code]. They never apply outside this
## addon. [code]*[/code] skips the whole addon. This script and its
## [code].uid[/code] are always skipped.

var ignore_patterns:Array[String] = []


func _get_name() -> String:
	# Must sort before the built-in "GDScript" exporter. It remaps .gd
	# files and stops the plugin loop, so a later skip() never runs.
	return "EnetheruTestRunnerExport"


func _export_begin(
			_features:PackedStringArray,
			_is_debug:bool,
			_path:String,
			_flags:int ) -> void:
	# Clear so re-exports do not accumulate patterns.
	ignore_patterns.clear()
	_load_ignore_file()


func _addon_root() -> String:
	# resource_path is empty while this script's member initializers run.
	var script:Script = get_script()
	if script == null:
		return ""
	var base := script.resource_path.get_base_dir()
	if base.is_empty():
		return ""
	return base + "/"


func _load_ignore_file() -> void:
	var root := _addon_root()
	if root.is_empty():
		push_warning("TestRunnerExportPlugin._load_ignore_file:",
			" addon root is empty")
		return
	var path:String = root + ".exportignore"
	if not FileAccess.file_exists(path):
		return
	var file:FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("TestRunnerExportPlugin._load_ignore_file:",
			" failed to open %s" % path)
		return
	while not file.eof_reached():
		var line:String = file.get_line().strip_edges()
		if line and not line.begins_with("#"):
			ignore_patterns.append(line)


func _export_file(
			path:String,
			_type:String,
			_features:PackedStringArray ) -> void:
	var root := _addon_root()
	if root.is_empty() or not path.begins_with(root):
		return
	var relative := path.trim_prefix(root)
	if relative == "export_plugin.gd" or relative == "export_plugin.gd.uid":
		skip()
		return
	for raw:String in ignore_patterns:
		var pattern := raw
		if pattern.begins_with("./"):
			pattern = pattern.trim_prefix("./")
		if pattern.is_empty():
			continue
		var dir := pattern.trim_suffix("/")
		if relative.match(pattern) or relative == dir \
				or (not dir.is_empty() and relative.begins_with(dir + "/")):
			skip()
			return

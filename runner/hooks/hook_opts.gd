@tool
class_name TR_HookOpts
extends Resource

##[codeblock lang=text]
##│ _  _          _      ___       _
##│| || |___  ___| |__  / _ \ _ __| |_ ___
##│| __ / _ \/ _ \ / / | (_) | '_ \  _(_-<
##│|_||_\___/\___/_\_\  \___/| .__/\__/__/
##╰──────────────────────────|_|────────────
##[/codeblock]Base for a hook's options resource.
##
## [method shared] is that resource. The base returns null.
## A derived script overrides it with the saved resource.


static func shared() -> TR_HookOpts:
	return null


## ProjectSettings prefix for this resource. Empty lets the plugin name it from the hook file.
func settings_prefix() -> String:
	return ""

@tool
extends CommandServerTool

## Smoke registration: proves external addons can publish commands.


func get_command_name() -> String:
	return "TESTS_PING"


func get_description() -> String:
	return "Smoke check that TestRunner registered with Command Server."


func get_usage() -> String:
	return "TESTS_PING"


func get_input_schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {},
		"additionalProperties": false,
	}


func _execute_line( _args:String, _context:Dictionary ) -> String:
	return "OK: test-runner registered"

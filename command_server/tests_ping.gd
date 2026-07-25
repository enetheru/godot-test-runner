@tool
extends CommandServerCommand

## Smoke registration: proves external addons can publish commands.


func get_name() -> String:
	return "TESTS_PING"


func get_description() -> String:
	return "Smoke check that TestRunner registered with Command Server."


func get_usage() -> String:
	return "TESTS_PING"


func execute( _args:String, _context:Dictionary ) -> String:
	return "OK: test-runner registered"

@tool
extends TestBase

##                                                                            [br]
## │ ___ _            _                   ___ _                _              [br]
## │/ __| |_ _ _ __ _| |_ ___ __ _ _  _  |_ _| |_ ___ _ _ __ _| |_ ___ _ _    [br]
## │\__ \  _| '_/ _` |  _/ -_) _` | || |  | ||  _/ -_) '_/ _` |  _/ _ \ '_|   [br]
## │|___/\__|_| \__,_|\__\___\__, |\_, | |___|\__\___|_| \__,_|\__\___/_|     [br]
## ╰─────────────────────────|___/─|__/────────────────────────────────────── [br]
## Strategy Iterator By-Line
##
## Strategy Iterator Description

class TestObject extends TestStrategy:
	var tps:Array = [2,2,2]
	func _get_phase_count() -> int: return tps.size()
	func _get_phase_name(phase_idx:int) -> String: return str(phase_idx)
	func _get_strategy_count(phase_idx:int) -> int: return tps[phase_idx]
	func _get_strategy(_phase_idx:int, _strategy_idx:int) -> Callable: return null_strategy
	func _flow( selection:Array ) -> void: print("Flow: ", selection)


func _run_test() -> int:
	var test := TestObject.new()

	var num_combos:int = test.get_max_combos()
	var counter:int = 0
	for selection:Array[int] in test:
		counter += 1
		test.flow(selection)
	TEST_EQ(num_combos, counter,
		"The expected number of combinations and the counter should match")

	return runcode

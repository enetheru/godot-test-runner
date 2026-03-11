@tool
@abstract
class_name TestStrategy

# an attempt to make a multi-dimensional testing regime

# I wonder if I can make a situation where we can specify interdependence or not.

enum Flags {
	OK = 0,
	ERROR = 1,
}
var flags:int = 0

#       █████  ██████  ███████ ████████ ██████   █████   ██████ ████████       #
#      ██   ██ ██   ██ ██         ██    ██   ██ ██   ██ ██         ██          #
#      ███████ ██████  ███████    ██    ██████  ███████ ██         ██          #
#      ██   ██ ██   ██      ██    ██    ██   ██ ██   ██ ██         ██          #
#      ██   ██ ██████  ███████    ██    ██   ██ ██   ██  ██████    ██          #
func                        ________ABSTRACT_________              ()->void:pass

@abstract
func _get_phase_count() -> int

@abstract
func _get_phase_name(phase:int) -> String

@abstract
func _get_strategy_count(phase:int) -> int

@abstract
func _get_strategy(phase:int, strategy:int) -> Callable

@abstract
func _flow( selection:Array[int] ) -> void


#         ███    ███ ███████ ████████ ██   ██  ██████  ██████  ███████         #
#         ████  ████ ██         ██    ██   ██ ██    ██ ██   ██ ██              #
#         ██ ████ ██ █████      ██    ███████ ██    ██ ██   ██ ███████         #
#         ██  ██  ██ ██         ██    ██   ██ ██    ██ ██   ██      ██         #
#         ██      ██ ███████    ██    ██   ██  ██████  ██████  ███████         #
func                        _________METHODS_________              ()->void:pass


## Phase count is how many separate sections or phases in the testing sequence.
func get_phase_count() -> int:
	return _get_phase_count()

## Get the name of the phase indicated by [param phase]
func get_phase_name(phase_idx:int) -> String:
	assert( phase_idx >= 0 and phase_idx < get_phase_count() )
	return _get_phase_name(phase_idx)

## Return the number of strategies for the given [param phase]
func get_strategy_count(phase_idx:int) -> int:
	assert( phase_idx >= 0 and phase_idx < get_phase_count() )
	return _get_strategy_count(phase_idx)

## return the [Callable] representing the [param strategy] n of [param phase] k
func get_strategy(phase_idx:int, strategy_idx:int) -> Callable:
	assert( phase_idx >= 0 and phase_idx < get_phase_count() )
	assert( strategy_idx >= 0 and strategy_idx < get_strategy_count(phase_idx) )
	return _get_strategy(phase_idx, strategy_idx)

## run the workfow
func flow( selection:Array[int] ) -> void: _flow(selection)

## Can be used in place of a valid strategy for error checking.
func null_strategy(...args:Array ) -> Variant:
	if args.is_empty():
		print("Null strategy called")
		return null
	print("Null strategy called with args:")
	for arg:Variant in args: print("\t", str(arg))
	return null

## return the total number of combinations
func get_max_combos() -> int:
	return range(get_phase_count()).reduce(
		func(a:int, p:int,)->int:
			return a * get_strategy_count(p),
		1)


func                        __Strategy_Iterator______              ()->void:pass
#region Strategy Iterator
#MARK: Strategy Iterator
##                                                                            [br]
## │ ___ _            _                   ___ _                _              [br]
## │/ __| |_ _ _ __ _| |_ ___ __ _ _  _  |_ _| |_ ___ _ _ __ _| |_ ___ _ _    [br]
## │\__ \  _| '_/ _` |  _/ -_) _` | || |  | ||  _/ -_) '_/ _` |  _/ _ \ '_|   [br]
## │|___/\__|_| \__,_|\__\___\__, |\_, | |___|\__\___|_| \__,_|\__\___/_|     [br]
## ╰─────────────────────────|___/─|__/────────────────────────────────────── [br]
## Iterate over the phase/strategy combinations
##
## each iteration in the for loop returns an Array[int] of all possible
## combinations
## It's possible I might want to place this in a sub object.

## Helper function to get the last index of a strategy. Used below in the
## interator functions.
func _max_strat_idx(p:int) -> int:
	return get_strategy_count(p)  -1


## create the phase strategy array used for iterating.
func _iter_init(iter: Array) -> bool:
	var pc:int = get_phase_count()
	if not pc: return false # No Phases, Nothing to iterate.
	var selection:Array[int]
	selection.assign(range(pc).map(_max_strat_idx))
	iter[0] = selection
	return true


## The [param iter] is the unwrapped value.
func _iter_get(iter: Variant) -> Array[int]: return iter


## decrement the phase/strategy array by one and return
func _iter_next(iter: Array) -> bool:
	# get the value out of the array reference hack
	var selection:Array[int] = iter.front()
	# When all the elements return 0 we return false.
	if not selection.max():return false

	for p in get_phase_count():
		var sc:int = _max_strat_idx(p)
		if sc == 0: continue # skip phases with only one strategy.
		var cs:int = selection[p] # Current Strategy.
		if cs:
			selection[p] = cs - 1 # decrement the strategy index
			break
		selection[p] = sc # reset the strategy to default.

	# put the value back into the array reference hack
	iter[0] = selection
	return true

#endregion Strategy Iterator

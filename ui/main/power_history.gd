class_name PowerHistory
extends RefCounted

## How each organization's influence has moved lately — remembered by the screen,
## not by the world.
##
## The simulation keeps only the current power score, recomputed every epoch,
## because a float that changes every few seasons is not a fact worth putting in
## the history. But "who is rising" is the question a reader of the power screen
## actually has, and a single number cannot answer it. So the shell samples the
## scores each time they are recomputed, and the power screen draws the last few
## decades as a line and a change.
##
## It is a view's memory: it starts empty when the app starts, is forgotten when
## another world begins, and nothing in the simulation ever reads it.

## Samples kept per organization: one per epoch, so about eighty years.
const SAMPLES := 32
## How far back "lately" reaches for the change shown beside a score: ten years.
const TREND_BACK := 4

static var _series: Dictionary = {}
static var _last_tick := -1
static var _world_seed := 0


## Records every living organization's score as it stands at this tick. Asking
## twice for the same tick records once; a tick that goes backwards means a
## different history has been loaded or begun, and what was remembered belongs
## to that other one.
static func sample(tick: int) -> void:
	if GameState.world == null:
		return
	if tick == _last_tick and GameState.world.seed == _world_seed:
		return
	if tick < _last_tick or GameState.world.seed != _world_seed:
		_series.clear()
		_world_seed = GameState.world.seed
	_last_tick = tick
	var seen := {}
	for org in GameState.active_organizations():
		var line: PackedFloat32Array = _series.get(org.org_id, PackedFloat32Array())
		line.append(org.power_score)
		if line.size() > SAMPLES:
			line = line.slice(line.size() - SAMPLES)
		_series[org.org_id] = line
		seen[org.org_id] = true
	for id in _series.keys():
		if not seen.has(id):
			_series.erase(id)


static func series(org_id: StringName) -> PackedFloat32Array:
	return _series.get(org_id, PackedFloat32Array())


## The change in score over the last ten years, or NAN while there is not yet
## that much remembered.
static func change(org_id: StringName) -> float:
	var line := series(org_id)
	if line.size() <= TREND_BACK:
		return NAN
	return line[line.size() - 1] - line[line.size() - 1 - TREND_BACK]


static func clear() -> void:
	_series.clear()
	_last_tick = -1

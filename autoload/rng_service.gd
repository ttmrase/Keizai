extends Node

## Deterministic randomness, split into independently seeded named streams.
##
## One shared stream would make an old save's future draws shift whenever a later
## phase adds a new RNG consumer, which breaks reproducibility exactly when it is
## most needed for debugging. Seeding each stream from the world seed plus its own
## name keeps every stream independent of when it was first used, or of how many
## draws any other stream has taken.

var _world_seed: int = 0
var _streams: Dictionary[StringName, RandomNumberGenerator] = {}


func configure(world_seed: int) -> void:
	_world_seed = world_seed
	_streams.clear()


func get_world_seed() -> int:
	return _world_seed


func stream(stream_name: StringName) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = _streams.get(stream_name)
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = hash(str(_world_seed, ":", stream_name))
		_streams[stream_name] = rng
	return rng


## Convenience: true with probability `p`, drawn from the named stream.
func chance(stream_name: StringName, p: float) -> bool:
	return stream(stream_name).randf() < p


func pick(stream_name: StringName, options: Array):
	if options.is_empty():
		return null
	return options[stream(stream_name).randi_range(0, options.size() - 1)]


## Weighted pick. `weights` must be the same length as `options`; non-positive
## weights are treated as zero. Returns null only for an empty/zero-weight input.
func pick_weighted(stream_name: StringName, options: Array, weights: Array):
	if options.is_empty():
		return null
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return pick(stream_name, options)
	var roll := stream(stream_name).randf() * total
	for i in options.size():
		roll -= maxf(0.0, float(weights[i]))
		if roll <= 0.0:
			return options[i]
	return options[options.size() - 1]


## Streams persist their full `state`, not just the seed, so a loaded game
## continues its exact sequence rather than restarting it.
func to_dict() -> Dictionary:
	var streams := {}
	for name in _streams:
		streams[String(name)] = {
			"seed": _streams[name].seed,
			"state": _streams[name].state,
		}
	return {"world_seed": _world_seed, "streams": streams}


func from_dict(d: Dictionary) -> void:
	_world_seed = int(d.get("world_seed", 0))
	_streams.clear()
	for name in d.get("streams", {}):
		var rng := RandomNumberGenerator.new()
		rng.seed = int(d["streams"][name]["seed"])
		rng.state = int(d["streams"][name]["state"])
		_streams[StringName(name)] = rng

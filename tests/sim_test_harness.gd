class_name SimTestHarness
extends RefCounted

## Shared setup for the invariant suite. Fast-forwarding calls the tick function
## directly instead of waiting on the real-time accumulator, which is what makes
## a fifty-thousand-tick run finish in seconds.

const DEFAULT_SEED := 424242


static func fresh_world(world_seed: int = DEFAULT_SEED) -> void:
	WorldGenerator.generate(world_seed)
	SimClock.start(0)
	SimClock.set_time_scale(0.0)


static func advance(ticks: int) -> void:
	SimClock.advance_n_ticks_instant(ticks)


## A world that has actually been through something: monsters, a famine, and a
## couple of disasters, so schism and succession rules have reason to fire.
static func eventful_world(world_seed: int, ticks: int) -> void:
	fresh_world(world_seed)
	GodPowerAPI.set_monster_spawn_rate(2.2)
	advance(int(ticks * 0.25))
	GodPowerAPI.set_harvest_modifier(0.35)
	GodPowerAPI.trigger_disaster(&"drought", _first_settlement_id(), 1.5)
	advance(int(ticks * 0.25))
	GodPowerAPI.set_harvest_modifier(1.2)
	GodPowerAPI.set_ore_supply_rate(2.4)
	GodPowerAPI.trigger_disaster(&"plague", _first_settlement_id(), 1.2)
	advance(int(ticks * 0.25))
	GodPowerAPI.set_monster_spawn_rate(0.4)
	advance(ticks - int(ticks * 0.75))


static func _first_settlement_id() -> StringName:
	for id in GameState.world.settlements:
		return id
	return &""

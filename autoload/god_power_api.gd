extends Node

## Everything the player is allowed to do, and nothing else.
##
## Note what is absent: there is no set_leader(), no force_schism(), no way to
## name a ruler, back a faction, or nudge a power score. The signatures below
## accept settlements and magnitudes — never an organization, a person, or an
## ideology. Every political consequence has to arrive the long way round, by
## the simulation reacting to a changed world.
##
## That boundary is also checked mechanically: tests/test_god_power_boundary.gd
## fails the build if anything under res://ui/ writes simulation state directly.

func set_ore_supply_rate(rate: float) -> void:
	GameState.world.ore_supply_rate = clampf(rate, 0.0, 3.0)


func set_wood_supply_rate(rate: float) -> void:
	GameState.world.wood_supply_rate = clampf(rate, 0.0, 3.0)


func set_harvest_modifier(value: float) -> void:
	GameState.world.harvest_rate_modifier = clampf(value, 0.0, 2.0)


func set_monster_spawn_rate(rate: float) -> void:
	GameState.world.monster_spawn_rate = clampf(rate, 0.0, 3.0)


func get_dial(dial: StringName) -> float:
	return GameState.world.get(String(dial))


## Starts a disaster (or a blessing). Returns the recorded event, or null if the
## definition id is unknown.
func trigger_disaster(definition_id: StringName, target_settlement_id: StringName = &"",
		magnitude: float = 1.0) -> HistoryEvent:
	var def := ContentRegistry.get_disaster(definition_id)
	if def == null:
		push_warning("GodPowerAPI: unknown disaster '%s'" % definition_id)
		return null

	var inst := DisasterInstance.new()
	inst.disaster_id = GameState.mint_disaster_id()
	inst.definition_id = def.definition_id
	inst.target_settlement_id = target_settlement_id if def.targeted else &""
	inst.magnitude = clampf(magnitude, 0.1, 3.0)
	inst.start_tick = SimClock.current_tick
	inst.duration_ticks = def.duration_ticks

	var place := "世界"
	if inst.target_settlement_id != &"":
		var s: SettlementState = GameState.world.settlements.get(inst.target_settlement_id)
		if s != null:
			place = s.display_name

	var description := def.chronicle_template \
		.replace("{name}", def.display_name) \
		.replace("{place}", place)

	return HistoryLog.emit_event(
		HistoryEvent.EventType.DISASTER_OCCURRED,
		SimClock.current_tick,
		description,
		{"disaster": inst.to_dict(), "definition_id": String(def.definition_id)})


func available_disasters() -> Array[DisasterDefinition]:
	return ContentRegistry.all_disasters()

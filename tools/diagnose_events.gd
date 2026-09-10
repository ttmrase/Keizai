extends Node

## Development probe: runs a hard century and reports what ruptured.

func _ready() -> void:
	ContentRegistry.ensure_loaded()
	var seeds := [4101, 4102, 4103]
	for world_seed in seeds:
		WorldGenerator.generate(world_seed)
		SimClock.start(0)
		SimClock.set_time_scale(0.0)
		# A world that is given a hard time: monsters, famine, plague, repeat.
		for round_index in 6:
			GodPowerAPI.set_monster_spawn_rate(2.6)
			GodPowerAPI.set_harvest_modifier(0.3)
			SimClock.advance_n_ticks_instant(700)
			GodPowerAPI.trigger_disaster(&"plague", &"", 1.4)
			GodPowerAPI.trigger_disaster(&"drought", &"", 1.5)
			SimClock.advance_n_ticks_instant(700)
		_report(world_seed)
	get_tree().quit(0)


func _report(world_seed: int) -> void:
	var incidents := {}
	var refoundings := 0
	for e in HistoryLog.buffer:
		if e.event_type == HistoryEvent.EventType.INCIDENT:
			var kind: String = e.payload.get("incident_kind", "?")
			incidents[kind] = int(incidents.get(kind, 0)) + 1
		elif e.event_type == HistoryEvent.EventType.SCHISM \
				and String(e.payload.get("schism_kind", "")) == "refounding":
			refoundings += 1

	var polities := GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM, false)
	var deepest := 0
	for p in polities:
		deepest = maxi(deepest, p.branch_depth)
	var realm := HouseRank.dominant_realm()
	print("seed %d  年%d  不満%.2f  信仰の割れ %.2f" % [world_seed,
		int(SimClock.current_tick / SimConfig.TICKS_PER_YEAR),
		GameState.world.global_unrest, Religion.division()])
	print("   事件 %s" % [incidents])
	print("   政体: 記録上%d / 現存%d / 建て直し%d / 深さ%d"
		% [polities.size(),
			GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM).size(),
			refoundings, deepest])
	print("   いまの国: %s（%s）" % [realm.display_name if realm != null else "なし",
		PolityFormEvaluator.form_of(realm).display_name if realm != null
			and PolityFormEvaluator.form_of(realm) != null else "?"])
	for entry in Incidents.pressures():
		print("     %s %d%%  %s" % [entry["label"], int(float(entry["pressure"]) * 100.0),
			entry["missing"]])

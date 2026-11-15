extends Node

## Development probe: runs several seeds for a long time and counts the rare
## things — regime changes, refoundings, ruptures — and how long a tick takes.
## This is how the frequency targets in docs/DESIGN.md were measured.
##
##   godot --headless --path . res://tools/Census.tscn -- --seeds=1,2,3 --years=1500 --mode=quiet
##
## --mode=quiet leaves the world alone; --mode=eventful pushes it the way the
## test harness's eventful_world does, repeatedly.

var _seeds: Array[int] = [11, 12, 13, 14, 15]
var _years := 1000
var _mode := "quiet"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			_seeds.clear()
			for s in arg.split("=")[1].split(","):
				_seeds.append(int(s))
		elif arg.begins_with("--years="):
			_years = int(arg.split("=")[1])
		elif arg.begins_with("--mode="):
			_mode = arg.split("=")[1]
	ContentRegistry.ensure_loaded()
	var total_ms := 0
	var total_ticks := 0
	for world_seed in _seeds:
		WorldGenerator.generate(world_seed)
		SimClock.start(0)
		SimClock.set_time_scale(0.0)
		var ticks := _years * SimConfig.TICKS_PER_YEAR
		var started := Time.get_ticks_msec()
		_run(ticks)
		var ms := Time.get_ticks_msec() - started
		total_ms += ms
		total_ticks += ticks
		_report(world_seed, ms, ticks)
	print("== %s: %d seeds × %d年, %.3f ms/tick ==" % [_mode, _seeds.size(), _years,
		float(total_ms) / maxf(1.0, float(total_ticks))])
	get_tree().quit(0)


func _run(ticks: int) -> void:
	if _mode != "eventful":
		SimClock.advance_n_ticks_instant(ticks)
		return
	# The harness's eventful world, over and over: a hard stretch, then relief.
	var chunk := 2000
	var done := 0
	var round_index := 0
	while done < ticks:
		var step := mini(chunk, ticks - done)
		match round_index % 4:
			0:
				GodPowerAPI.set_monster_spawn_rate(2.2)
			1:
				GodPowerAPI.set_harvest_modifier(0.35)
				GodPowerAPI.trigger_disaster(&"drought", &"", 1.5)
			2:
				GodPowerAPI.set_harvest_modifier(1.2)
				GodPowerAPI.set_ore_supply_rate(2.4)
				GodPowerAPI.trigger_disaster(&"plague", &"", 1.2)
			3:
				GodPowerAPI.set_monster_spawn_rate(0.4)
		SimClock.advance_n_ticks_instant(step)
		done += step
		round_index += 1


func _report(world_seed: int, ms: int, ticks: int) -> void:
	var counts := {}
	var incidents := {}
	for e in HistoryLog.backbone:
		match e.event_type:
			HistoryEvent.EventType.INCIDENT:
				var kind: String = e.payload.get("incident_kind", "?")
				incidents[kind] = int(incidents.get(kind, 0)) + 1
			HistoryEvent.EventType.SCHISM:
				var sk := String(e.payload.get("schism_kind", ""))
				if e.payload.get("organization", {}).get("kind", "") == "POLITICAL_SYSTEM":
					counts["polity_" + sk] = int(counts.get("polity_" + sk, 0)) + 1
			HistoryEvent.EventType.POWER_TRANSFER:
				if bool(e.payload.get("regime_change", false)):
					counts["regime_change"] = int(counts.get("regime_change", 0)) + 1
	print("seed %d: %.3f ms/tick  polities now %d  %s  incidents %s" % [world_seed,
		float(ms) / float(ticks),
		GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM).size(),
		counts, incidents])



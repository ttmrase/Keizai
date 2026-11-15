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
	var wars: Array[String] = []
	var greats: Array[String] = []
	var quarrels: Array[String] = []
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
				if e.payload.has("battle"):
					counts["battles"] = int(counts.get("battles", 0)) + 1
				if e.payload.has("defector_house_id"):
					counts["defections"] = int(counts.get("defections", 0)) + 1
			HistoryEvent.EventType.GREATNESS:
				var field := String(e.payload.get("field", ""))
				counts["great_" + field] = int(counts.get("great_" + field, 0)) + 1
				greats.append("  ★%d年 [%s] %s" % [int(e.tick / 4),
					Greatness.field_label(field), e.description])
			HistoryEvent.EventType.OFFICE:
				var action := String(e.payload.get("action", ""))
				var office := String(e.payload.get("office", ""))
				if action == "appoint":
					counts["appoint_" + office] = int(counts.get("appoint_" + office, 0)) + 1
				elif action == "hereditary" and String(e.payload.get("house", "")) != "":
					counts["hereditary_" + office] = int(counts.get("hereditary_" + office, 0)) + 1
				elif action == "heirs" and bool(e.payload.get("reordered", false)):
					counts["heirs_reordered"] = int(counts.get("heirs_reordered", 0)) + 1
				elif action == "uji_chief":
					counts["uji_chief"] = int(counts.get("uji_chief", 0)) + 1
			HistoryEvent.EventType.INTRIGUE:
				if String(e.payload.get("action", "")) == "resolve":
					var outcome := String(e.payload.get("outcome", ""))
					counts["intrigue_" + outcome] = int(counts.get("intrigue_" + outcome, 0)) + 1
					var motive := String(e.payload.get("motive_kind", ""))
					if motive == "":
						motive = "ambition"
					counts["motive_" + motive] = int(counts.get("motive_" + motive, 0)) + 1
					var root := String(e.payload.get("motive_root_kind", ""))
					if root == "":
						root = "ambition"
					counts["root_" + root] = int(counts.get("root_" + root, 0)) + 1
					for fall in e.payload.get("falls", []):
						var fk := String(fall.get("kind", ""))
						counts["fall_" + fk] = int(counts.get("fall_" + fk, 0)) + 1
					if int(e.payload.get("motive_generations", 0)) >= 2 and outcome == "won":
						counts["revenge_3gen"] = int(counts.get("revenge_3gen", 0)) + 1
					if bool(e.payload.get("major", false)):
						counts["intrigue_major"] = int(counts.get("intrigue_major", 0)) + 1
					quarrels.append("  ⚔%d年 %s" % [int(e.tick / 4), e.description])
			HistoryEvent.EventType.DOCTRINE:
				var act := String(e.payload.get("action", ""))
				counts["doctrine_" + act] = int(counts.get("doctrine_" + act, 0)) + 1
				if act == "born":
					var dk := String(e.payload.get("derivation", ""))
					counts["derive_" + dk] = int(counts.get("derive_" + dk, 0)) + 1
					if not counts.has("first_doctrine_year"):
						counts["first_doctrine_year"] = int(e.tick / 4)
					quarrels.append("  ✎%d年 %s" % [int(e.tick / 4), e.description])
			HistoryEvent.EventType.CONFLICT_DECLARED:
				if e.payload.has("war"):
					var cause := String(e.payload["war"].get("cause", ""))
					counts["war_" + cause] = int(counts.get("war_" + cause, 0)) + 1
			HistoryEvent.EventType.CONFLICT_RESOLVED:
				if e.payload.has("war_id"):
					var outcome := String(e.payload.get("outcome", ""))
					counts["end_" + outcome] = int(counts.get("end_" + outcome, 0)) + 1
					wars.append("  %d年 %s %d年間 戦%d %s" % [int(e.tick / 4), outcome,
						int(e.payload.get("years", 0)), int(e.payload.get("battles", 0)),
						" / ".join(e.payload.get("aftermath", []))])
	print("seed %d: %.3f ms/tick  polities now %d  %s  incidents %s" % [world_seed,
		float(ms) / float(ticks),
		GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM).size(),
		counts, incidents])
	for line in wars:
		print(line)
	var officers := 0
	for id in GameState.people:
		if GameState.people[id].ever_held_office():
			officers += 1
	print("  偉人 %d人 / 役職経験者 %d人" % [greats.size(), officers])
	for line in greats:
		print(line)
	var live := {}
	for g in Grudges.live():
		live[g["kind"]] = int(live.get(g["kind"], 0)) + 1
	print("  政争・思想 %d行 / 生きている遺恨 %s" % [quarrels.size(), live])
	for line in quarrels.slice(0, 40):
		if line.begins_with("  ✎") or quarrels.find(line) < 6:
			print(line)
	var alive := 0
	var creeds: Array[String] = []
	for d in Doctrines.all():
		if d.is_alive():
			alive += 1
		for a in d.adoptions:
			creeds.append("%s(%d-%s)" % [d.name, int(int(a["start"]) / 4),
				"" if int(a["end"]) < 0 else str(int(int(a["end"]) / 4))])
	print("  思想 %d（存命%d） 国是: %s" % [Doctrines.all().size(), alive, ", ".join(creeds)])
	# How many were alive at once (each year since the first), and how far apart
	# revisions came.
	var now := SimClock.current_tick
	var most := 0
	var sum := 0
	var years := 0
	if not Doctrines.all().is_empty():
		var first := Doctrines.all()[0].born_tick
		for t in range(first, now, SimConfig.TICKS_PER_YEAR):
			var n := 0
			for d in Doctrines.all():
				var end := d.state_tick if d.state == "faded" else now + 1
				if d.born_tick <= t and t < end:
					n += 1
			most = maxi(most, n)
			sum += n
			years += 1
	var gaps: Array[float] = []
	for d in Doctrines.all():
		for i in range(1, d.thinkers.size()):
			gaps.append(float(int(d.thinkers[i]["tick"]) - int(d.thinkers[i - 1]["tick"])) / 4.0)
	var gap_mean := 0.0
	for g in gaps:
		gap_mean += g
	print("  思想の同時存命 最大%d 平均%.1f／改訂の間隔 平均%.0f年（%d回）" % [most,
		float(sum) / maxf(1.0, float(years)), gap_mean / maxf(1.0, float(gaps.size())), gaps.size()])
	# Seats: how long people held them.
	var tenures := {}
	for id in GameState.people:
		for r in GameState.people[id].office_history:
			var end := int(r.get("end", -1))
			if end < 0:
				continue
			var key := String(r.get("office", ""))
			var list: Array = tenures.get(key, [])
			list.append(float(end - int(r.get("start", 0))) / 4.0)
			tenures[key] = list
	var tenure_text: Array[String] = []
	for key in tenures:
		var total := 0.0
		for y in tenures[key]:
			total += float(y)
		tenure_text.append("%s %d回・平均%.0f年" % [Offices.LABELS.get(key, key), (tenures[key] as Array).size(),
			total / float((tenures[key] as Array).size())])
	print("  要職の在任: %s" % "、".join(tenure_text))
	_report_rank()
	for war in GameState.world.wars:
		print("  (進行中) %d年〜 front %.2f" % [int(war.start_tick / 4), war.front])



## What the top of the peerage rests on: for the five highest houses, their
## grounds by kind; and the same summed over every census run.
static var rank_kinds_total := {}


func _report_rank() -> void:
	var ctx := HouseRank.context(true)
	var ranked: Array = []
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing == Organization.Standing.NOBLE:
			var grounds := HouseRank.grounds_of(house, ctx)
			ranked.append([HouseRank.standing_from(grounds), house, grounds])
	ranked.sort_custom(func(x, y): return x[0] > y[0])
	var kinds := {}
	for entry in ranked.slice(0, 5):
		for g in entry[2]:
			var k := String(g["kind"])
			kinds[k] = snappedf(float(kinds.get(k, 0.0)) + float(g["value"]), 0.01)
			rank_kinds_total[k] = float(rank_kinds_total.get(k, 0.0)) + float(g["value"])
	print("  上位5家の家格の根拠（合計）: %s" % [kinds])
	for entry in ranked.slice(0, 3):
		var parts: Array[String] = []
		for g in (entry[2] as Array).slice(0, 5):
			parts.append("%s %.2f" % [g["label"], g["value"]])
		print("    %s %s %.2f: %s" % [entry[1].formal_name(), HouseRank.title_of_house(entry[1]),
			entry[0], "、".join(parts)])
	for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		var seats: Array[String] = []
		for key in polity.offices:
			var holder := GameState.get_person(StringName(polity.offices[key].get("person", "")))
			seats.append("%s=%s" % [Offices.label_of(String(key), polity),
				holder.full_name if holder != null else "?"])
		print("  %s 要職: %s 家職:%s 跡目:%d家" % [polity.formal_name(), ", ".join(seats),
			polity.hereditary_offices.keys(), polity.heir_houses.size()])

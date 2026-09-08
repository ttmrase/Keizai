extends Node

## Development harness: runs a scripted century and prints what the civilization
## did with it. Not shipped in the game — this is how you eyeball whether the
## rules produce a story worth watching.
##
##   godot --headless --path . res://tools/Diagnose.tscn -- --ticks=4000 --seed=7

var _ticks := 3000
var _seed := 20260908


func _ready() -> void:
	_parse_args()
	print("=== Keizai diagnostic run: seed=%d ticks=%d ===\n" % [_seed, _ticks])

	WorldGenerator.generate(_seed)
	SimClock.start(0)

	_print_world_opening()
	_run_scenario()

	print("\n=== after %d ticks (%d年) ===" % [SimClock.current_tick, SimClock.year()])
	_print_world_numbers()
	_print_org_tree()
	_print_power_table()
	_print_chronicle_highlights()
	_print_family_tree()
	_print_invariants()

	get_tree().quit(0)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ticks="):
			_ticks = int(arg.split("=")[1])
		elif arg.begins_with("--seed="):
			_seed = int(arg.split("=")[1])


## A deliberately eventful century: monsters rise, the harvest fails, disasters
## land, then the pressure lifts. Each phase should push a different institution
## to the fore.
func _run_scenario() -> void:
	var quarter := int(_ticks / 4)

	print("--- 第1期: 魔物が増える ---")
	GodPowerAPI.set_monster_spawn_rate(2.4)
	SimClock.advance_n_ticks_instant(quarter)
	_print_phase_summary()

	print("--- 第2期: 凶作と災厄 ---")
	GodPowerAPI.set_harvest_modifier(0.4)
	GodPowerAPI.trigger_disaster(&"drought", &"", 1.4)
	SimClock.advance_n_ticks_instant(int(quarter * 0.5))
	GodPowerAPI.trigger_disaster(&"plague", &"", 1.2)
	SimClock.advance_n_ticks_instant(int(quarter * 0.5))
	_print_phase_summary()

	print("--- 第3期: 鉱脈と豊穣 ---")
	GodPowerAPI.set_harvest_modifier(1.35)
	GodPowerAPI.set_ore_supply_rate(2.6)
	GodPowerAPI.trigger_disaster(&"mineral_strike", &"", 1.5)
	GodPowerAPI.set_monster_spawn_rate(0.6)
	SimClock.advance_n_ticks_instant(quarter)
	_print_phase_summary()

	print("--- 第4期: 静かな時代 ---")
	GodPowerAPI.set_harvest_modifier(1.0)
	GodPowerAPI.set_ore_supply_rate(1.0)
	SimClock.advance_n_ticks_instant(_ticks - quarter * 3)
	_print_phase_summary()


func _print_phase_summary() -> void:
	var w: WorldState = GameState.world
	var top := PowerCalculator.ranked()
	var leader := "なし"
	if not top.is_empty():
		leader = "%s (%.0f)" % [top[0].display_name, top[0].power_score]
	print("  %d年: 人口%.0f 魔物脅威%.2f 不満%.2f 収穫%.2f | 最有力: %s | 組織数%d"
		% [SimClock.year(), w.global_population, w.global_monster_threat_level,
			w.global_unrest, w.global_harvest_modifier, leader,
			GameState.active_organizations().size()])


func _print_world_opening() -> void:
	print("--- 建国 ---")
	for org in GameState.active_organizations():
		var leader := GameState.get_current_leader(org.org_id)
		print("  [%s] %s — %s / %s" % [org.kind_name(), org.display_name, org.description,
			leader.full_name if leader != null else "不在"])
	print("")


func _print_world_numbers() -> void:
	var w: WorldState = GameState.world
	print("人口 %.0f / 富 %.0f / 鉱石 %.0f / 木材 %.0f / 食料 %.0f"
		% [w.global_population, w.global_wealth, w.global_ore, w.global_wood, w.global_food_stock])
	print("魔物 %.0f (脅威 %.2f) / 不満 %.2f / 収穫 %.2f"
		% [w.global_monster_population, w.global_monster_threat_level,
			w.global_unrest, w.global_harvest_modifier])
	print("記録された出来事: %d件 (うち系譜上不可欠: %d件)"
		% [HistoryLog.total_recorded, HistoryLog.backbone.size()])


func _print_org_tree() -> void:
	print("\n--- 組織の系譜 ---")
	for kind in [Organization.OrgKind.POLITICAL_SYSTEM, Organization.OrgKind.HOUSE,
			Organization.OrgKind.GUILD, Organization.OrgKind.FACTION]:
		var root := GameState.root_of_kind(kind)
		if root == null:
			continue
		_print_org_branch(root, 0)


func _print_org_branch(org: Organization, depth: int) -> void:
	var leader := GameState.get_current_leader(org.org_id)
	var status := "" if org.is_active() else " [消滅]"
	print("%s%s (%s, 力%.0f, %d名)%s — %s"
		% ["    ".repeat(depth) + ("└─ " if depth > 0 else ""), org.display_name,
			org.kind_name(), org.power_score, org.member_count, status,
			leader.full_name if leader != null else "指導者不在"])
	for child in GameState.child_organizations(org.org_id):
		_print_org_branch(child, depth + 1)


func _print_power_table() -> void:
	print("\n--- 勢力 ---")
	const BUILT_IN_LABELS := {
		PowerCalculator.BASE_KEY: "基礎",
		PowerCalculator.MEMBERSHIP_KEY: "規模",
		PowerCalculator.LEADERSHIP_KEY: "指導者の力量",
	}
	for org in PowerCalculator.ranked():
		var top_key := PowerCalculator.top_driver(org)
		var label: String = BUILT_IN_LABELS.get(top_key, String(top_key))
		var profile := ContentRegistry.get_power_profile(org.archetype_id)
		if profile != null:
			for d in profile.drivers:
				if d.world_var_path == top_key and not d.label.is_empty():
					label = d.label
		print("  %-26s %5.1f  主因: %s" % [org.display_name, org.power_score, label])


func _print_chronicle_highlights() -> void:
	print("\n--- 年代記(抜粋) ---")
	var shown := 0
	for e in HistoryLog.backbone:
		if e.event_type == HistoryEvent.EventType.BIRTH:
			continue
		print("  %-10s %s" % [SimClock.format_tick(e.tick), e.description])
		shown += 1
		if shown >= 30:
			break


func _print_family_tree() -> void:
	var house := GameState.root_of_kind(Organization.OrgKind.HOUSE)
	if house == null:
		return
	print("\n--- %s の家系 ---" % house.display_name)
	var founder: NotableIndividual = null
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		if p.house_org_id == house.org_id and p.is_founder_generation and p.sex == "m":
			founder = p
			break
	if founder == null:
		print("  (該当なし)")
		return
	_print_person(founder, 0)


func _print_person(p: NotableIndividual, depth: int) -> void:
	if depth > 8:
		return
	var life := "%d〜" % int(p.birth_tick / SimConfig.TICKS_PER_YEAR)
	if not p.is_alive():
		life += "%d年" % int(p.death_tick / SimConfig.TICKS_PER_YEAR)
	else:
		life += "存命"
	var titles: Array[String] = []
	for t in p.role_history:
		var org := GameState.get_organization(t.org_id)
		if org != null:
			titles.append("%s%s" % [org.display_name, t.title])
	var title_text := " 〈%s〉" % ", ".join(titles) if not titles.is_empty() else ""
	print("%s%s (%s)%s" % ["    ".repeat(depth) + ("└─ " if depth > 0 else ""),
		p.full_name, life, title_text])
	for child_id in p.children_ids:
		var child := GameState.get_person(child_id)
		if child != null:
			_print_person(child, depth + 1)


func _print_invariants() -> void:
	print("\n--- 不変条件 ---")
	var org_ok := 0
	var org_bad := 0
	for org in GameState.organizations.values():
		if GenealogyValidator.traces_to_root(org.org_id):
			org_ok += 1
		else:
			org_bad += 1
			print("  !! %s の系譜が根に到達しない" % org.display_name)
	var people_ok := 0
	var people_bad := 0
	for id in GameState.people:
		if GenealogyValidator.trace_to_founder(id):
			people_ok += 1
		else:
			people_bad += 1
	print("  組織の系譜: %d件が根に到達 / %d件が不正" % [org_ok, org_bad])
	print("  人物の家系: %d件が始祖に到達 / %d件が不正" % [people_ok, people_bad])

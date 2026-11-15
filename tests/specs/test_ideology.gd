extends Spec

## 思想の系譜: no doctrine when the world begins; free countries write them and
## closed ones mostly do not; every doctrine traces back to a single root; a
## creed pulls a country toward the state it describes; a doctrine set down from
## a reign names that reign; and all of it is the same every time and kept by a
## save.

const SLOT := 5
const LINEAGE := preload("res://tests/specs/test_lineage_invariants.gd")


func run() -> void:
	_check_none_at_start()
	_check_freedom_matters()
	_check_creed_moves_a_country()
	_check_born_of_a_reign()
	_check_round_trip_and_old_save()
	_check_determinism()
	finish()


func _check_none_at_start() -> void:
	SimTestHarness.fresh_world(7101)
	check(GameState.doctrines.is_empty(), "no doctrine exists when the world begins")
	for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		check_eq(polity.doctrine_id, &"", "no country starts with a creed")


## Holds every country open — or closed — for a stretch, re-imposing it every
## few years against the ordinary drift.
func _hold(open: bool) -> void:
	for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		if polity.ideology == null:
			continue
		if open:
			polity.ideology.decision_structure = PoliticalSystemAxes.DecisionStructure.ASSEMBLY
			polity.ideology.legitimacy_basis = PoliticalSystemAxes.LegitimacyBasis.ELECTED
			polity.ideology.set_axis(&"tradition_reform", 0.6)
			polity.ideology.set_axis(&"isolationism_commerce", 0.4)
			polity.ideology.set_axis(&"centralization", -0.3)
		else:
			polity.ideology.decision_structure = PoliticalSystemAxes.DecisionStructure.AUTOCRATIC
			polity.ideology.legitimacy_basis = PoliticalSystemAxes.LegitimacyBasis.MILITARY_STRENGTH
			polity.ideology.set_axis(&"tradition_reform", -0.8)
			polity.ideology.set_axis(&"isolationism_commerce", -0.6)
			polity.ideology.set_axis(&"centralization", 0.8)


func _run_held(world_seed: int, open: bool, years: int) -> Dictionary:
	SimTestHarness.fresh_world(world_seed)
	var argued := 0
	# Every year, so a state founded in between is held too.
	for year in years:
		_hold(open)
		SimTestHarness.advance(SimConfig.TICKS_PER_YEAR)
	for d in Doctrines.all():
		if d.derivation != "governance" and d.model_ruler_id == &"":
			argued += 1
	return {"all": GameState.doctrines.size(), "argued": argued}


func _check_freedom_matters() -> void:
	var closed := 0
	var closed_argued := 0
	var open := 0
	var open_argued := 0
	for world_seed in [7201, 7202, 7203]:
		var shut := _run_held(world_seed, false, 300)
		closed += int(shut["all"])
		closed_argued += int(shut["argued"])
		var free := _run_held(world_seed, true, 300)
		open += int(free["all"])
		open_argued += int(free["argued"])
		LINEAGE.check_doctrine_lineage(self, "seed %d held open" % world_seed)
		for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM, false):
			if polity.doctrine_id != &"":
				check(Doctrines.get_doctrine(polity.doctrine_id) != null, "a creed is a doctrine that exists")
		for d in Doctrines.all():
			check(GameState.get_person(d.founder_id) != null, "every doctrine has a founder")
			check_eq(String(d.thinkers[0].get("person", "")), String(d.founder_id),
				"the founder is the first of its thinkers")
	check_eq(closed_argued, 0, "a world held closed writes no doctrine out of argument")
	check_gt(float(open_argued), 0.0, "a world held open writes doctrines")
	check_gt(float(open), float(closed), "free countries write more than closed ones")
	print("    300 years held closed: %d doctrines (%d argued); held open: %d (%d argued)" % [
		closed, closed_argued, open, open_argued])


## Taking a creed pulls a country's ideals toward the state the doctrine
## describes, a little every year.
func _check_creed_moves_a_country() -> void:
	SimTestHarness.fresh_world(7301)
	var polity: Organization = null
	for p in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		polity = p
	var thinker := Doctrines._thinker(polity, SimClock.current_tick, RngService.stream(&"doctrine"), true)
	check(thinker != null, "a country has somebody who could write")
	if thinker == null:
		return
	Doctrines._birth(polity, thinker, SimClock.current_tick, RngService.stream(&"doctrine"), {})
	var d: Doctrine = Doctrines.all()[0]
	# Pull its picture a fair way off what the country is now, so the move shows.
	for a in PoliticalSystemAxes.AXIS_NAMES:
		d.claims[String(a)] = clampf(polity.ideology.get_axis(a) + 0.25, -1.0, 1.0)
	d.basis = polity.ideology.legitimacy_basis
	d.structure = polity.ideology.decision_structure
	d.prestige = 0.6
	Doctrines._adopt(polity, d, SimClock.current_tick, "")
	check_eq(polity.doctrine_id, d.doctrine_id, "adopting makes it the country's creed")
	check_eq(d.adopted_by().size(), 1, "and the doctrine knows who holds it")
	var before := Doctrines.distance(d, polity.ideology)
	var base := SimClock.current_tick - SimClock.current_tick % SimConfig.TICKS_PER_YEAR \
		+ Doctrines.STEP_SEASON
	for year in 10:
		Doctrines.step(base + (year + 1) * SimConfig.TICKS_PER_YEAR)
	var after := Doctrines.distance(d, polity.ideology)
	check(polity.doctrine_id == d.doctrine_id, "the creed is still held")
	check(after < before - 0.03, "a creed pulls the country toward it (%.3f -> %.3f)" % [before, after])


## A doctrine set down from a reign names the state and the ruler it took as its
## model — and when it is the world's first, it is the root.
func _check_born_of_a_reign() -> void:
	SimTestHarness.fresh_world(7401)
	SimTestHarness.advance(200)
	var polity: Organization = null
	for p in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		polity = p
	var ruler := GameState.get_current_leader(polity.org_id)
	var thinker := Doctrines._thinker(polity, SimClock.current_tick, RngService.stream(&"doctrine"), false)
	check(ruler != null and thinker != null, "a country with a ruler and a writer")
	if ruler == null or thinker == null:
		return
	var had := GameState.doctrines.size()
	Doctrines._birth(polity, thinker, SimClock.current_tick, RngService.stream(&"doctrine"),
		{"ruler": ruler, "great": true, "polity": polity})
	check_eq(GameState.doctrines.size(), had + 1, "a doctrine is born of the reign")
	var d: Doctrine = Doctrines.all().back()
	check_eq(d.model_polity_id, polity.org_id, "it names the state it took as its model")
	check_eq(d.model_ruler_id, ruler.person_id, "and the ruler")
	check_eq(d.derivation, "governance", "and says it came from a reign")
	if had == 0:
		check_eq(d.parent_id, &"", "the world's first doctrine is its root")
	LINEAGE.check_doctrine_lineage(self, "after a reign")
	# Every reign-born doctrine in a long natural run says whose reign it was.
	SimTestHarness.fresh_world(7402)
	SimTestHarness.advance(3200)
	for x in Doctrines.all():
		if x.derivation == "governance":
			check(GameState.get_person(x.model_ruler_id) != null, "a reign-born doctrine names its ruler")
			check(GameState.get_organization(x.model_polity_id) != null, "and its state")
	LINEAGE.check_doctrine_lineage(self, "seed 7402 after 800 years")


func _canon(value) -> String:
	return JSON.stringify(value, "", true)


func _check_round_trip_and_old_save() -> void:
	_run_held(7501, true, 200)
	SimTestHarness.advance(400)
	var before := GameState.to_dict()
	check_gt(float((before["doctrines"] as Dictionary).size()), 0.0, "a world with doctrines to save")
	check(SaveManager.save_game(SLOT), "saving")
	WorldGenerator.generate(1)
	check(SaveManager.load_game(SLOT), "loading")
	var after := GameState.to_dict()
	check_eq(_canon(after["doctrines"]), _canon(before["doctrines"]), "doctrines survive a save")
	check_eq(int(after["next_doctrine_seq"]), int(before["next_doctrine_seq"]), "and the next id")
	for id in before["organizations"]:
		check_eq(String(after["organizations"].get(id, {}).get("doctrine_id", "")),
			String(before["organizations"][id].get("doctrine_id", "")), "creeds and platforms survive")
	SimTestHarness.advance(80)
	LINEAGE.check_doctrine_lineage(self, "after loading")

	# A save from before doctrines: nothing written. It loads, and the world can
	# go on to write its first.
	GameState.doctrines.clear()
	for org_id in GameState.organizations:
		GameState.organizations[org_id].doctrine_id = &""
	check(SaveManager.save_game(SLOT), "saving an old-style world")
	WorldGenerator.generate(1)
	check(SaveManager.load_game(SLOT), "loading an old-style world")
	check(GameState.doctrines.is_empty(), "an old world has no doctrines it never recorded")
	for chunk in 20:
		_hold(true)
		SimTestHarness.advance(40)
	LINEAGE.check_doctrine_lineage(self, "an old world writing its first")
	SaveManager.delete_save(SLOT)


func _check_determinism() -> void:
	var lines: Array[String] = []
	for attempt in 2:
		_run_held(7601, true, 250)
		var parts: Array[String] = [_canon(GameState.to_dict()["doctrines"])]
		for e in HistoryLog.backbone:
			if e.event_type == HistoryEvent.EventType.DOCTRINE:
				parts.append("%d %s" % [e.tick, e.description])
		lines.append("\n".join(parts))
	check_eq(lines[1], lines[0], "the same world writes the same doctrines")

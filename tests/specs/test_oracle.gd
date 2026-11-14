extends Spec

## The god's side of the game: prophecies, might and feats.
##
## What matters most is what the oracle must not do — change the world's history
## by being asked something — and after that, that a prophecy which comes true
## is noticed, pays out, and is remembered across a save.

func run() -> void:
	SimTestHarness.fresh_world(808)
	SimTestHarness.advance(400)

	_might_accrues()
	_offers_are_real_and_harmless()
	_declaring()
	_an_event_fulfils_a_prophecy()
	_a_deadline_fails_a_prophecy()
	_judging_reads_the_world()
	_calamities_cost_might()
	_the_oracle_survives_a_save()
	_the_history_reads_as_chapters()
	_a_prophecy_races_its_deadline()
	_portents_read_the_world()
	_kin_bear_the_same_arms()
	finish()


func _might_accrues() -> void:
	# A hundred years at a point a year, from sixty, against a ceiling of 150.
	check_near(Oracle.might, Oracle.MAX_MIGHT, 0.01, "might should build to its ceiling over a century")


func _offers_are_real_and_harmless() -> void:
	var world_before := JSON.stringify(GameState.to_dict())
	var rng_before := JSON.stringify(RngService.to_dict())
	var offers := Oracle.current_offers()
	check_gt(float(offers.size()), 1.0, "the oracle should offer more than one prophecy")
	var kinds := {}
	var steerable := false
	for offer in offers:
		kinds[offer["kind"]] = true
		steerable = steerable or ProphecyBook.STEERABLE.has(offer["kind"])
		check(not String(offer["text"]).is_empty(), "every offer should say what it foretells")
		check(not String(offer["hint"]).is_empty(), "every offer should say how it might come about")
		check_gt(float(offer["reward"]), 0.0, "every offer should be worth something")
		check_gt(float(offer["deadline"]), float(SimClock.current_tick), "every offer should lie in the future")
		check_eq(ProphecyBook.judge(offer, SimClock.current_tick), ProphecyBook.Verdict.PENDING,
			"an offer should not already be settled: %s" % offer["text"])
	check_eq(kinds.size(), offers.size(), "offers should be of different kinds")
	check(steerable, "at least one offer should be something the dials can reach")
	Oracle.reroll()
	check_eq(JSON.stringify(GameState.to_dict()), world_before,
		"asking for prophecies should not change the world")
	check_eq(JSON.stringify(RngService.to_dict()), rng_before,
		"asking for prophecies should not draw on the world's randomness")


func _declaring() -> void:
	var offers := Oracle.current_offers()
	var count := offers.size()
	check(Oracle.declare(0), "a prophecy should be declarable")
	check_eq(Oracle.prophecies.size(), 1, "the declared prophecy should be active")
	check_eq(Oracle.offers.size(), count - 1, "the declared offer should leave the offers")
	Oracle.prophecies.clear()


func _an_event_fulfils_a_prophecy() -> void:
	var tick := SimClock.current_tick
	var p := ProphecyBook._make(ProphecyBook.INCIDENT, "uprising", "民衆蜂起", 0.0, tick, 40, 70,
		"40年のうちに、民衆蜂起が起きる", "test")
	p["state"] = "active"
	Oracle.prophecies.append(p)
	Oracle.might = 10.0
	var unlocked := []
	var listener := func(feat: Dictionary): unlocked.append(feat["id"])
	Oracle.feat_unlocked.connect(listener)
	HistoryLog.emit_event(HistoryEvent.EventType.INCIDENT, tick, "民が立ち上がった。",
		{"incident_kind": "uprising"})
	Oracle.feat_unlocked.disconnect(listener)
	check(Oracle.prophecies.is_empty(), "a prophecy that came true should no longer be pending")
	check_eq(String(Oracle.record.back()["state"]), "fulfilled", "it should be recorded as fulfilled")
	check_near(Oracle.might, 80.0, 0.01, "a fulfilled prophecy should pay its reward in might")
	check(unlocked.has("uprising"), "witnessing an uprising should be a feat")
	check(unlocked.has("first_prophecy"), "a first fulfilled prophecy should be a feat")
	check(Oracle.is_unlocked("uprising"), "a feat should be kept once unlocked")


func _a_deadline_fails_a_prophecy() -> void:
	var tick := SimClock.current_tick
	var p := ProphecyBook._make(ProphecyBook.GROWTH, "", "", 1.0e9, tick, 1, 30, "test", "test")
	p["state"] = "active"
	Oracle.prophecies.append(p)
	var might := Oracle.might
	SimTestHarness.advance(20)
	check(Oracle.prophecies.is_empty(), "a prophecy past its deadline should be settled")
	check_eq(String(Oracle.record.back()["state"]), "failed", "it should be recorded as failed")
	check(Oracle.might <= might + 5.01, "a failed prophecy should pay nothing beyond the year's might")


func _judging_reads_the_world() -> void:
	var tick := SimClock.current_tick
	var ranked := PowerCalculator.ranked(-1)
	var first := ProphecyBook._make(ProphecyBook.HEGEMONY, String(ranked[0].org_id), "", 0.0,
		tick, 30, 30, "", "")
	check_eq(ProphecyBook.judge(first, tick), ProphecyBook.Verdict.FULFILLED,
		"the strongest organization should already hold first place")
	var second := ProphecyBook._make(ProphecyBook.HEGEMONY, String(ranked[1].org_id), "", 0.0,
		tick, 30, 30, "", "")
	check_eq(ProphecyBook.judge(second, tick), ProphecyBook.Verdict.PENDING,
		"the second strongest should not")
	var gone := ProphecyBook._make(ProphecyBook.EXTINCTION, "no_such_house", "", 0.0, tick, 30, 30, "", "")
	check_eq(ProphecyBook.judge(gone, tick), ProphecyBook.Verdict.FULFILLED,
		"a house that does not exist has died out")
	var shrink := ProphecyBook._make(ProphecyBook.DECLINE, "", "", GameState.world.global_population + 1.0,
		tick, 30, 30, "", "")
	check_eq(ProphecyBook.judge(shrink, tick), ProphecyBook.Verdict.FULFILLED,
		"a population already under the mark has fallen to it")
	for kind in ProphecyBook.KINDS:
		var line := ProphecyBook.progress(ProphecyBook._make(kind, "", "", 0.0, tick, 30, 30, "", ""), tick)
		check(line != null, "progress should read for %s" % kind)


func _calamities_cost_might() -> void:
	var free := Oracle.free_mode()
	Oracle.set_free_mode(false)
	Oracle.might = 10.0
	var running := GameState.world.active_disasters.size()
	check(not Oracle.call_down(&"plague"), "a plague should be out of reach with too little might")
	check_eq(GameState.world.active_disasters.size(), running, "an unpaid calamity should not happen")
	Oracle.might = 50.0
	check(Oracle.call_down(&"plague"), "a plague should be called down when it can be paid for")
	check_near(Oracle.might, 50.0 - Oracle.CALAMITY_COST[&"plague"], 0.01, "the plague should cost its price")
	Oracle.set_free_mode(true)
	Oracle.might = 0.0
	check(Oracle.call_down(&"blessed_grove"), "in free mode a calamity should cost nothing")
	Oracle.set_free_mode(free)


func _the_oracle_survives_a_save() -> void:
	Oracle.might = 42.0
	Oracle.current_offers()
	Oracle.declare(0)
	var before := Oracle.to_dict()
	var wire: Dictionary = JSON.parse_string(JSON.stringify(before))
	Oracle.from_dict(wire)
	check_eq(JSON.stringify(Oracle.to_dict()), JSON.stringify(before),
		"the oracle's state should come back from a save as it went in")
	check_eq(typeof(Oracle.prophecies[0]["deadline"]), TYPE_INT,
		"ticks should come back from a save as whole numbers")


func _the_history_reads_as_chapters() -> void:
	var chapters := EraBook.chapters()
	check_eq(chapters.size(), EraBook.current_index() + 1,
		"there should be a chapter for every fifty years so far, and the one being written")
	check(not chapters[0]["complete"], "the newest chapter should still be being written")
	for i in chapters.size():
		var chapter: Dictionary = chapters[i]
		check(not String(chapter["title"]).is_empty(), "every chapter should have a name")
		check(not chapter["lines"].is_empty(), "every chapter should say something about itself")
		check_eq(int(chapter["number"]), chapters.size() - i, "chapters should run newest first")
	var again := EraBook.chapters()
	for i in chapters.size():
		check_eq(again[i]["title"], chapters[i]["title"], "the same history should give the same book")


func _a_prophecy_races_its_deadline() -> void:
	var tick := SimClock.current_tick
	Oracle.prophecies.clear()
	for kind in ProphecyBook.KINDS:
		var near := ProphecyBook.closeness(ProphecyBook._make(kind, "", "", 0.0, tick, 30, 30, "", ""), tick)
		check(near >= -1.0 and near <= 1.0, "closeness should be a share or unknown for %s" % kind)
	var top := PowerCalculator.ranked(-1)[0]
	check_near(ProphecyBook.closeness(ProphecyBook._make(ProphecyBook.HEGEMONY, String(top.org_id),
		"", 0.0, tick, 30, 30, "", ""), tick), 1.0, 0.001, "the strongest stands at its own goal")
	check_eq(ProphecyBook.headline({"text": "30年のうちに、甲が乙となる"}), "甲が乙となる",
		"a headline should drop the deadline")
	check_eq(ProphecyBook.stars({"reward": 40}), 1, "a modest prophecy is one star")
	check_eq(ProphecyBook.stars({"reward": 120}), 3, "a bold prophecy is three")

	# Sixty people from a hundred toward the goal: past the first mark, not the second.
	var population := GameState.world.global_population
	var p := ProphecyBook._make(ProphecyBook.GROWTH, "", "", population + 40.0, tick, 40, 35,
		"40年のうちに、世の人口が増える", "test")
	p["state"] = "active"
	p["base"] = population - 60.0
	p["told"] = 0
	p["warned"] = false
	Oracle.prophecies.append(p)
	var nearing := [0]
	var pressing := [0]
	var on_near := func(_p: Dictionary, _c: float): nearing[0] += 1
	var on_press := func(_p: Dictionary, _y: int): pressing[0] += 1
	Oracle.prophecy_nearing.connect(on_near)
	Oracle.prophecy_pressing.connect(on_press)
	Oracle._watch_progress(tick)
	Oracle._watch_progress(tick)
	check_eq(nearing[0], 1, "drawing near should be said once, not every season")
	check_eq(pressing[0], 0, "forty years is not yet short of time")
	p["deadline"] = tick + 3 * SimConfig.TICKS_PER_YEAR
	Oracle._watch_progress(tick)
	Oracle._watch_progress(tick)
	check_eq(pressing[0], 1, "running short of time should be said once")
	Oracle.prophecy_nearing.disconnect(on_near)
	Oracle.prophecy_pressing.disconnect(on_press)
	Oracle.prophecies.clear()


func _portents_read_the_world() -> void:
	var tick := SimClock.current_tick
	var world_before := JSON.stringify(GameState.to_dict())
	var rng_before := JSON.stringify(RngService.to_dict())
	Oracle.prophecies.clear()
	Oracle.record.clear()
	var portents := Portents.current(tick)
	check(not portents.is_empty(), "there is always something to say about the world")
	check_eq(String(portents[0]["tab"]), "god",
		"a god who has foretold nothing is first told to foretell something")
	for i in portents.size():
		var item: Dictionary = portents[i]
		check(not String(item["title"]).is_empty(), "every portent should say what it is")
		check(not String(item["tab"]).is_empty(), "every portent should say where to look")
		if i > 0:
			check(float(portents[i - 1]["weight"]) >= float(item["weight"]),
				"portents should run most pressing first")
	check(portents.size() <= Portents.MAX_ITEMS, "the list should stay short enough to read")
	check_eq(JSON.stringify(GameState.to_dict()), world_before, "reading portents should not change the world")
	check_eq(JSON.stringify(RngService.to_dict()), rng_before,
		"reading portents should not draw on the world's randomness")

	Oracle.current_offers()
	Oracle.declare(0)
	var spoken := Portents.current(tick)
	var found := false
	for item in spoken:
		found = found or (String(item["label"]) == "神託" and String(item["title"])
			== ProphecyBook.headline(Oracle.prophecies[0]))
	check(found, "a spoken prophecy should be among the portents")
	Oracle.prophecies.clear()


func _kin_bear_the_same_arms() -> void:
	var founders := {}
	var cadets := 0
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE, false):
		if house.is_noble() and house.founding_tick == 0:
			founders["%d/%s" % [Crest.device_of(house), Crest.metal_of(house).to_html()]] = true
		var parent := GameState.get_organization(house.parent_org_id)
		if house.founding_tick > 0 and parent != null and parent.kind == Organization.OrgKind.HOUSE:
			cadets += 1
			check_eq(Crest.device_of(house), Crest.device_of(parent),
				"%s should bear the device of the house it left" % house.display_name)
			check(Crest.are_kin(house, parent), "a cadet and its parent are of one line")
	# Families raised to the peerage since the founding bring arms of their own
	# as well, so there may be more than there were founders — never fewer.
	check(founders.size() >= WorldGenerator.SETTLEMENT_COUNT,
		"each founding house should have arms of its own (%d kinds)" % founders.size())
	check_gt(float(cadets), 0.0, "the test world should have cadet houses to check")

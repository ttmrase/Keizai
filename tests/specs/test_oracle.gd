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

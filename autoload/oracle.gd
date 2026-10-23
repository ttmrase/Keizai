extends Node

## The god's side of the bargain: what the god has foretold, what it has to spend,
## and what it has seen.
##
## The simulation lets the god change the world and nothing else, and that stays
## true. What was missing was a reason to change it. The oracle supplies three:
##
## * 神託 — prophecies. The god foretells something the world might do (a
##   family on the throne, a guild above all, a rupture, an extinction), with a
##   deadline, and then has only the dials and the calamities to bring it about.
##   A prophecy that comes true pays out in might.
## * 神威 — might. Calamities cost it; time and fulfilled prophecies bring it.
##   A god who can call down a plague whenever it likes has no reason to think
##   about which one. (A setting lifts the cost for those who want a sandbox.)
## * 史録 — feats, kept across every world: what this god has witnessed.
##
## It reads the world and never writes it, except through GodPowerAPI exactly as
## the god panel always did. It draws from its own random generator, never the
## world's, so asking for a prophecy cannot change what history does next.

signal might_changed(value: float)
signal prophecies_changed()
signal prophecy_resolved(prophecy: Dictionary)
signal feat_unlocked(feat: Dictionary)

const START_MIGHT := 60.0
const MAX_MIGHT := 150.0
## Gained every year, whatever happens.
const MIGHT_PER_YEAR := 1.0
const MAX_ACTIVE := 3
const REROLL_COST := 5.0
const OFFER_COUNT := 3
## Offers this old are replaced, because the world they were drawn from has
## moved on.
const OFFER_SHELF_LIFE := 10 * SimConfig.TICKS_PER_YEAR
const RECORD_KEEP := 40

## What each calamity and blessing costs. Blessings are cheaper than ruin, and a
## plague — which can end a family — is the dearest of all.
const CALAMITY_COST := {
	&"drought": 30,
	&"plague": 45,
	&"wildfire": 25,
	&"monster_incursion": 35,
	&"bountiful_harvest": 20,
	&"mineral_strike": 20,
	&"blessed_grove": 15,
}

var annals_path := "user://annals.cfg"

# ---- this world (saved with it)
var might := START_MIGHT
var prophecies: Array = []
var record: Array = []
var offers: Array = []
var offers_tick := -1
var next_id := 1
var calls_by_kind: Dictionary = {}
var call_ticks: Array = []
var last_call_tick := 0
var last_turmoil_tick := 0
var last_royal := ""

# ---- every world (user://annals.cfg)
var _annals: ConfigFile
var _feats_open: Array = []


func _ready() -> void:
	EventBus.tick_advanced.connect(_on_tick)
	EventBus.event_recorded.connect(_on_event)
	EventBus.power_recalculated.connect(_on_epoch)
	EventBus.world_reset.connect(_on_world_reset)


# ----------------------------------------------------------------- might

func free_mode() -> bool:
	return bool(_load_annals().get_value("prefs", "free_mode", false))


func set_free_mode(on: bool) -> void:
	_load_annals().set_value("prefs", "free_mode", on)
	_save_annals()
	might_changed.emit(might)


func cost_of(definition_id: StringName) -> int:
	return 0 if free_mode() else int(CALAMITY_COST.get(definition_id, 30))


func can_afford(definition_id: StringName) -> bool:
	return might >= float(cost_of(definition_id))


## Calls a calamity or blessing down, if the god can pay for it.
func call_down(definition_id: StringName) -> bool:
	if not can_afford(definition_id):
		return false
	if GodPowerAPI.trigger_disaster(definition_id, &"", 1.0) == null:
		return false
	_spend(float(cost_of(definition_id)))
	_note_call(definition_id, SimClock.current_tick)
	return true


func _gain(amount: float) -> void:
	might = minf(MAX_MIGHT, might + amount)
	might_changed.emit(might)


func _spend(amount: float) -> void:
	might = maxf(0.0, might - amount)
	might_changed.emit(might)


func _on_tick(tick: int) -> void:
	if tick > 0 and tick % SimConfig.TICKS_PER_YEAR == 0 and might < MAX_MIGHT:
		_gain(MIGHT_PER_YEAR)


# ------------------------------------------------------------ prophecies

## What the god could foretell now. Drawn again when the old offers have gone
## stale or stopped making sense.
func current_offers() -> Array:
	var tick := SimClock.current_tick
	var stale := offers.is_empty() or offers_tick < 0 or tick - offers_tick > OFFER_SHELF_LIFE
	if not stale:
		for offer in offers:
			if ProphecyBook.judge(offer, tick) != ProphecyBook.Verdict.PENDING:
				stale = true
	if stale:
		_draw_offers(tick)
	elif offers.size() < OFFER_COUNT:
		_top_up(tick)
	return offers


## Throws the offers away and draws new ones, for a little might.
func reroll() -> bool:
	var price := 0.0 if free_mode() else REROLL_COST
	if might < price:
		return false
	_spend(price)
	_draw_offers(SimClock.current_tick)
	prophecies_changed.emit()
	return true


func _draw_offers(tick: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([GameState.world.seed if GameState.world != null else 0, tick, next_id,
		offers_tick])
	offers = ProphecyBook.offers(rng, tick, prophecies, OFFER_COUNT)
	offers_tick = tick


## Speaking a prophecy takes it off the table; the table is filled again, so the
## god always has a choice of futures rather than whatever was left over.
func _top_up(tick: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([GameState.world.seed if GameState.world != null else 0, tick, next_id,
		offers.size()])
	var spoken := prophecies + offers
	for candidate in ProphecyBook.offers(rng, tick, spoken, OFFER_COUNT):
		if offers.size() >= OFFER_COUNT:
			break
		var same_kind := false
		for offer in offers:
			same_kind = same_kind or offer["kind"] == candidate["kind"]
		if not same_kind:
			offers.append(candidate)


## Speaks one of the offers. It is judged against the world from this moment.
func declare(index: int) -> bool:
	if prophecies.size() >= MAX_ACTIVE or index < 0 or index >= offers.size():
		return false
	var tick := SimClock.current_tick
	var p: Dictionary = offers[index].duplicate(true)
	p["state"] = "active"
	p["declared"] = tick
	p["deadline"] = tick + int(p["years"]) * SimConfig.TICKS_PER_YEAR
	p["met"] = false
	p["id"] = next_id
	next_id += 1
	offers.remove_at(index)
	prophecies.append(p)
	prophecies_changed.emit()
	_judge_all(tick)
	return true


func _judge_all(tick: int) -> void:
	for p in prophecies.duplicate():
		var verdict := ProphecyBook.judge(p, tick)
		if verdict != ProphecyBook.Verdict.PENDING:
			_resolve(p, verdict == ProphecyBook.Verdict.FULFILLED, tick)


func _resolve(p: Dictionary, fulfilled: bool, tick: int) -> void:
	prophecies.erase(p)
	p["state"] = "fulfilled" if fulfilled else "failed"
	p["resolved"] = tick
	record.append(p)
	while record.size() > RECORD_KEEP:
		record.pop_front()
	if fulfilled:
		_gain(float(p["reward"]))
	prophecies_changed.emit()
	prophecy_resolved.emit(p)
	_note_prophecy(p, fulfilled)


## Whether a spoken prophecy names this family, body or person, so the screens
## can mark whoever the god is watching.
func is_foretold(id: StringName) -> bool:
	for p in prophecies:
		if StringName(p["target"]) == id:
			return true
	return false


func fulfilled_count() -> int:
	var n := 0
	for p in record:
		if p["state"] == "fulfilled":
			n += 1
	return n


# --------------------------------------------------------------- listening

func _on_event(e: HistoryEvent) -> void:
	var met := false
	for p in prophecies:
		if not p["met"]:
			ProphecyBook.notice(p, e)
			met = met or bool(p["met"])
	if met:
		_judge_all(e.tick)
	_feats_from_event(e)


func _on_epoch(tick: int) -> void:
	_judge_all(tick)
	_feats_from_world(tick)


func _on_world_reset() -> void:
	might = START_MIGHT
	prophecies.clear()
	record.clear()
	offers.clear()
	offers_tick = -1
	next_id = 1
	calls_by_kind.clear()
	call_ticks.clear()
	# A new world starts at the beginning of time, whatever the clock still says
	# about the last one.
	last_call_tick = 0
	last_turmoil_tick = 0
	last_royal = ""
	var annals := _load_annals()
	var worlds := int(annals.get_value("tally", "worlds", 0)) + 1
	annals.set_value("tally", "worlds", worlds)
	_save_annals()
	if worlds >= 3:
		_unlock("many_worlds")
	might_changed.emit(might)
	prophecies_changed.emit()


# ------------------------------------------------------------------ feats

func is_unlocked(id: String) -> bool:
	return _load_annals().has_section_key("feats", id)


func unlocked_on(id: String) -> Dictionary:
	return _load_annals().get_value("feats", id, {})


func unlocked_count() -> int:
	var annals := _load_annals()
	return annals.get_section_keys("feats").size() if annals.has_section("feats") else 0


func _unlock(id: String) -> void:
	if is_unlocked(id):
		return
	var feat := Feats.find(id)
	if feat.is_empty():
		return
	var when := {"year": SimClock.year(),
		"seed": GameState.world.seed if GameState.world != null else 0}
	_load_annals().set_value("feats", id, when)
	_save_annals()
	var shown := feat.duplicate()
	shown.merge(when)
	feat_unlocked.emit(shown)


func _feats_from_event(e: HistoryEvent) -> void:
	match e.event_type:
		HistoryEvent.EventType.SCHISM:
			var kind := String(e.payload.get("schism_kind", ""))
			if kind == "refounding":
				_unlock("refounding")
				last_turmoil_tick = e.tick
			elif kind == "revelation":
				_unlock("new_god")
			else:
				var org := GameState.get_organization(e.subject_org_id)
				if org != null and org.kind == Organization.OrgKind.HOUSE:
					_unlock("first_branch")
		HistoryEvent.EventType.INCIDENT:
			last_turmoil_tick = e.tick
			var kind := String(e.payload.get("incident_kind", ""))
			_unlock(kind)
			var annals := _load_annals()
			var seen: Array = annals.get_value("tally", "incidents_seen", [])
			if not seen.has(kind):
				seen.append(kind)
				annals.set_value("tally", "incidents_seen", seen)
				_save_annals()
			if seen.size() >= Feats.INCIDENT_FEATS.size():
				_unlock("four_ruptures")
		HistoryEvent.EventType.POWER_TRANSFER:
			if bool(e.payload.get("regime_change", false)):
				last_turmoil_tick = e.tick
				_unlock("regime")
		HistoryEvent.EventType.DISSOLVED:
			var org := GameState.get_organization(e.subject_org_id)
			if org != null and org.is_noble():
				_unlock("extinction")


func _feats_from_world(tick: int) -> void:
	var royal := String(HouseRank.royal_house_id())
	if not royal.is_empty():
		if not last_royal.is_empty() and royal != last_royal:
			_unlock("dynasty")
		last_royal = royal

	var years := float(tick) / float(SimConfig.TICKS_PER_YEAR)
	if years >= 1000.0:
		_unlock("millennium")
	if GameState.world.global_population >= 20000.0:
		_unlock("great_population")
	if tick - last_turmoil_tick >= 100 * SimConfig.TICKS_PER_YEAR:
		_unlock("golden_peace")
	if tick - last_call_tick >= 200 * SimConfig.TICKS_PER_YEAR:
		_unlock("idle_god")

	var faiths := {}
	for id in GameState.world.settlements:
		faiths[GameState.world.settlements[id].religion_id] = true
	if faiths.size() >= 3:
		_unlock("faiths_divided")

	var old_enough := tick - 500 * SimConfig.TICKS_PER_YEAR
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.is_noble() and house.rank_tier >= HouseRank.TIER_NAMES.size() - 1:
			_unlock("duke")
		if house.member_count >= 25:
			_unlock("great_house")
		if old_enough >= 0 and house.founding_tick <= old_enough:
			_unlock("five_centuries")

	# The oldest living person changes slowly; looking every ten epochs is plenty.
	if not is_unlocked("centenarian") and (tick / SimConfig.POWER_RECALC_EPOCH_TICKS) % 10 == 0:
		for person in GameState.living_people():
			if person.age_years(tick) >= 100:
				_unlock("centenarian")
				break


func _note_call(definition_id: StringName, tick: int) -> void:
	calls_by_kind[String(definition_id)] = int(calls_by_kind.get(String(definition_id), 0)) + 1
	if calls_by_kind.size() >= CALAMITY_COST.size():
		_unlock("seven_calamities")
	call_ticks.append(tick)
	while not call_ticks.is_empty() and tick - int(call_ticks[0]) > 10 * SimConfig.TICKS_PER_YEAR:
		call_ticks.pop_front()
	if call_ticks.size() >= 4:
		_unlock("wrath")
	last_call_tick = tick


func _note_prophecy(p: Dictionary, fulfilled: bool) -> void:
	if not fulfilled:
		_unlock("failed_prophecy")
		return
	var annals := _load_annals()
	var total := int(annals.get_value("tally", "fulfilled", 0)) + 1
	annals.set_value("tally", "fulfilled", total)
	_save_annals()
	_unlock("first_prophecy")
	if total >= 10:
		_unlock("ten_prophecies")
	if int(p["reward"]) >= 100:
		_unlock("bold_prophecy")


func _load_annals() -> ConfigFile:
	if _annals == null:
		_annals = ConfigFile.new()
		_annals.load(annals_path)
	return _annals


func _save_annals() -> void:
	_load_annals().save(annals_path)


## Points the cross-world record somewhere else — the test suite and the
## screenshot tool use this so they never write into a player's own record.
func use_annals(path: String) -> void:
	annals_path = path
	_annals = null


# ------------------------------------------------------------------- saving

func to_dict() -> Dictionary:
	return {
		"might": might,
		"prophecies": prophecies.duplicate(true),
		"record": record.duplicate(true),
		"offers": offers.duplicate(true),
		"offers_tick": offers_tick,
		"next_id": next_id,
		"calls_by_kind": calls_by_kind.duplicate(),
		"call_ticks": call_ticks.duplicate(),
		"last_call_tick": last_call_tick,
		"last_turmoil_tick": last_turmoil_tick,
		"last_royal": last_royal,
	}


## A save from before the oracle existed restores to a fresh one.
func from_dict(d: Dictionary) -> void:
	might = float(d.get("might", START_MIGHT))
	prophecies = _numbers_fixed(d.get("prophecies", []))
	record = _numbers_fixed(d.get("record", []))
	offers = _numbers_fixed(d.get("offers", []))
	offers_tick = int(d.get("offers_tick", -1))
	next_id = int(d.get("next_id", 1))
	calls_by_kind = {}
	var calls: Dictionary = d.get("calls_by_kind", {})
	for kind in calls:
		calls_by_kind[String(kind)] = int(calls[kind])
	call_ticks = []
	for t in d.get("call_ticks", []):
		call_ticks.append(int(t))
	last_call_tick = int(d.get("last_call_tick", SimClock.current_tick))
	last_turmoil_tick = int(d.get("last_turmoil_tick", SimClock.current_tick))
	last_royal = String(d.get("last_royal", ""))
	might_changed.emit(might)
	prophecies_changed.emit()


## JSON brings every number back as a float; ticks and ids are compared as ints.
static func _numbers_fixed(list: Array) -> Array:
	var out: Array = []
	for item in list:
		var p: Dictionary = item.duplicate(true)
		for key in ["declared", "deadline", "years", "reward", "resolved", "id"]:
			if p.has(key):
				p[key] = int(p[key])
		out.append(p)
	return out

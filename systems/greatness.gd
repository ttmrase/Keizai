class_name Greatness
extends RefCounted

## 偉人 — the few people later history keeps.
##
## Holding a throne for a long time is not enough, nor is founding something, nor
## leading a guild well. Every world has hundreds of office-holders and the
## histories remember a handful: the founder whose state lasted a century and a
## half, the ruler who found a country with its standing in ruins and left it
## whole, the faith's founder whose teaching came to hold half the world. The bar
## here is the one a short world history would set.
##
## Most of these are judged afterwards. Whether a state lasted cannot be known
## the year it was founded, and whether a family stayed great cannot be known the
## year its head died, so a person is usually recognised long after the fact —
## often long after their death. What is recognised is recorded (GREATNESS) and
## kept forever; nothing about it can be undone by what happens next.
##
## Six fields, so the histories are not all kings:
##   統治  founders of states that last, restorers, good long reigns
##   武    who won the civil wars, from behind or for good; who beat back the monsters
##   信仰  founders of faiths that took hold, and those who spread them
##   富と技 founders of the first guild of its kind, when it came to lead the world
##   変革  who brought a state down and put something lasting in its place
##   家門  heads who raised their families two ranks, for good

const FIELDS := ["rule", "arms", "faith", "craft", "change", "house"]

const FIELD_LABELS := {
	"rule": "統治",
	"arms": "武",
	"faith": "信仰",
	"craft": "富と技",
	"change": "変革",
	"house": "家門",
}

const FIELD_GLYPHS := {
	"rule": &"crown",
	"arms": &"swords",
	"faith": &"altar",
	"craft": &"coin",
	"change": &"banner",
	"house": &"seal",
}

## What it would take, for the shelves nobody stands on yet.
const FIELD_HINTS := {
	"rule": "国を開いて百二十年続かせる。傾いた国を立て直す。三十年の治世で民を三割増やし、乱を一度も起こさない",
	"arms": "内戦を勝ち抜いて国を一つに戻す。劣勢の側を勝たせる。魔物の極まった時代を鎮める",
	"faith": "興した信仰が世の半ばに広がる、あるいは二百年のあいだ三地方以上に根付く。信仰を大きく広げる",
	"craft": "世で最初の商い・職人・魔術・討伐のギルドを興し、それが世で最も力ある組織になる",
	"change": "体制を倒し、その新しい秩序を百三十年以上続かせる",
	"house": "当主として家格を二段以上引き上げて公爵か王家に至らせ、五十年後もその家をそこに留める",
}

# --- 統治 ---
const FOUNDER_YEARS := 120
const FOUNDER_REIGN_YEARS := 8
const RESTORER_REIGN_YEARS := 20
const RESTORER_LOW := 0.35
const RESTORER_HIGH := 0.75
const GOOD_REIGN_YEARS := 30
const GOOD_REIGN_GROWTH := 1.3
const GOOD_REIGN_FLOOR := 0.6
# --- 武 ---
const WAR_MIN_YEARS := 3
const WAR_MIN_BATTLES := 3
const UNIFIER_YEARS := 6
## The winner's ruler must have held the seat for at least this share of the war:
## a war is not won by whoever happened to inherit it the season it ended.
const COMMAND_SHARE := 0.5
const WARDEN_PEAK := 0.85
const WARDEN_CALM := 0.35
const WARDEN_YEARS := 15
# --- 信仰 ---
const PROPHET_REACH := 0.5
const PROPHET_YEARS := 200
const PROPHET_REGIONS := 3
## A faith that only takes hold centuries later is its later teachers' work,
## not its founder's: "lasting" is judged in the century after PROPHET_YEARS.
const PROPHET_WINDOW := 100
const APOSTLE_GAIN := 4
const APOSTLE_REACH := 0.6
# --- 富と技 ---
const GUILD_FOUNDER_ARCHETYPES := {
	&"merchants_guild": "商祖",
	&"artisans_guild": "工祖",
	&"mage_guild": "魔導の祖",
	&"monster_hunters_guild": "討伐の祖",
}
# --- 変革 ---
const CHANGE_YEARS := 130
# --- 家門 ---
const HOUSE_RISE := 2.0
## Only a rise to the very top counts: a duke's coronet, or a crown.
const HOUSE_PEAK := HouseRank.NOBLE_PRECEDENCE_BASE + 4.0
## And fifty years on it must still be there.
const HOUSE_KEPT := HouseRank.NOBLE_PRECEDENCE_BASE + 4.0
const HOUSE_WAIT_YEARS := 50


# =================================================================== readers

static func all() -> Array[Dictionary]:
	return GameState.greats


static func in_field(field: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in GameState.greats:
		if entry["field"] == field:
			out.append(entry)
	return out


static func is_great(person_id: StringName) -> bool:
	var id := String(person_id)
	for entry in GameState.greats:
		if entry["person_id"] == id:
			return true
	return false


static func entries_of(person_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var id := String(person_id)
	for entry in GameState.greats:
		if entry["person_id"] == id:
			out.append(entry)
	return out


static func field_label(field: String) -> String:
	return FIELD_LABELS.get(field, field)


static func _already(person_id: StringName, field: String) -> bool:
	var id := String(person_id)
	for entry in GameState.greats:
		if entry["person_id"] == id and entry["field"] == field:
			return true
	return false


# ===================================================================== yearly

static func step(tick: int) -> void:
	if tick % SimConfig.TICKS_PER_YEAR != 3:
		return
	_watch_reigns(tick)
	_judge_founders(tick)
	_judge_pending(tick)


# -------------------------------------------------------------------- reigns

## Keeps each seat's record of its current head's time in it, and judges a reign
## the year it is seen to have ended.
static func _watch_reigns(tick: int) -> void:
	for org in GameState.active_organizations():
		if not _watched(org):
			continue
		var marks := org.reign_marks
		var ruler := String(org.leader_person_id)
		if String(marks.get("ruler", "")) != ruler:
			if String(marks.get("ruler", "")) != "":
				_judge_reign(org, marks, tick)
			_open_marks(org, ruler, tick)
		elif ruler != "":
			_update_marks(org, marks, tick)


static func _watched(org: Organization) -> bool:
	match org.kind:
		Organization.OrgKind.POLITICAL_SYSTEM, Organization.OrgKind.RELIGION:
			return true
		Organization.OrgKind.GUILD:
			return org.archetype_id == &"monster_hunters_guild"
		Organization.OrgKind.HOUSE:
			return org.standing != Organization.Standing.COMMONER
	return false


static func _open_marks(org: Organization, ruler: String, tick: int) -> void:
	var kept: Array = org.reign_marks.get("judged", [])
	var marks := {"ruler": ruler, "judged": kept}
	if ruler != "":
		marks["start"] = tick
		marks["low"] = org.legitimacy
		marks["min"] = org.legitimacy
		marks["people"] = _people_of(org)
		marks["regions"] = Religion._regions_holding(org.org_id) \
			if org.kind == Organization.OrgKind.RELIGION else 0
		marks["peak"] = GameState.world.global_monster_threat_level
		marks["rank"] = HouseRank.precedence(org) if org.kind == Organization.OrgKind.HOUSE else 0.0
		marks["calm"] = true
	org.reign_marks = marks


static func _update_marks(org: Organization, marks: Dictionary, tick: int) -> void:
	marks["low"] = minf(float(marks.get("low", 1.0)), org.legitimacy)
	marks["min"] = minf(float(marks.get("min", 1.0)), org.legitimacy)
	marks["peak"] = maxf(float(marks.get("peak", 0.0)), GameState.world.global_monster_threat_level)
	if org.kind == Organization.OrgKind.POLITICAL_SYSTEM and bool(marks.get("calm", true)):
		var start := int(marks.get("start", tick))
		if CivilWar.is_at_war(org.org_id) \
				or int(org.last_fired_tick.get(&"regime_shift", -999999)) >= start \
				or int(org.last_fired_tick.get(&"war", -999999)) >= start:
			marks["calm"] = false
		else:
			for kind in Incidents.KIND_LABELS:
				if Incidents.last_tick(kind) >= start:
					marks["calm"] = false
					break


static func _people_of(org: Organization) -> float:
	var total := 0.0
	for id in org.governs_settlement_ids:
		var s: SettlementState = GameState.world.settlements.get(id)
		if s != null:
			total += s.population
	return total


## What a reign that has just ended amounted to.
static func _judge_reign(org: Organization, marks: Dictionary, tick: int) -> void:
	var person := GameState.get_person(StringName(marks.get("ruler", "")))
	if person == null:
		return
	var years := int((tick - int(marks.get("start", tick))) / SimConfig.TICKS_PER_YEAR)
	match org.kind:
		Organization.OrgKind.POLITICAL_SYSTEM:
			if not org.is_active():
				return
			if years >= RESTORER_REIGN_YEARS and float(marks.get("low", 1.0)) <= RESTORER_LOW \
					and org.legitimacy >= RESTORER_HIGH:
				_recognise(person, "rule", "中興の祖",
					"傾いた%sの威信を立て直し、%d年にわたって国を保った。" % [
						org.formal_name(), years], [org.origin_event_id], tick)
				return
			var grew := _people_of(org) / maxf(1.0, float(marks.get("people", 0.0)))
			if years >= GOOD_REIGN_YEARS and bool(marks.get("calm", false)) \
					and float(marks.get("min", 0.0)) >= GOOD_REIGN_FLOOR \
					and grew >= GOOD_REIGN_GROWTH:
				_recognise(person, "rule", "名君",
					"%d年の治世のあいだ%sの民は%d%%増え、乱は一度も起きなかった。" % [
						years, org.formal_name(), int((grew - 1.0) * 100.0)],
					[org.origin_event_id], tick)
		Organization.OrgKind.RELIGION:
			var now := Religion._regions_holding(org.org_id)
			var before := int(marks.get("regions", 0))
			if years >= 10 and now - before >= APOSTLE_GAIN \
					and Religion.reach_of(org) >= APOSTLE_REACH:
				_recognise(person, "faith", "伝道の長",
					"%sの長として、その教えを%d地方から%d地方へ広げた。" % [
						org.display_name, before, now], [org.origin_event_id], tick)
		Organization.OrgKind.GUILD:
			if years >= WARDEN_YEARS and float(marks.get("peak", 0.0)) >= WARDEN_PEAK \
					and GameState.world.global_monster_threat_level <= WARDEN_CALM:
				_recognise(person, "arms", "護国の将",
					"魔物の跋扈した時代に%sを率い、その脅威を鎮めた。" % org.formal_name(),
					[org.origin_event_id], tick)
		Organization.OrgKind.HOUSE:
			var start := float(marks.get("rank", 0.0))
			var end := HouseRank.precedence(org)
			if end - start >= HOUSE_RISE and end >= HOUSE_PEAK:
				# Whether it lasted cannot be known yet: fifty years from now.
				GameState.world.great_pending.append({
					"person_id": String(person.person_id),
					"house_id": String(org.org_id),
					"due": tick + HOUSE_WAIT_YEARS * SimConfig.TICKS_PER_YEAR,
					"from": HouseRank.tier_name(_tier_from_precedence(start),
						Organization.Standing.NOBLE if start >= HouseRank.NOBLE_PRECEDENCE_BASE
							else Organization.Standing.RETAINER),
					"to": HouseRank.title_of_house(org),
				})


static func _tier_from_precedence(p: float) -> int:
	if p >= HouseRank.NOBLE_PRECEDENCE_BASE:
		return int(p - HouseRank.NOBLE_PRECEDENCE_BASE)
	return int(p / HouseRank.SERVICE_PRECEDENCE_STEP)


static func _judge_pending(tick: int) -> void:
	var waiting: Array = GameState.world.great_pending
	if waiting.is_empty():
		return
	var still: Array = []
	for entry in waiting:
		if int(entry.get("due", 0)) > tick:
			still.append(entry)
			continue
		var house := GameState.get_organization(StringName(entry.get("house_id", "")))
		var person := GameState.get_person(StringName(entry.get("person_id", "")))
		if house == null or person == null or not house.is_active() or not house.is_noble():
			continue
		if HouseRank.precedence(house) < HOUSE_KEPT:
			continue
		_recognise(person, "house", "家門の祖",
			"%sを%sから%sへと引き上げ、その家は五十年後もなおその座にあった。" % [
				house.formal_name(), entry.get("from", ""), entry.get("to", "")],
			[house.origin_event_id], tick)
	GameState.world.great_pending = still


# ------------------------------------------------------------------ founders

## Founders are judged by what became of what they founded: a state that
## lasted, a faith that spread, a guild that came to lead the world.
static func _judge_founders(tick: int) -> void:
	for org in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM, false):
		if _judged(org, "founder") and _judged(org, "change"):
			continue
		var age := int(((org.dissolved_tick if not org.is_active() else tick) - org.founding_tick)
			/ SimConfig.TICKS_PER_YEAR)
		# Two separate judgements, each made once: who took the state (変革),
		# and who founded it (建国) — the second only for a state nobody took.
		if not _judged(org, "change"):
			if age >= CHANGE_YEARS:
				_judge_change(org, age, tick)
			elif not org.is_active():
				_mark_judged(org, "change")
		if not _judged(org, "founder"):
			if age >= FOUNDER_YEARS:
				_mark_judged(org, "founder")
				if not _taken_by_somebody(org):
					var first := _first_holding(org.org_id)
					if not first.is_empty() and int(first["years"]) >= FOUNDER_REIGN_YEARS:
						_recognise(first["person"], "rule", "建国の父",
							"%sの最初の%sとして国を開き、その国は%s。" % [org.formal_name(),
								org.leadership_title, _lasted(org, age)], [org.origin_event_id], tick)
			elif not org.is_active():
				_mark_judged(org, "founder")

	for faith in GameState.organizations_of_kind(Organization.OrgKind.RELIGION, false):
		if faith.is_root() or _judged(faith, "founder"):
			continue
		var age := int(((faith.dissolved_tick if not faith.is_active() else tick)
			- faith.founding_tick) / SimConfig.TICKS_PER_YEAR)
		var reach := Religion.reach_of(faith) if faith.is_active() else 0.0
		var lasting := faith.is_active() and age >= PROPHET_YEARS \
			and age < PROPHET_YEARS + PROPHET_WINDOW \
			and Religion._regions_holding(faith.org_id) >= PROPHET_REGIONS
		if reach >= PROPHET_REACH or lasting:
			_mark_judged(faith, "founder")
			var first := _first_holding(faith.org_id)
			if not first.is_empty():
				var why := "その教えは世の%d地方を占めるに至った。" % Religion._regions_holding(faith.org_id) \
					if reach >= PROPHET_REACH else "その教えは%d年を経てなお根付いている。" % age
				_recognise(first["person"], "faith", "開祖",
					"%sを開いた。%s" % [faith.display_name, why], [faith.origin_event_id], tick)
		elif not faith.is_active():
			_mark_judged(faith, "founder")

	var leader := _most_powerful()
	for archetype in GUILD_FOUNDER_ARCHETYPES:
		var first_guild := _first_of_archetype(archetype)
		if first_guild == null or _judged(first_guild, "founder"):
			continue
		if not first_guild.is_active():
			_mark_judged(first_guild, "founder")
			continue
		if leader == null or leader.org_id != first_guild.org_id:
			continue
		_mark_judged(first_guild, "founder")
		var first := _first_holding(first_guild.org_id)
		if not first.is_empty():
			_recognise(first["person"], "craft", GUILD_FOUNDER_ARCHETYPES[archetype],
				"世で最初の%sを興し、それは%d年後、世で最も力ある組織となった。" % [
					Palette.kind_label(first_guild.kind) if first_guild.display_name.is_empty()
						else first_guild.display_name,
					int((tick - first_guild.founding_tick) / SimConfig.TICKS_PER_YEAR)],
				[first_guild.origin_event_id], tick)


## Whether a state was founded by somebody bringing the last one down. Asked by
## the 兆し every few seasons, and the answer never changes, so it is kept.
static var _taken_memo: Dictionary = {}


## "百五十年を経てなお続いている" for a state still standing, "百六十年続いた"
## for one that has since ended.
static func _lasted(polity: Organization, age: int) -> String:
	if polity.is_active():
		return "%d年を経てなお続いている" % age
	return "%d年続いた" % age


static func _taken_by_somebody(polity: Organization) -> bool:
	if polity.origin_event_id == &"" or polity.is_root():
		return false
	var key := "%d:%s" % [GameState.world.seed, polity.origin_event_id]
	if _taken_memo.has(key):
		return _taken_memo[key]
	var origin := HistoryLog.find_event(polity.origin_event_id)
	var taken := origin != null and String(origin.payload.get("claimant_leader_id", "")) != ""
	_taken_memo[key] = taken
	return taken


## Whoever led the side that brought the old state down, once it is known that
## what they put in its place lasted.
static func _judge_change(polity: Organization, age: int, tick: int) -> void:
	_mark_judged(polity, "change")
	var origin := HistoryLog.find_event(polity.origin_event_id)
	if origin == null or origin.event_type != HistoryEvent.EventType.SCHISM:
		return
	var kind := String(origin.payload.get("schism_kind", ""))
	if kind != "refounding" and kind != "civil_war":
		return
	var leader := GameState.get_person(StringName(origin.payload.get("claimant_leader_id", "")))
	if leader == null:
		return
	var parent := GameState.get_organization(polity.parent_org_id)
	var claimant := GameState.get_organization(StringName(origin.payload.get("claimant_org_id", "")))
	_recognise(leader, "change", "変革者",
		"%sを率いて%sを倒し、その新しい秩序は%s。" % [
			claimant.formal_name() if claimant != null else "同志",
			parent.formal_name() if parent != null else "旧き国", _lasted(polity, age)],
		[origin.event_id], tick)


## A war won outright, by whoever ruled the winning side at its end. Called by
## CivilWar once the ending is in the record.
static func consider_war(ending: HistoryEvent, tick: int) -> void:
	var outcome := String(ending.payload.get("outcome", ""))
	if outcome == "peace" or outcome == "":
		return
	var years := int(ending.payload.get("years", 0))
	if years < WAR_MIN_YEARS or int(ending.payload.get("battles", 0)) < WAR_MIN_BATTLES:
		return
	var person := GameState.get_person(StringName(ending.payload.get("winner_ruler_id", "")))
	if person == null:
		return
	var winner_id := StringName(ending.payload.get("winner", ""))
	var started := tick - years * SimConfig.TICKS_PER_YEAR
	var seat_from := tick
	for t in person.role_history:
		if t.org_id == winner_id and (t.end_tick < 0 or t.end_tick >= tick - 1):
			seat_from = mini(seat_from, t.start_tick)
	if float(tick - maxi(seat_from, started)) < COMMAND_SHARE * float(tick - started):
		return
	var loser := GameState.get_organization(StringName(ending.payload.get("loser", "")))
	var loser_name := loser.formal_name() if loser != null else "敵"
	if bool(ending.payload.get("underdog", false)):
		_recognise(person, "arms", "名将",
			"劣勢から%sを打ち破り、%d年の戦を勝利に導いた。" % [loser_name, years],
			[ending.event_id], tick)
	elif years >= UNIFIER_YEARS:
		_recognise(person, "arms", "統一者",
			"%d年の戦の末に%sを破り、割れた国を一つに戻した。" % [years, loser_name],
			[ending.event_id], tick)


# ------------------------------------------------------------------ helpers

static func _judged(org: Organization, key: String) -> bool:
	return (org.reign_marks.get("judged", []) as Array).has(key)


static func _mark_judged(org: Organization, key: String) -> void:
	var judged: Array = org.reign_marks.get("judged", [])
	if not judged.has(key):
		judged.append(key)
	org.reign_marks["judged"] = judged


## The first person ever to hold this seat, and for how long.
static func _first_holding(org_id: StringName) -> Dictionary:
	var best: NotableIndividual = null
	var best_tenure: RoleTenure = null
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		for t in p.role_history:
			if t.org_id != org_id:
				continue
			if best_tenure == null or t.start_tick < best_tenure.start_tick \
					or (t.start_tick == best_tenure.start_tick
						and String(p.person_id) < String(best.person_id)):
				best = p
				best_tenure = t
	if best == null:
		return {}
	var ended := best_tenure.end_tick if best_tenure.end_tick >= 0 else SimClock.current_tick
	return {"person": best, "years": int((ended - best_tenure.start_tick) / SimConfig.TICKS_PER_YEAR)}


static func _first_of_archetype(archetype: StringName) -> Organization:
	var best: Organization = null
	for id in GameState.organizations:
		var org: Organization = GameState.organizations[id]
		if org.archetype_id != archetype:
			continue
		if best == null or org.founding_tick < best.founding_tick \
				or (org.founding_tick == best.founding_tick and String(org.org_id) < String(best.org_id)):
			best = org
	return best


static func _most_powerful() -> Organization:
	var best: Organization = null
	for org in GameState.active_organizations():
		if best == null or org.power_score > best.power_score:
			best = org
	return best


static func _recognise(person: NotableIndividual, field: String, title: String,
		text: String, basis: Array, tick: int) -> void:
	if person == null or _already(person.person_id, field):
		return
	var ids: Array = []
	for id in basis:
		if StringName(id) != &"":
			ids.append(String(id))
	var house := GameState.get_organization(person.house_org_id)
	var since := int((tick - person.death_tick) / SimConfig.TICKS_PER_YEAR)
	var when := ""
	if not person.is_alive():
		when = "没後%d年、" % since if since >= 1 else "その死に際して、"
	HistoryLog.emit_event(
		HistoryEvent.EventType.GREATNESS,
		tick,
		"%s%sは「%s」として歴史に名を刻んだ。%s" % [when, person.full_name, title, text],
		{"field": field, "title": title, "text": text, "basis": ids},
		house.org_id if house != null else &"",
		person.person_id,
		StringName(ids[0]) if not ids.is_empty() else &"")

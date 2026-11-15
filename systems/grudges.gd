class_name Grudges
extends RefCounted

## 遺恨 — who resents whom, and why.
##
## A grudge is not an opinion that drifts on its own. It is a fact with a cause:
## the house that lost a disputed succession resents the house that won it; the
## family pushed down the order of heirs resents the ones that went past; the
## family whose estates were handed to another after a war resents the one that
## took them. Each is written by GameState.apply from the event that caused it,
## so every grudge points back at the thing that happened — and nothing new can
## be resented without something new having happened.
##
## What changes with time is only how much it still burns: a grudge fades over
## decades, a little faster each time the house that holds it changes head, and
## is deepened by anything new between the same two families. That is worked
## out on reading, so the record never has to be rewritten just because a year
## went by.
##
## Kept apart from HouseRelations, which reads it: a relation says how two houses
## get on, a grudge says what one of them has not forgiven, and why.

## How much of a grudge a year takes away (half in about sixty years).
const YEARLY_FADE := 0.0115
## What a new head of the house that holds it lets go of.
const HEAD_CHANGE := 0.85
## Below this nobody remembers it any more.
const FORGOTTEN := 0.05
const CEILING := 1.5
## Most causes recorded per grudge — the first and the most recent matter.
const KEPT_CAUSES := 4

## How hard each kind of thing is held against whoever did it.
const FROM_SUCCESSION := {"retirement": 0.55, "departure": 0.85, "disinheritance": 1.0}
const FROM_HEIRS := 0.75
const FROM_DISPLACED := 0.3
const FROM_ESTATE := 0.6
const FROM_STRIPPED := 0.35
const FROM_EXCOMMUNICATION := 0.55
const FROM_ASSASSINATION := 0.9
const FROM_INTRIGUE_LOSS := 0.9
const FROM_STALEMATE := 0.35
## Revenge taken: a house that has brought down the family it resented holds
## only this much of it afterwards.
const SATISFIED := 0.45

const KIND_LABELS := {
	"succession": "家督争い",
	"seat": "継承争い",
	"heirs": "跡目の順位",
	"displaced": "要職の交代",
	"estate": "戦後の所領",
	"stripped": "家格の削減",
	"excommunication": "破門",
	"assassination": "暗殺",
	"intrigue": "政争",
}


static func settled(d: Dictionary) -> Dictionary:
	var g := d.duplicate(true)
	for field in ["id", "updated", "since", "generations", "root_since"]:
		g[field] = int(g.get(field, 0))
	g["strength"] = float(g.get("strength", 0.0))
	for field in ["holder", "target", "holder_person", "target_person", "cause", "kind", "why",
			"root_kind"]:
		g[field] = String(g.get(field, ""))
	var causes: Array = []
	for c in g.get("causes", []):
		causes.append(String(c))
	g["causes"] = causes
	return g


# ===================================================================== reading

## How much a grudge still burns at a given moment.
static func strength_of(g: Dictionary, tick: int = -1) -> float:
	if tick < 0:
		tick = SimClock.current_tick
	var years := maxf(0.0, float(tick - int(g.get("updated", tick))) / SimConfig.TICKS_PER_YEAR)
	return float(g.get("strength", 0.0)) * pow(1.0 - YEARLY_FADE, years)


## The house a grudge is held by. A quarrel inside one family is held by the
## person who lost it until they belong somewhere else — a cadet line of their
## own, or the house that took them in — and from then on by that house.
static func holder_of(g: Dictionary) -> StringName:
	var holder := StringName(g.get("holder", ""))
	if holder != StringName(g.get("target", "")):
		return holder
	var person := GameState.get_person(StringName(g.get("holder_person", "")))
	if person != null and person.is_alive() and person.house_org_id != &"":
		return person.house_org_id
	return holder


## How much one house resents another, now.
static func toward(holder_id: StringName, target_id: StringName, tick: int = -1) -> float:
	if holder_id == target_id or holder_id == &"" or target_id == &"":
		return 0.0
	return float(table(tick).get("%s|%s" % [holder_id, target_id], 0.0))


## Every live grudge at once, as "holder|target" -> strength — for a pass that
## asks about every pair of houses, which would otherwise rescan the list for
## each of them.
static func table(tick: int = -1) -> Dictionary:
	if tick < 0:
		tick = SimClock.current_tick
	# Asked for by every family's loyalty, every pair's relation and every court
	# in the same season: worked out once for as long as nothing has changed.
	var signature := [tick, GameState.world, _version, GameState.world.next_grudge_id,
		GameState.world.grudges.size(), GameState.people.size()]
	if signature == _table_signature:
		return _table
	var out := {}
	for g in GameState.world.grudges:
		var holder := holder_of(g)
		if holder == StringName(g["target"]):
			continue
		var s := strength_of(g, tick)
		if s < FORGOTTEN:
			continue
		var key := "%s|%s" % [holder, g["target"]]
		out[key] = maxf(float(out.get(key, 0.0)), s)
	_table_signature = signature
	_table = out
	return out


## Bumped by every write, so a reading taken earlier in the same season is
## never mistaken for a current one.
static var _version := 0
static var _table_signature: Array = []
static var _table: Dictionary = {}


## The record itself, for the strongest grudge one house holds against another.
static func between(holder_id: StringName, target_id: StringName, tick: int = -1) -> Dictionary:
	var best := {}
	var most := FORGOTTEN
	for g in GameState.world.grudges:
		if StringName(g["target"]) != target_id or holder_of(g) != holder_id:
			continue
		var s := strength_of(g, tick)
		if s >= most:
			most = s
			best = g
	return best


## Every grudge a house holds that is still remembered, the strongest first.
static func held_by(house_id: StringName, tick: int = -1) -> Array[Dictionary]:
	return _filtered(func(g: Dictionary) -> bool:
		return holder_of(g) == house_id and StringName(g["target"]) != house_id, tick)


## Every grudge held against a house.
static func against(house_id: StringName, tick: int = -1) -> Array[Dictionary]:
	return _filtered(func(g: Dictionary) -> bool:
		return StringName(g["target"]) == house_id and holder_of(g) != house_id, tick)


## Every grudge between two different houses that is still remembered.
static func live(tick: int = -1) -> Array[Dictionary]:
	return _filtered(func(g: Dictionary) -> bool:
		return holder_of(g) != StringName(g["target"]), tick)


static func _filtered(keep: Callable, tick: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g in GameState.world.grudges:
		if strength_of(g, tick) >= FORGOTTEN and bool(keep.call(g)):
			out.append(g)
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		var sx := strength_of(x, tick)
		var sy := strength_of(y, tick)
		return sx > sy if not is_equal_approx(sx, sy) else int(x["id"]) < int(y["id"]))
	return out


static func kind_label(kind: String) -> String:
	return KIND_LABELS.get(kind, "因縁")


## "612年の家督争いから" — the first cause, which is the one a family tells.
static func why_label(g: Dictionary) -> String:
	return "%d年の%sから" % [int(int(g.get("since", 0)) / SimConfig.TICKS_PER_YEAR),
		kind_label(String(g.get("kind", "")))]


## Where a chain of grudges began: a quarrel at court answered by another one
## still goes back to the disputed succession that started it.
static func root_label(kind: String, since: int) -> String:
	if kind == "" or kind == "ambition":
		return ""
	return "%d年の%s" % [int(since / SimConfig.TICKS_PER_YEAR), kind_label(kind)]


## How badly, in a word.
static func depth_label(strength: float) -> String:
	if strength >= 1.0:
		return "深い遺恨"
	if strength >= 0.55:
		return "遺恨"
	if strength >= 0.25:
		return "わだかまり"
	return "薄れた遺恨"


# ============================================== writing — GameState.apply only

## What has to be read before an event is applied, for working out afterwards
## who it wronged — the order of heirs it is about to replace, for instance.
static func before(e: HistoryEvent) -> Dictionary:
	if e.event_type == HistoryEvent.EventType.OFFICE \
			and String(e.payload.get("action", "")) == "heirs":
		var polity := GameState.get_organization(StringName(e.payload.get("polity", "")))
		if polity != null:
			return {"heirs": polity.heir_houses.duplicate()}
	if e.event_type == HistoryEvent.EventType.SUCCESSION:
		var org := GameState.get_organization(e.subject_org_id)
		if org != null and org.kind == Organization.OrgKind.HOUSE:
			return {"house_head_changed": org.leader_person_id != e.subject_person_id}
	return {}


## Works out what an event leaves resented. Called by GameState.apply after the
## event itself is applied; writes nowhere but the grudges.
static func observe(e: HistoryEvent, pre: Dictionary) -> void:
	match e.event_type:
		HistoryEvent.EventType.SUCCESSION:
			_from_succession(e, pre)
		HistoryEvent.EventType.FOUNDING, HistoryEvent.EventType.SCHISM:
			_from_branching(e)
		HistoryEvent.EventType.OFFICE:
			_from_office(e, pre)
		HistoryEvent.EventType.POWER_TRANSFER:
			_from_transfer(e)
		HistoryEvent.EventType.INCIDENT:
			_from_incident(e)
		HistoryEvent.EventType.DEATH:
			_from_death(e)
		HistoryEvent.EventType.DISSOLVED:
			_forget_house(e.subject_org_id)
		HistoryEvent.EventType.INTRIGUE:
			_from_intrigue(e)


static func _from_succession(e: HistoryEvent, pre: Dictionary) -> void:
	var org := GameState.get_organization(e.subject_org_id)
	if org == null:
		return
	# A new head lets a little of the house's old quarrels go.
	if org.kind == Organization.OrgKind.HOUSE and bool(pre.get("house_head_changed", true)):
		_on_head_change(org.org_id, e.tick)
	if not bool(e.payload.get("contested", false)):
		return
	var loser := GameState.get_person(StringName(e.payload.get("loser_id", "")))
	var winner := GameState.get_person(e.subject_person_id)
	if loser == null or winner == null or loser.house_org_id == &"" \
			or winner.house_org_id == &"":
		return
	var severity := String(e.payload.get("severity", "retirement"))
	var amount := float(FROM_SUCCESSION.get(severity, 0.55))
	# A seat worth more is lost harder: a crown more than a household.
	var kind := "succession"
	if org.kind != Organization.OrgKind.HOUSE:
		kind = "seat"
		amount *= 1.15 if org.kind == Organization.OrgKind.POLITICAL_SYSTEM else 0.8
	if bool(e.payload.get("minority", false)):
		amount += 0.1
	var why := "%sの%sをめぐる争いに敗れた" % [org.formal_name(), org.leadership_title]
	_add(loser.house_org_id, winner.house_org_id, loser.person_id, winner.person_id,
		amount, e, kind, why)


## A cadet line founded by somebody who lost a quarrel inside the family takes
## the quarrel with it: from now on it is one house against another.
static func _from_branching(e: HistoryEvent) -> void:
	_version += 1
	var house := GameState.get_organization(e.subject_org_id)
	if house == null or house.kind != Organization.OrgKind.HOUSE or house.parent_org_id == &"":
		return
	var moved: Array[NotableIndividual] = []
	for raw_id in e.payload.get("moved_person_ids", []):
		var p := GameState.get_person(StringName(raw_id))
		if p != null:
			moved.append(p)
	var leader := GameState.get_person(house.leader_person_id)
	if leader != null:
		moved.append(leader)
	for g in GameState.world.grudges:
		if g["holder"] != g["target"] or g["holder"] != String(house.parent_org_id):
			continue
		# The loser's own line counts: a grandson who leaves to found a house of
		# his own takes his grandfather's quarrel with him.
		for p in moved:
			if _descends_from(p, StringName(g["holder_person"])):
				g["holder"] = String(house.org_id)
				break


static func _from_office(e: HistoryEvent, pre: Dictionary) -> void:
	var action := String(e.payload.get("action", ""))
	if e.payload.has("intrigue"):
		# What a quarrel at court cost somebody is resented as the quarrel, once.
		return
	if action == "heirs" and pre.has("heirs"):
		var old: Array = pre["heirs"]
		var now: Array = e.payload.get("houses", [])
		for i in old.size():
			var lowered := String(old[i])
			var at := now.find(lowered)
			if at >= 0 and at <= i:
				continue
			# Everyone now ahead of it who was not before went past it.
			var limit := at if at >= 0 else now.size()
			for j in limit:
				var ahead := String(now[j])
				var was := old.find(StringName(ahead))
				if was < 0 or was > i:
					_add(StringName(lowered), StringName(ahead), &"", &"", FROM_HEIRS, e,
						"heirs", "跡目の順位を%sに越された" % _house_name(ahead))
	elif action == "vacate" and String(e.payload.get("reason", "")) == "replaced":
		var successor := StringName(e.payload.get("successor_house", ""))
		var displaced := StringName(e.payload.get("house", ""))
		if successor != &"" and displaced != &"" and successor != displaced:
			var polity := GameState.get_organization(StringName(e.payload.get("polity", "")))
			_add(displaced, successor, e.subject_person_id, &"", FROM_DISPLACED, e, "displaced",
				"%sの座を%sに奪われた" % [Offices.label_of(String(e.payload.get("office", "")),
					polity), _house_name(String(successor))])


static func _from_transfer(e: HistoryEvent) -> void:
	if bool(e.payload.get("estate", false)):
		var from := StringName(e.payload.get("from_house_id", ""))
		if from != &"" and from != e.subject_org_id:
			_add(from, e.subject_org_id, &"", e.subject_person_id, FROM_ESTATE, e, "estate",
				"戦の後、所領を%sに与えられた" % _house_name(String(e.subject_org_id)))
		return
	if bool(e.payload.get("honour", false)) and bool(e.payload.get("stripped", false)) \
			and not e.payload.has("intrigue"):
		var crown := GameState.get_organization(StringName(e.payload.get("granted_by", "")))
		var crown_house := StringName(&"")
		if crown != null:
			if crown.kind == Organization.OrgKind.HOUSE:
				crown_house = crown.org_id
			else:
				var head := GameState.get_current_leader(crown.org_id)
				crown_house = head.house_org_id if head != null else &""
		if crown_house != &"":
			_add(e.subject_org_id, crown_house, e.subject_person_id, &"", FROM_STRIPPED, e,
				"stripped", "%sに家格を削られた" % _house_name(String(crown_house)))


static func _from_incident(e: HistoryEvent) -> void:
	if String(e.payload.get("incident_kind", "")) != "excommunication":
		return
	var faith := GameState.get_organization(StringName(e.payload.get("faith_id", "")))
	var head := GameState.get_current_leader(faith.org_id) if faith != null else null
	if head == null or head.house_org_id == &"":
		return
	_add(StringName(e.payload.get("target_house_id", "")), head.house_org_id, &"",
		head.person_id, FROM_EXCOMMUNICATION, e, "excommunication",
		"%sの長に破門された" % faith.display_name)


static func _from_death(e: HistoryEvent) -> void:
	if not bool(e.payload.get("assassinated", false)):
		return
	var victim := GameState.get_person(e.subject_person_id)
	var accused := StringName(e.payload.get("accused_house_id", ""))
	if victim == null or victim.house_org_id == &"" or accused == &"":
		return
	_add(victim.house_org_id, accused, &"", &"", FROM_ASSASSINATION, e, "assassination",
		"%sを殺されたと信じている" % victim.full_name)


static func _from_intrigue(e: HistoryEvent) -> void:
	if String(e.payload.get("action", "")) != "resolve":
		return
	var instigator := StringName(e.payload.get("instigator", ""))
	var target := StringName(e.payload.get("target", ""))
	var inst_person := StringName(e.payload.get("instigator_person", ""))
	var targ_person := StringName(e.payload.get("target_person", ""))
	# A quarrel answered keeps the cause of the first one: the grudges it leaves
	# still go back to whatever started it.
	var rk := String(e.payload.get("motive_root_kind", ""))
	var rs := int(e.payload.get("motive_root_since", -1))
	if rk == "":
		rk = "ambition"
		rs = e.tick
	match String(e.payload.get("outcome", "")):
		"won":
			# Revenge taken; the one brought down will want it back.
			_satisfy(instigator, target, e.tick)
			_add(target, instigator, targ_person, inst_person, FROM_INTRIGUE_LOSS, e,
				"intrigue", "政争で%sに陥れられた" % _house_name(String(instigator)), rk, rs)
		"backfired":
			_add(instigator, target, inst_person, targ_person, FROM_INTRIGUE_LOSS, e,
				"intrigue", "%sを陥れようとして返り討ちにされた" % _house_name(String(target)), rk, rs)
			_add(target, instigator, targ_person, inst_person, FROM_STALEMATE, e,
				"intrigue", "政争で%sに狙われた" % _house_name(String(instigator)), rk, rs)
		"stalemate":
			_add(instigator, target, inst_person, targ_person, FROM_STALEMATE, e,
				"intrigue", "政争で%sを倒しきれなかった" % _house_name(String(target)), rk, rs)
			_add(target, instigator, targ_person, inst_person, FROM_STALEMATE, e,
				"intrigue", "政争で%sに狙われた" % _house_name(String(instigator)), rk, rs)


## Writes or deepens one grudge.
static func _add(holder: StringName, target: StringName, holder_person: StringName,
		target_person: StringName, amount: float, e: HistoryEvent, kind: String,
		why: String, root_kind := "", root_since := -1) -> void:
	_version += 1
	if holder == &"" or target == &"" or amount <= 0.0:
		return
	if holder == target and holder_person == &"":
		return
	var w := GameState.world
	for g in w.grudges:
		if g["holder"] != String(holder) or g["target"] != String(target):
			continue
		if holder == target and g["holder_person"] != String(holder_person):
			continue
		g["strength"] = minf(CEILING, strength_of(g, e.tick) + amount)
		g["updated"] = e.tick
		var causes: Array = g["causes"]
		causes.append(String(e.event_id))
		if causes.size() > KEPT_CAUSES:
			causes.remove_at(1)
		if target_person != &"":
			g["target_person"] = String(target_person)
		return
	w.grudges.append({
		"id": w.next_grudge_id,
		"holder": String(holder),
		"target": String(target),
		"holder_person": String(holder_person),
		"target_person": String(target_person),
		"strength": minf(CEILING, amount),
		"updated": e.tick,
		"since": e.tick,
		"cause": String(e.event_id),
		"kind": kind,
		"why": why,
		"causes": [String(e.event_id)],
		"generations": 0,
		"root_kind": root_kind if root_kind != "" else kind,
		"root_since": root_since if root_since >= 0 else e.tick,
	})
	w.next_grudge_id += 1
	_prune(e.tick)


static func _satisfy(holder: StringName, target: StringName, tick: int) -> void:
	_version += 1
	for g in GameState.world.grudges:
		if g["target"] == String(target) and holder_of(g) == holder:
			g["strength"] = strength_of(g, tick) * SATISFIED
			g["updated"] = tick


static func _on_head_change(house_id: StringName, tick: int) -> void:
	_version += 1
	for g in GameState.world.grudges:
		if g["holder"] == String(house_id) and g["holder"] != g["target"]:
			g["strength"] = strength_of(g, tick) * HEAD_CHANGE
			g["updated"] = tick
			g["generations"] = int(g["generations"]) + 1


## A house that is gone holds nothing and is held to nothing.
static func _forget_house(house_id: StringName) -> void:
	_version += 1
	var kept: Array = []
	for g in GameState.world.grudges:
		if g["holder"] != String(house_id) and g["target"] != String(house_id):
			kept.append(g)
	GameState.world.grudges = kept


static func _prune(tick: int) -> void:
	_version += 1
	var kept: Array = []
	for g in GameState.world.grudges:
		if strength_of(g, tick) >= FORGOTTEN * 0.5:
			kept.append(g)
	GameState.world.grudges = kept


static func _descends_from(person: NotableIndividual, ancestor_id: StringName) -> bool:
	if ancestor_id == &"":
		return false
	var line: Array[NotableIndividual] = [person]
	for generation in 4:
		var next: Array[NotableIndividual] = []
		for p in line:
			if p.person_id == ancestor_id:
				return true
			for parent_id in [p.father_id, p.mother_id]:
				var parent := GameState.get_person(parent_id)
				if parent != null:
					next.append(parent)
		line = next
	for p in line:
		if p.person_id == ancestor_id:
			return true
	return false


static func _house_name(house_id: String) -> String:
	var house := GameState.get_organization(StringName(house_id))
	return house.formal_name() if house != null else "他家"

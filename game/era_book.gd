class_name EraBook
extends RefCounted

## The chronicle read as a history book: fifty-year chapters, each with a name.
##
## A thousand years of births and deaths is a record, not a story. What makes it
## a story is the shape a reader can hold: "the age of plague", "the great
## upheaval", "a quiet half-century" — and under each, the few things that age
## will be remembered for. Every name and line here is read off the event log,
## so a chapter says only what actually happened, and the same history always
## gives the same book.

const CHAPTER_YEARS := 50
const CHAPTER_TICKS := CHAPTER_YEARS * SimConfig.TICKS_PER_YEAR
const MAX_LINES := 5
const MAX_MOMENTS := 6

const TITLES := {
	"dawn": ["建国の時代", "始まりの半世紀"],
	"fall": ["興亡の時代", "国が改まる時代", "王冠の落ちる半世紀"],
	"turmoil": ["大乱の時代", "動乱の半世紀", "剣と叛旗の時代"],
	"division": ["分かれゆく時代", "枝分かれの半世紀", "家々の分かれる時代", "新しき家々の時代"],
	"faith": ["信仰の時代", "神々の目覚め", "祈りの分かれ目"],
	"plague": ["疫病の時代", "黒い死の半世紀"],
	"drought": ["飢えの時代", "渇きの半世紀"],
	"monster_incursion": ["魔物の時代", "牙の半世紀"],
	"wildfire": ["炎の時代", "焼け野の半世紀"],
	"bounty": ["実りの時代", "黄金の半世紀", "恵みの時代"],
	"decline": ["黄昏の時代", "絶えゆく家々の時代", "血の細る半世紀"],
	"peace": ["泰平の世", "静かな半世紀", "凪の時代", "穏やかな半世紀"],
}

static var _cache: Dictionary = {}
static var _cache_seed := -1


static func current_index() -> int:
	return int(SimClock.current_tick / CHAPTER_TICKS)


## Every chapter so far, the one still being written first.
static func chapters() -> Array[Dictionary]:
	var last := current_index()
	var wanted: Array[int] = []
	for i in range(last, -1, -1):
		wanted.append(i)
	return _build(wanted)


static func chapter(index: int) -> Dictionary:
	var built := _build([index])
	return built[0] if not built.is_empty() else {}


static func _build(indices: Array[int]) -> Array[Dictionary]:
	var world_seed: int = GameState.world.seed if GameState.world != null else 0
	if world_seed != _cache_seed:
		_cache.clear()
		_cache_seed = world_seed
	var current := current_index()
	var needed := {}
	for i in indices:
		if i == current or not _cache.has(i):
			needed[i] = _empty_tally(i)

	# One pass over the record. The ruler is followed from the beginning, because
	# who reigned at the end of a chapter may have taken the throne long before.
	var ruler := ""
	var ruler_at_end := {}
	for e in HistoryLog.buffer:
		var index := int(e.tick / CHAPTER_TICKS)
		if e.event_type == HistoryEvent.EventType.SUCCESSION and _is_polity(e.subject_org_id):
			var person := GameState.get_person(e.subject_person_id)
			if person != null:
				ruler = person.full_name
				if needed.has(index):
					needed[index]["rulers"].append(ruler)
		ruler_at_end[index] = ruler
		if needed.has(index):
			_tally(needed[index], e)

	var last_ruler := ""
	for i in range(0, current + 1):
		if ruler_at_end.has(i):
			last_ruler = ruler_at_end[i]
		if needed.has(i):
			needed[i]["ruler"] = last_ruler

	var written := {}
	for i in needed:
		var chapter := _write(needed[i], world_seed)
		if i == current:
			chapter["complete"] = false
		else:
			_cache[i] = chapter
		written[i] = chapter
	var out: Array[Dictionary] = []
	for i in indices:
		if written.has(i):
			out.append(written[i])
		elif _cache.has(i):
			out.append(_cache[i])
	return out


static func _empty_tally(index: int) -> Dictionary:
	return {
		"index": index,
		"rulers": [],
		"ruler": "",
		"incidents": [],
		"regimes": 0,
		"refoundings": [],
		"house_branches": [],
		"other_branches": [],
		"faiths": [],
		"extinctions": [],
		"calamities": {},
		"blessings": {},
		"births": 0,
		"deaths": 0,
		"moments": [],
	}


static func _tally(t: Dictionary, e: HistoryEvent) -> void:
	var moment := false
	match e.event_type:
		HistoryEvent.EventType.BIRTH:
			t["births"] += 1
		HistoryEvent.EventType.DEATH:
			t["deaths"] += 1
		HistoryEvent.EventType.INCIDENT:
			t["incidents"].append([Incidents.label_of(StringName(e.payload.get("incident_kind", ""))),
				int(e.tick / SimConfig.TICKS_PER_YEAR)])
			moment = true
		HistoryEvent.EventType.POWER_TRANSFER:
			if bool(e.payload.get("regime_change", false)):
				t["regimes"] += 1
				moment = true
		HistoryEvent.EventType.SCHISM:
			var born: Dictionary = e.payload.get("organization", {})
			var name := String(born.get("display_name", ""))
			match String(e.payload.get("schism_kind", "")):
				"refounding":
					t["refoundings"].append(name)
					moment = true
				"revelation":
					t["faiths"].append(name)
					moment = true
				_:
					var org := GameState.get_organization(e.subject_org_id)
					if org != null and org.is_noble():
						t["house_branches"].append(org.display_name)
						moment = true
					elif org != null and org.kind != Organization.OrgKind.HOUSE:
						t["other_branches"].append(org.display_name)
		HistoryEvent.EventType.DISSOLVED:
			var org := GameState.get_organization(e.subject_org_id)
			if org != null and org.is_noble():
				t["extinctions"].append(org.display_name)
				moment = true
		HistoryEvent.EventType.DISASTER_OCCURRED:
			var id := String(e.payload.get("definition_id", ""))
			var def := ContentRegistry.get_disaster(StringName(id))
			if def != null:
				var bucket: Dictionary = t["blessings"] if def.is_benevolent else t["calamities"]
				bucket[id] = int(bucket.get(id, 0)) + 1
	if moment and t["moments"].size() < MAX_MOMENTS:
		t["moments"].append(e)


static func _is_polity(org_id: StringName) -> bool:
	var org := GameState.get_organization(org_id)
	return org != null and org.kind == Organization.OrgKind.POLITICAL_SYSTEM


# ------------------------------------------------------------------ writing

static func _write(t: Dictionary, world_seed: int) -> Dictionary:
	var index: int = t["index"]
	var theme := _theme(t)
	var names: Array = TITLES[theme]
	# Stepping through the names chapter by chapter, so two quiet ages in a row
	# are not both called the same thing.
	var title: String = names[(absi(hash([world_seed, theme])) + index) % names.size()]
	return {
		"index": index,
		"number": index + 1,
		"start_year": index * CHAPTER_YEARS,
		"end_year": (index + 1) * CHAPTER_YEARS,
		"title": title,
		"theme": theme,
		"lines": _lines(t),
		"moments": t["moments"],
		"births": t["births"],
		"deaths": t["deaths"],
		"complete": true,
	}


## What the age was most about. Ruptures outweigh splits, splits outweigh
## weather, and an age with none of it is a peaceful one.
static func _theme(t: Dictionary) -> String:
	var harsh := 0
	var worst := ""
	var worst_count := 0
	for id in t["calamities"]:
		harsh += int(t["calamities"][id])
		if int(t["calamities"][id]) > worst_count:
			worst_count = int(t["calamities"][id])
			worst = id
	var bounty := 0
	for id in t["blessings"]:
		bounty += int(t["blessings"][id])

	var scores := {
		"fall": t["refoundings"].size() * 6,
		"turmoil": t["incidents"].size() * 3 + int(t["regimes"]) * 3,
		"division": t["house_branches"].size() + t["other_branches"].size(),
		"faith": t["faiths"].size() * 3,
		"calamity": harsh * 2,
		"bounty": bounty * 2,
		"decline": int(t["extinctions"].size() * 1.5),
	}
	# Ties go to whichever comes first here: a split that matched the deaths
	# is the more interesting half of the story.
	var best := "peace"
	var best_score := 1
	for key in ["fall", "turmoil", "faith", "calamity", "division", "decline", "bounty"]:
		if int(scores[key]) > best_score:
			best = key
			best_score = int(scores[key])
	if best == "calamity":
		return worst if TITLES.has(worst) else "drought"
	if int(t["index"]) == 0 and (best == "peace" or best == "division"):
		return "dawn"
	return best


static func _lines(t: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var rulers: Array = t["rulers"]
	if rulers.size() >= 2:
		lines.append("国の長は%d度替わり、%sの代でこの章は閉じる" % [rulers.size(), rulers.back()])
	elif rulers.size() == 1:
		lines.append("%sが国の長に立った" % rulers[0])
	elif not String(t["ruler"]).is_empty():
		lines.append("%sの治世が続いた" % t["ruler"])

	if not t["refoundings"].is_empty():
		lines.append("国が倒れ、%sが興った" % "、".join(t["refoundings"]))
	elif int(t["regimes"]) > 0:
		lines.append("統治のかたちが%d度覆った" % t["regimes"])

	if not t["incidents"].is_empty():
		var parts: Array[String] = []
		for entry in t["incidents"]:
			parts.append("%s（%d年）" % [entry[0], entry[1]])
		lines.append("%sが起きた" % "・".join(parts))

	if not t["faiths"].is_empty():
		lines.append("新たな信仰、%sが生まれた" % "・".join(t["faiths"]))
	if not t["house_branches"].is_empty():
		lines.append("%sが分かれ出た" % _some(t["house_branches"], "家"))
	if not t["extinctions"].is_empty():
		lines.append("%sが絶えた" % _some(t["extinctions"], "家"))

	var harsh := _disaster_names(t["calamities"])
	if not harsh.is_empty():
		lines.append("%sが世を襲った" % "・".join(harsh))
	var kind := _disaster_names(t["blessings"])
	if not kind.is_empty():
		lines.append("%sに恵まれた" % "・".join(kind))

	if lines.size() <= 1 and t["incidents"].is_empty() and t["house_branches"].is_empty():
		lines.append("大きな出来事のない、穏やかな時が流れた")
	return lines.slice(0, MAX_LINES)


static func _some(names: Array, unit: String) -> String:
	if names.size() <= 3:
		return "・".join(names)
	return "%s ほか%d%s" % ["・".join(names.slice(0, 3)), names.size() - 3, unit]


static func _disaster_names(counts: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id in counts:
		var def := ContentRegistry.get_disaster(StringName(id))
		if def != null:
			out.append(def.display_name)
	return out

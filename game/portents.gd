class_name Portents
extends RefCounted

## 兆し — what is brewing, read off the world as it stands.
##
## The chronicle says what happened and the map says what is. Neither says what
## is about to be, and that is the part a watcher leans forward for: an old
## ruler with the succession unsettled, a family down to its last member, a
## faction one bad harvest from the capital, a prophecy with ten years left.
## This gathers those into one short list, most pressing first, so that at any
## moment the game can answer "what should I be watching?" in a line.
##
## Nothing here predicts anything. Every line is a reading of the present —
## an age, a headcount, a pressure the simulation already computes — and it
## writes nothing.

const MAX_ITEMS := 8
const OLD_AGE := 68
const UNREST_ALARM := 0.6
const PRESSURE_FLOOR := 0.45
const THREAT_ALARM := 0.7


## The list, most pressing first. Each item says what it is (`label`, `title`,
## `sub`), how it looks (`glyph`, `colour`), how pressing it is (`weight`, 0..1)
## and where a reader should go to see it (`tab`, and `subject` when it is about
## a particular person or family).
static func current(tick: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if GameState.world == null:
		return out
	_prophecies(out, tick)
	_war(out, tick)
	_ruptures(out)
	_challenge(out)
	_old_ruler(out, tick)
	_offices(out, tick)
	_quarrels(out, tick)
	_doctrines(out, tick)
	_thin_blood(out)
	_restless_land(out)
	_divided_faith(out)
	_monsters(out)
	_nearing_greatness(out, tick)
	out.sort_custom(func(a, b): return float(a["weight"]) > float(b["weight"]))
	if out.size() > MAX_ITEMS:
		out.resize(MAX_ITEMS)
	if out.is_empty():
		out.append(_item("凪", "世は静かだ", "何かを起こすなら、神の出番。理を動かすか、未来を告げよう",
			&"sun", Palette.TEXT_MUTED, 0.0, "god"))
	return out


static func _item(label: String, title: String, sub: String, glyph: StringName,
		colour: Color, weight: float, tab: String, subject: StringName = &"") -> Dictionary:
	return {"label": label, "title": title, "sub": sub, "glyph": glyph, "colour": colour,
		"weight": clampf(weight, 0.0, 1.0), "tab": tab, "subject": subject}


# ------------------------------------------------------------- the god's own

static func _prophecies(out: Array[Dictionary], tick: int) -> void:
	if Oracle.prophecies.is_empty():
		# The loop the whole game hangs on, offered until it has been taken up.
		var first := Oracle.record.is_empty()
		out.append(_item("神託", "まだ未来を告げていない",
			"神託をひとつ下そう。告げた未来へ、理と災厄で世を導く",
			&"sparkle", Palette.ACCENT, 0.97 if first else 0.5, "god"))
		return
	for p in Oracle.prophecies:
		var left := ProphecyBook.years_left(p, tick)
		var near := ProphecyBook.closeness(p, tick)
		var where := ProphecyBook.progress(p, tick)
		var sub := "あと%d年" % left
		if not where.is_empty():
			sub = "%s　・　あと%d年" % [where, left]
		# More pressing as the deadline nears or the outcome does.
		var urgency := 1.0 - clampf(float(left) / maxf(1.0, float(p["years"])), 0.0, 1.0)
		var weight := 0.62 + 0.2 * urgency + 0.15 * maxf(0.0, near)
		out.append(_item("神託", ProphecyBook.headline(p), sub, &"sparkle", Palette.ACCENT,
			weight, "god", StringName(p["target"])))


# ------------------------------------------------------------ what is building

## A war under way is the most pressing thing in the world, after the god's own
## words: which side is winning, and how worn out they both are.
static func _war(out: Array[Dictionary], tick: int) -> void:
	for war in CivilWar.wars():
		var a := GameState.get_organization(war.side_a)
		var b := GameState.get_organization(war.side_b)
		if a == null or b == null:
			continue
		var leading := a if war.front > 0.0 else b
		var state := "互角" if absf(war.front) < 0.2 else ("%s優勢" % leading.short_name())
		out.append(_item("戦", "%s 対 %s　%d年目" % [a.short_name(), b.short_name(),
				war.years(tick) + 1],
			"戦況：%s　・　疲弊 %d%% ／ %d%%" % [state,
				int(minf(war.exhaustion_a, 1.0) * 100.0), int(minf(war.exhaustion_b, 1.0) * 100.0)],
			&"swords", Palette.DANGER, 0.95, "incidents"))


static func _ruptures(out: Array[Dictionary]) -> void:
	for entry in Incidents.pressures():
		var pressure := float(entry["pressure"])
		if pressure < PRESSURE_FLOOR:
			continue
		var missing := String(entry.get("missing", ""))
		out.append(_item("兆し", "%sの機運が高まっている（%d%%）" % [entry["label"], int(pressure * 100.0)],
			"まだ足りないもの：%s" % missing if not missing.is_empty() else "条件は揃いつつある",
			&"flame", Palette.DANGER, 0.3 + 0.6 * pressure, "incidents"))


static func _challenge(out: Array[Dictionary]) -> void:
	var realm := HouseRank.dominant_realm()
	if realm == null:
		return
	var challenge := RegimeShift.standing_challenge(realm)
	if challenge.is_empty():
		return
	var hold := float(challenge.get("hold", 0.0))
	var challenger: Organization = challenge["org"]
	out.append(_item("兆し", "%sが体制に迫っている" % challenger.formal_name(),
		"掌握 %d%%　・　いまの体制の正統性 %d%%" % [int(hold * 100.0), int(realm.legitimacy * 100.0)],
		&"banner", Palette.POLITY, 0.35 + 0.5 * hold, "power", challenger.org_id))
	# And whether, if it fell, it would fall whole — or half the country would
	# stand by it and fight.
	if CivilWar.is_at_war(realm.org_id):
		return
	var outlook := CivilWar.split_outlook(realm)
	if outlook.is_empty():
		return
	var share := float(outlook.get("share", 0.0))
	var needed := float(outlook.get("needed", 1.0))
	if share >= needed * 0.8 and (outlook["loyal"] as Array).size() >= CivilWar.MIN_SIDE_REGIONS \
			and (outlook["rebel"] as Array).size() >= CivilWar.MIN_SIDE_REGIONS:
		out.append(_item("兆し", "国が割れかねない",
			"体制が倒れれば、%d地方が旧体制に付く（民の%d%%）。割れれば内戦になる" % [
				(outlook["loyal"] as Array).size(), int(share * 100.0)],
			&"split", Palette.DANGER, 0.4 + 0.4 * hold, "incidents"))


## The seats beside the throne: a regency about to end as its king comes of
## age, and an heir house that is on the worst of terms with the crown it is
## named to inherit.
static func _offices(out: Array[Dictionary], tick: int) -> void:
	var realm := HouseRank.dominant_realm()
	if realm == null:
		return
	var ruler := GameState.get_current_leader(realm.org_id)
	if realm.offices.has("regent") and ruler != null and not Offices.is_regency_by_right(realm):
		var left := SimConfig.ADULT_AGE_YEARS - ruler.age_years(tick)
		if left > 0 and left <= 3:
			var regent := GameState.get_person(StringName(realm.offices["regent"].get("person", "")))
			out.append(_item("兆し", "摂政位が空く",
				"%sはあと%d年で成年。%sの摂政も終わる" % [ruler.full_name, left,
					regent.full_name if regent != null else "いまの"],
				&"crown", Palette.POLITY, 0.42, "power"))
	if not realm.heir_houses.is_empty() and ruler != null:
		var first := GameState.get_organization(realm.heir_houses[0])
		if first != null and HouseRelations.relation(first.org_id, ruler.house_org_id) <= -0.35:
			out.append(_item("兆し", "跡目の順位に異論",
				"跡目家の第一位%sは王家と険悪だ" % first.formal_name(),
				&"crown", Palette.HOUSE, 0.36, "power", first.org_id))


## 政争 under way, and the deepest grudge that has not been answered yet.
static func _quarrels(out: Array[Dictionary], tick: int) -> void:
	for state in Intrigue.active():
		var a := GameState.get_organization(StringName(state["instigator"]))
		var b := GameState.get_organization(StringName(state["target"]))
		if a == null or b == null:
			continue
		var near := int(state["resolve_tick"]) - tick <= 2 and int(state["stage"]) >= 2
		out.append(_item("政争", "%sが%sを狙う" % [a.short_name(), b.short_name()],
			"%sをめぐる政争が進行中（%s）%s" % [Intrigue.prize_label(state),
				Intrigue.motive_phrase(state), "。決着は近い" if near else ""],
			&"dagger", Palette.HOUSE, 0.5 if near else 0.4, "incidents", a.org_id))
	var deepest := {}
	var most := 0.75
	for g in Grudges.live(tick):
		var s := Grudges.strength_of(g, tick)
		var holder := GameState.get_organization(Grudges.holder_of(g))
		if s < most or holder == null or not Intrigue.involving(holder.org_id).is_empty():
			continue
		most = s
		deepest = g
	if not deepest.is_empty():
		var holder := GameState.get_organization(Grudges.holder_of(deepest))
		var target := GameState.get_organization(StringName(deepest["target"]))
		if holder != null and target != null:
			out.append(_item("兆し", "%sは%sに遺恨を抱く" % [holder.short_name(), target.short_name()],
				"%s。%s" % [Grudges.why_label(deepest), String(deepest.get("why", ""))],
				&"dagger", Palette.HOUSE, 0.3 + 0.1 * minf(most, 1.5), "relations", holder.org_id))


## 思想: a doctrine close to becoming a country's creed, and one about to die.
static func _doctrines(out: Array[Dictionary], tick: int) -> void:
	var realm := HouseRank.dominant_realm()
	if realm == null or not is_instance_valid(realm.ideology):
		return
	if realm.doctrine_id == &"":
		var best: Doctrine = null
		var most := Doctrines.ADOPT_CLOSENESS - 0.1
		for d in Doctrines.living():
			var c := Doctrines.closeness(d, realm.ideology) + 0.25 * d.prestige
			if c > most:
				most = c
				best = d
		if best != null:
			out.append(_item("思想", "%sが国是に近づく" % best.name,
				"%sの向きは%sの説く姿に近い。新しい体制か、綱領に掲げる派閥が議場を握れば" % [
					realm.formal_name(), best.name],
				&"scroll", Palette.RELIGION, 0.32, "lineage"))
	for d in Doctrines.living():
		if d.adopted_by().is_empty() and d.prestige < Doctrines.FADE_PRESTIGE + 0.05 \
				and float(tick - d.born_tick) / SimConfig.TICKS_PER_YEAR >= Doctrines.FADE_MIN_YEARS:
			out.append(_item("思想", "%sが廃れかけている" % d.name,
				"掲げる国も派閥もなく、声望は地に落ちた", &"scroll", Palette.TEXT_MUTED, 0.22, "lineage"))
			break


static func _old_ruler(out: Array[Dictionary], tick: int) -> void:
	var realm := HouseRank.dominant_realm()
	if realm == null:
		return
	var ruler := GameState.get_current_leader(realm.org_id)
	if ruler == null or not ruler.is_alive():
		out.append(_item("兆し", "国の長の座が空いている", "誰が継ぐかは、人の側が決める",
			&"crown", Palette.POLITY, 0.6, "power"))
		return
	var age := ruler.age_years(tick)
	if age < OLD_AGE:
		return
	var seat := realm.leadership_title if not realm.leadership_title.is_empty() else "国の長"
	out.append(_item("兆し", "%s %sは%d歳" % [seat, ruler.full_name, age],
		"代替わりが近い。次に誰が立つかで、世の向きが変わる",
		&"crown", Palette.POLITY, 0.38 + 0.02 * float(age - OLD_AGE), "lineage", ruler.person_id))


static func _thin_blood(out: Array[Dictionary]) -> void:
	var frail: Array[Organization] = []
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.is_noble() and house.member_count <= 2:
			frail.append(house)
	frail.sort_custom(func(a, b):
		if a.member_count != b.member_count:
			return a.member_count < b.member_count
		return a.power_score > b.power_score)
	for house in frail.slice(0, 2):
		out.append(_item("兆し", "%sの血を継ぐ者は、あと%d人" % [house.formal_name(), house.member_count],
			"子が生まれなければ、この家は絶える",
			&"candle", Palette.HOUSE, 0.5 if house.member_count <= 1 else 0.34, "lineage",
			house.org_id))


static func _restless_land(out: Array[Dictionary]) -> void:
	var worst: SettlementState = null
	var starving := 0
	for id in GameState.world.settlements:
		var s: SettlementState = GameState.world.settlements[id]
		if s.starving:
			starving += 1
		if worst == null or s.unrest > worst.unrest:
			worst = s
	if worst != null and worst.unrest >= UNREST_ALARM:
		out.append(_item("兆し", "%sが荒れている（不満 %d%%）" % [worst.display_name, int(worst.unrest * 100.0)],
			"飢えが火に油を注いでいる" if worst.starving else "火種は燻りつづけている",
			&"unrest", Palette.DANGER, 0.2 + 0.5 * worst.unrest, "map"))
	if starving >= 2:
		out.append(_item("兆し", "%dの地方が飢えている" % starving,
			"収穫を上げれば鎮まり、放っておけば不満に変わる",
			&"drought", Palette.DANGER, 0.3 + 0.06 * float(starving), "map"))


static func _divided_faith(out: Array[Dictionary]) -> void:
	var held := {}
	for id in GameState.world.settlements:
		held[GameState.world.settlements[id].religion_id] = true
	if held.size() < 2 or Religion.division() < 0.3:
		return
	out.append(_item("兆し", "信仰が割れている",
		"%dの教えが地を分け合う。祈りの違いは、家と家の仲も裂く" % held.size(),
		&"altar", Palette.RELIGION, 0.2 + 0.3 * Religion.division(), "map"))


static func _monsters(out: Array[Dictionary]) -> void:
	var threat := GameState.world.global_monster_threat_level
	if threat < THREAT_ALARM:
		return
	out.append(_item("兆し", "魔物が跋扈している",
		"武を頼む者が力を増す。討伐の者たちが国を動かしはじめる",
		&"claw", Palette.DANGER, 0.25 + 0.3 * threat, "power"))


## Somebody history is about to weigh: a founder whose state nears its hundred
## and fiftieth year, a head whose family has held the rank they raised it to
## for nearly fifty. Read from what Greatness will look at, decided by nothing.
const GREATNESS_HORIZON_YEARS := 20


static func _nearing_greatness(out: Array[Dictionary], tick: int) -> void:
	for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		var age := int((tick - polity.founding_tick) / SimConfig.TICKS_PER_YEAR)
		var left := Greatness.FOUNDER_YEARS - age
		if left <= 0 or left > GREATNESS_HORIZON_YEARS \
				or (polity.reign_marks.get("judged", []) as Array).has("founder"):
			continue
		if Greatness._taken_by_somebody(polity):
			continue
		var first := Greatness._first_holding(polity.org_id)
		if first.is_empty() or int(first["years"]) < Greatness.FOUNDER_REIGN_YEARS:
			continue
		var founder: NotableIndividual = first["person"]
		out.append(_item("偉人", "あと%d年で、%sが歴史に刻まれる" % [left, founder.full_name],
			"%sが百二十年を保てば、その国を開いた者は「建国の父」と呼ばれる" % polity.formal_name(),
			&"laurel", Palette.ACCENT, 0.3 + 0.02 * float(GREATNESS_HORIZON_YEARS - left),
			"lineage", founder.person_id))
	for entry in GameState.world.great_pending:
		var left := int((int(entry.get("due", 0)) - tick) / SimConfig.TICKS_PER_YEAR)
		if left > GREATNESS_HORIZON_YEARS:
			continue
		var who := GameState.get_person(StringName(entry.get("person_id", "")))
		var house := GameState.get_organization(StringName(entry.get("house_id", "")))
		if who == null or house == null or not house.is_active():
			continue
		out.append(_item("偉人", "あと%d年で、%sが歴史に刻まれる" % [maxi(1, left), who.full_name],
			"%sがそれまで公爵の座を保てば、家を引き上げた当主は「家門の祖」となる" % house.formal_name(),
			&"laurel", Palette.ACCENT, 0.3, "lineage", who.person_id))

class_name Doctrines
extends RefCounted

## 思想の系譜 — how doctrines are born, written over, taken up by states, turned
## against, forgotten and dug up again.
##
## There are none when the world begins. The first comes from a country loose
## enough to argue in — a chamber rather than a throne, a basis other than blood
## or the sword, towns rich enough to keep people who write — or from a reign so
## long and so good that somebody sets down how it was done. From then on every
## new doctrine comes out of an existing one: carried on and revised (発展),
## split over (分派), written against (反動), two made into one (総合), or one
## that had died brought back by a later hand (復興).
##
## States take them up as their creed — a new regime reaching for the doctrine
## nearest what it means to be, a chamber held by a faction that marches under
## one, a ruler who was a pupil — and a creed pulls the country's ideals toward
## the picture it paints, props up the regime if the great families share that
## picture and undermines it if they do not. A creed that brings prosperity is
## admired abroad; one whose country falls is discredited, and its enemies'
## reaction follows. A doctrine a closed regime cannot stomach is driven out:
## its thinkers exiled or jailed, the doctrine underground or abroad.
##
## The god cannot write a doctrine or burn one. The god moves harvests, ore and
## monsters, and the prosperity and the anger those make are what thinkers write
## from.

const STEP_SEASON := 1

## Freedom below which nothing is born from argument, and the rate above it.
const FREE_FLOOR := 0.35
const BIRTH_CHANCE := 0.015
## A reign that history called great, and one that was only long and quiet.
const GREAT_REIGN_CHANCE := 0.35
const LONG_REIGN_CHANCE := 0.15
const LONG_REIGN_YEARS := 22
## Doctrines that can be alive at once before a new one needs real room.
const CROWDED := 6
## Years between revisions of a living doctrine, on average.
const REVISION_YEARS := 45.0
## How far revisions may carry a doctrine from where it began before the next
## one splits off instead.
const SPLIT_DRIFT := 0.12
## How close a state's ideals must be to a doctrine for it to take it up, and
## how far they may fall before it lets it go.
const ADOPT_CLOSENESS := 0.55
const ABANDON_CLOSENESS := 0.3
## How fast a creed pulls a country's ideals toward its picture, per year.
const CREED_PULL := 0.012
const CREED_LEGITIMACY := 0.012
## Admiration lost per year by a doctrine nobody holds.
const NEGLECT := 0.003
const FADE_PRESTIGE := 0.08
const FADE_MIN_YEARS := 80
## Years a faded doctrine stays dead before it can be revived.
const REVIVAL_YEARS := 60

const DERIVATION_LABELS := {
	"root": "源流",
	"development": "発展",
	"schism": "分派",
	"reaction": "反動",
	"synthesis": "総合",
	"revival": "復興",
	"governance": "治世から",
}
const STATE_LABELS := {"rising": "興隆", "underground": "地下", "faded": "廃れ"}
const BASIS_LABELS := {
	PoliticalSystemAxes.LegitimacyBasis.HEREDITARY: "血統",
	PoliticalSystemAxes.LegitimacyBasis.ELECTED: "民意",
	PoliticalSystemAxes.LegitimacyBasis.MERITOCRATIC: "功績と技能",
	PoliticalSystemAxes.LegitimacyBasis.THEOCRATIC: "信仰",
	PoliticalSystemAxes.LegitimacyBasis.MILITARY_STRENGTH: "武",
	PoliticalSystemAxes.LegitimacyBasis.WEALTH_BASED: "富",
}
const STRUCTURE_LABELS := {
	PoliticalSystemAxes.DecisionStructure.AUTOCRATIC: "一人が決める",
	PoliticalSystemAxes.DecisionStructure.OLIGARCHIC_COUNCIL: "有力者の合議",
	PoliticalSystemAxes.DecisionStructure.ASSEMBLY: "議会が決める",
}
const AXIS_WORDS := {
	&"centralization": ["分権", "集権"],
	&"tradition_reform": ["伝統", "改革"],
	&"militarism_pacifism": ["和平", "尚武"],
	&"isolationism_commerce": ["自給", "通商"],
	&"secular_theocratic": ["世俗", "神権"],
}
## Names a doctrine can take from what it argues.
const BASIS_NAMES := {
	PoliticalSystemAxes.LegitimacyBasis.HEREDITARY: ["正統主義", "王権論", "家門主義"],
	PoliticalSystemAxes.LegitimacyBasis.ELECTED: ["共和主義", "民権論", "議会主義"],
	PoliticalSystemAxes.LegitimacyBasis.MERITOCRATIC: ["能力主義", "賢人政治論", "功績主義"],
	PoliticalSystemAxes.LegitimacyBasis.THEOCRATIC: ["神政主義", "教権論", "聖統主義"],
	PoliticalSystemAxes.LegitimacyBasis.MILITARY_STRENGTH: ["尚武主義", "軍政論", "武断主義"],
	PoliticalSystemAxes.LegitimacyBasis.WEALTH_BASED: ["産業主義", "重商主義", "富国論"],
}
const AXIS_NAMES := {
	"centralization+": ["集権主義", "中央集権論"],
	"centralization-": ["自治主義", "分権論"],
	"tradition_reform-": ["復古主義", "守旧論"],
	"tradition_reform+": ["進歩主義", "改革論"],
	"militarism_pacifism+": ["軍国論", "強兵主義"],
	"militarism_pacifism-": ["平和主義", "非戦論"],
	"isolationism_commerce+": ["通商主義", "自由交易論"],
	"isolationism_commerce-": ["自給主義", "鎖国論"],
	"secular_theocratic+": ["祭政一致論", "敬神主義"],
	"secular_theocratic-": ["世俗主義", "政教分離論"],
}
## Titles for a revision of a doctrine already written.
const WORK_FORMS := ["『続%s論』", "『%s新論』", "『%s問答』", "『%s通義』", "『%s精義』"]


# ===================================================================== reading

static func all() -> Array[Doctrine]:
	var out: Array[Doctrine] = []
	for id in GameState.doctrines:
		out.append(GameState.doctrines[id])
	out.sort_custom(func(a: Doctrine, b: Doctrine) -> bool:
		return a.born_tick < b.born_tick if a.born_tick != b.born_tick \
			else String(a.doctrine_id) < String(b.doctrine_id))
	return out


static func living() -> Array[Doctrine]:
	var out: Array[Doctrine] = []
	for d in all():
		if d.is_alive():
			out.append(d)
	return out


static func get_doctrine(id: StringName) -> Doctrine:
	return GameState.doctrines.get(id)


static func creed_of(polity: Organization) -> Doctrine:
	if polity == null or polity.doctrine_id == &"":
		return null
	return get_doctrine(polity.doctrine_id)


static func derivation_label(kind: String) -> String:
	return DERIVATION_LABELS.get(kind, kind)


static func state_label(state: String) -> String:
	return STATE_LABELS.get(state, state)


## How far a doctrine's picture of the state is from a set of real ideals: 0 is
## the same, 1 as far apart as the axes go. Basis and structure count as well.
static func distance(d: Doctrine, axes: PoliticalSystemAxes) -> float:
	if axes == null:
		return 1.0
	var total := 0.0
	for a in PoliticalSystemAxes.AXIS_NAMES:
		total += absf(float(d.claims.get(String(a), 0.0)) - axes.get_axis(a))
	var dist := total / float(PoliticalSystemAxes.AXIS_NAMES.size()) / 2.0
	if d.basis != axes.legitimacy_basis:
		dist += 0.06
	if d.structure != axes.decision_structure:
		dist += 0.03
	return dist


## The same as a closeness, 0..1, read the way a country's people would: a
## doctrine within a few points of what they already believe is theirs.
static func closeness(d: Doctrine, axes: PoliticalSystemAxes) -> float:
	return clampf(1.0 - distance(d, axes) / 0.3, 0.0, 1.0)


static func claims_distance(a: Dictionary, b: Dictionary) -> float:
	var total := 0.0
	for axis in PoliticalSystemAxes.AXIS_NAMES:
		total += absf(float(a.get(String(axis), 0.0)) - float(b.get(String(axis), 0.0)))
	return total / float(PoliticalSystemAxes.AXIS_NAMES.size()) / 2.0


static func doctrine_distance(a: Doctrine, b: Doctrine) -> float:
	var dist := claims_distance(a.claims, b.claims)
	if a.basis != b.basis:
		dist += 0.06
	if a.structure != b.structure:
		dist += 0.03
	return dist


## The doctrine a family or a faction feels nearest to, if any is near enough
## to count as theirs.
static func sympathy_of(org: Organization) -> Doctrine:
	if org == null or org.ideology == null:
		return null
	if org.kind == Organization.OrgKind.FACTION and org.doctrine_id != &"":
		return get_doctrine(org.doctrine_id)
	var best: Doctrine = null
	var most := 0.6
	for d in living():
		var c := closeness(d, org.ideology)
		if c > most:
			most = c
			best = d
	return best


## Its argument, in a line: what makes rule right, who decides, and the two
## things it cares about most.
static func claims_text(d: Doctrine) -> String:
	var axes: Array = PoliticalSystemAxes.AXIS_NAMES.duplicate()
	axes.sort_custom(func(x: StringName, y: StringName) -> bool:
		return absf(float(d.claims.get(String(x), 0.0))) > absf(float(d.claims.get(String(y), 0.0))))
	var leans: Array[String] = []
	for a in axes.slice(0, 2):
		var v := float(d.claims.get(String(a), 0.0))
		if absf(v) >= 0.1:
			leans.append(AXIS_WORDS[a][1 if v > 0.0 else 0])
	var temper := "急進" if d.change >= 0.35 else ("守旧" if d.change <= -0.35 else "穏健")
	return "支配の正しさは%s、%s。%s%s" % [BASIS_LABELS.get(d.basis, "?"),
		STRUCTURE_LABELS.get(d.structure, "?"), "・".join(leans) + "を説く。" if not leans.is_empty() else "",
		temper]


## Everything a person wrote: [doctrine, entry].
static func works_of(person_id: StringName) -> Array:
	var out: Array = []
	for d in all():
		for t in d.thinkers:
			if StringName(t.get("person", "")) == person_id:
				out.append([d, t])
	return out


## The doctrines that came out of this one, directly.
static func children_of(id: StringName) -> Array[Doctrine]:
	var out: Array[Doctrine] = []
	for d in all():
		if d.parent_id == id or d.second_parent_id == id:
			out.append(d)
	return out


static func descendants_count(id: StringName) -> int:
	var count := 0
	var frontier: Array[StringName] = [id]
	var seen := {}
	while not frontier.is_empty():
		var next: Array[StringName] = []
		for x in frontier:
			for c in children_of(x):
				if not seen.has(c.doctrine_id):
					seen[c.doctrine_id] = true
					count += 1
					next.append(c.doctrine_id)
		frontier = next
	return count


## How freely a country lets people argue about how it should be run, 0..~1.3.
static func freedom_of(polity: Organization) -> float:
	var axes := polity.ideology
	if axes == null:
		return 0.0
	var f := 0.0
	match axes.decision_structure:
		PoliticalSystemAxes.DecisionStructure.ASSEMBLY:
			f = 0.85
		PoliticalSystemAxes.DecisionStructure.OLIGARCHIC_COUNCIL:
			f = 0.5
		_:
			f = 0.15
	match axes.legitimacy_basis:
		PoliticalSystemAxes.LegitimacyBasis.ELECTED:
			f += 0.3
		PoliticalSystemAxes.LegitimacyBasis.MERITOCRATIC:
			f += 0.2
		PoliticalSystemAxes.LegitimacyBasis.WEALTH_BASED:
			f += 0.15
		PoliticalSystemAxes.LegitimacyBasis.THEOCRATIC:
			f -= 0.15
		PoliticalSystemAxes.LegitimacyBasis.MILITARY_STRENGTH:
			f -= 0.2
	f += 0.25 * axes.tradition_reform + 0.15 * axes.isolationism_commerce \
		- 0.15 * axes.centralization
	return clampf(f, 0.0, 1.3)


# ======================================================================= step

static func step(tick: int) -> void:
	if tick % SimConfig.TICKS_PER_YEAR != STEP_SEASON:
		return
	var rng := RngService.stream(&"doctrine")
	var polities := GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM)
	polities.sort_custom(func(x: Organization, y: Organization) -> bool:
		return String(x.org_id) < String(y.org_id))
	_settle_fallen(tick)
	for polity in polities:
		_consider_birth(polity, tick, rng)
	_consider_revisions(tick, rng)
	for polity in polities:
		_consider_creed(polity, tick, rng)
	_consider_platforms(tick)
	_consider_suppression(polities, tick, rng)
	_settle_standing(polities, tick)


# ===================================================================== births

## A country loose enough to argue in, rich enough to keep people who write,
## with somebody in it who might — and a reason: hunger or anger breed radical
## doctrines, a long calm a conservative one, a fallen regime its mourners.
static func _consider_birth(polity: Organization, tick: int, rng: RandomNumberGenerator) -> void:
	if polity.ideology == null:
		return
	# The more doctrines are already being argued over, the less room for another.
	var room := clampf(1.0 - float(living().size()) / float(CROWDED), 0.1, 1.0)
	# From a reign: the death or end of a ruler whose reign is worth writing up.
	var reign := _finished_reign(polity, tick)
	if not reign.is_empty():
		var chance := GREAT_REIGN_CHANCE if bool(reign["great"]) else LONG_REIGN_CHANCE
		if rng.randf() < chance * room:
			var thinker := _thinker(polity, tick, rng, false)
			if thinker != null:
				_birth(polity, thinker, tick, rng, reign)
				return
	var freedom := freedom_of(polity)
	if freedom <= FREE_FLOOR:
		return
	var prosperity := _prosperity(polity)
	var chance := BIRTH_CHANCE * (freedom - FREE_FLOOR) / (1.0 - FREE_FLOOR) \
		* (0.5 + prosperity) * room
	if rng.randf() >= chance:
		return
	var thinker := _thinker(polity, tick, rng, true)
	if thinker != null:
		_birth(polity, thinker, tick, rng, {})


## The reign that ended in this country last year, if any is worth a doctrine:
## long, calm and legitimate, or called great by history.
static func _finished_reign(polity: Organization, tick: int) -> Dictionary:
	for i in range(HistoryLog.backbone.size() - 1, -1, -1):
		var e: HistoryEvent = HistoryLog.backbone[i]
		if e.tick < tick - SimConfig.TICKS_PER_YEAR:
			break
		if e.event_type == HistoryEvent.EventType.GREATNESS \
				and String(e.payload.get("field", "")) == "rule":
			# A reign history has called great is written up in the country
			# that came of it, even if the state it ruled has since changed form.
			var ruler := GameState.get_person(e.subject_person_id)
			if ruler != null:
				for t in ruler.role_history:
					var ruled := GameState.get_organization(t.org_id)
					if ruled != null and ruled.kind == Organization.OrgKind.POLITICAL_SYSTEM \
							and (ruled.org_id == polity.org_id or ruled.org_id == polity.parent_org_id):
						return {"ruler": ruler, "great": true, "polity": ruled}
		if e.event_type == HistoryEvent.EventType.SUCCESSION and e.subject_org_id == polity.org_id:
			var before := GameState.get_person(StringName(e.payload.get("previous_leader_id", "")))
			if before == null:
				continue
			var t := before.tenure_in(polity.org_id)
			if t == null or t.end_tick < 0:
				continue
			var years := int((t.end_tick - t.start_tick) / SimConfig.TICKS_PER_YEAR)
			if years >= LONG_REIGN_YEARS and polity.legitimacy >= 0.5:
				return {"ruler": before, "great": false, "polity": polity}
	return {}


static func _prosperity(polity: Organization) -> float:
	var wealth := 0.0
	var people := 0.0
	var count := 0
	for settlement_id in polity.governs_settlement_ids:
		var s: SettlementState = GameState.world.settlements.get(settlement_id)
		if s == null:
			continue
		wealth += s.wealth
		people += s.population
		count += 1
	if count == 0:
		return 0.0
	return clampf(wealth / float(count) / 400.0 + people / float(count) / 4000.0, 0.0, 1.0)


static func _unrest(polity: Organization) -> float:
	var total := 0.0
	var count := 0
	for settlement_id in polity.governs_settlement_ids:
		var s: SettlementState = GameState.world.settlements.get(settlement_id)
		if s != null:
			total += s.unrest + (0.3 if s.starving else 0.0)
			count += 1
	return total / float(count) if count > 0 else 0.0


## Who might write it: a grown member of one of the country's families — the
## learned first, the pious where faith rules, younger sons and daughters before
## heads of houses, who have other things to do.
static func _thinker(polity: Organization, tick: int, rng: RandomNumberGenerator,
		from_argument: bool) -> NotableIndividual:
	var candidates: Array = []
	var weights: Array = []
	var theocratic := polity.ideology.legitimacy_basis == PoliticalSystemAxes.LegitimacyBasis.THEOCRATIC
	var houses := GameState.organizations_of_kind(Organization.OrgKind.HOUSE)
	houses.sort_custom(func(x: Organization, y: Organization) -> bool:
		return String(x.org_id) < String(y.org_id))
	for house in houses:
		if house.standing == Organization.Standing.COMMONER \
				or CivilWar.realm_of_house(house) != polity.org_id:
			continue
		var members := GameState.house_members(house.org_id)
		members.sort_custom(func(x: NotableIndividual, y: NotableIndividual) -> bool:
			return String(x.person_id) < String(y.person_id))
		for p in members:
			if not p.is_adult(tick) or p.age_years(tick) > 70 or Offices._leads_a_state(p):
				continue
			var w := 1.0
			if p.has_tag(&"scholarly"):
				w += 4.0
			if theocratic and p.has_tag(&"pious"):
				w += 2.0
			if house.leader_person_id != p.person_id:
				w += 1.0
			if from_argument and p.has_tag(&"just"):
				w += 0.5
			candidates.append(p)
			weights.append(w)
	if candidates.is_empty():
		return null
	return RngService.pick_weighted(&"doctrine", candidates, weights)


## Works out what the new doctrine argues, where it comes from and what it is
## called, and records it.
static func _birth(polity: Organization, thinker: NotableIndividual, tick: int,
		rng: RandomNumberGenerator, reign: Dictionary) -> void:
	var claims := {}
	for a in PoliticalSystemAxes.AXIS_NAMES:
		claims[String(a)] = polity.ideology.get_axis(a)
	var basis := polity.ideology.legitimacy_basis
	var structure := polity.ideology.decision_structure
	var change := 0.0
	var fallen := _fallen_regime(polity, tick)
	var unrest := _unrest(polity)
	if not reign.is_empty():
		# Set down from the reign itself: what that country was, a little cleaner.
		change = -0.1
	elif not fallen.is_empty():
		# Mourning the old order: what it was, and how it was ruled.
		for key in fallen["axes"]:
			claims[key] = float(fallen["axes"][key])
		basis = int(fallen["basis"])
		structure = int(fallen["structure"])
		change = -0.6
	elif unrest >= 0.4:
		# Anger and hunger: remake it, and give it to the many.
		change = 0.7
		claims["tradition_reform"] = clampf(float(claims["tradition_reform"]) + 0.5, -1.0, 1.0)
		claims["centralization"] = clampf(float(claims["centralization"]) - 0.25, -1.0, 1.0)
		basis = [PoliticalSystemAxes.LegitimacyBasis.ELECTED,
			PoliticalSystemAxes.LegitimacyBasis.MERITOCRATIC][rng.randi_range(0, 1)]
		structure = PoliticalSystemAxes.DecisionStructure.ASSEMBLY
	elif polity.legitimacy >= 0.7:
		# A long calm: keep it as it is, and say why.
		change = -0.4
		claims["tradition_reform"] = clampf(float(claims["tradition_reform"]) - 0.35, -1.0, 1.0)
	else:
		change = rng.randf_range(-0.3, 0.5)
		if rng.randf() < 0.45:
			basis = rng.randi_range(0, PoliticalSystemAxes.LegitimacyBasis.size() - 1)
	# And the thinker's own turn of mind on two of the questions.
	var axes: Array = PoliticalSystemAxes.AXIS_NAMES.duplicate()
	for i in 2:
		var a := String(axes[rng.randi_range(0, axes.size() - 1)])
		claims[a] = clampf(float(claims[a]) + rng.randf_range(-0.4, 0.4), -1.0, 1.0)

	var probe := Doctrine.new()
	probe.claims = claims
	probe.basis = basis
	probe.structure = structure

	# Where it comes from.
	var parent: Doctrine = null
	var second: Doctrine = null
	var derivation := "root"
	if not GameState.doctrines.is_empty():
		var lineage := _lineage_for(probe, polity, fallen, reign)
		parent = lineage["parent"]
		second = lineage["second"]
		derivation = lineage["derivation"]
		if derivation == "development" or derivation == "revival":
			# Carried on from its parent: the new hand moves it only part of the way.
			for key in claims:
				claims[key] = lerpf(float(parent.claims.get(key, 0.0)), float(claims[key]), 0.55)
			basis = parent.basis if rng.randf() < 0.7 else basis
		elif derivation == "synthesis":
			for key in claims:
				claims[key] = (float(parent.claims.get(key, 0.0)) + float(second.claims.get(key, 0.0))) * 0.5
			basis = parent.basis
			structure = second.structure
		elif derivation == "reaction":
			# Against its parent: the opposite answer on what the parent cared most about.
			for key in claims:
				var theirs := float(parent.claims.get(key, 0.0))
				if absf(theirs - float(claims[key])) < 0.25:
					claims[key] = clampf(-theirs * 0.8 + float(claims[key]) * 0.2, -1.0, 1.0)
			if basis == parent.basis:
				basis = _opposite_basis(parent.basis)
			change = -signf(parent.change) * maxf(0.3, absf(change))
	if not reign.is_empty() and derivation == "root":
		derivation = "governance"
	elif not reign.is_empty() and derivation != "synthesis":
		derivation = "governance"

	var d := Doctrine.new()
	d.doctrine_id = GameState.mint_doctrine_id()
	d.claims = claims
	d.basis = basis
	d.structure = structure
	d.change = clampf(change, -1.0, 1.0)
	d.parent_id = parent.doctrine_id if parent != null else &""
	d.second_parent_id = second.doctrine_id if second != null else &""
	d.derivation = derivation
	d.founder_id = thinker.person_id
	d.born_tick = tick
	d.born_polity_id = polity.org_id
	d.home_polity_id = polity.org_id
	d.state = "rising"
	d.state_tick = tick
	d.maturity = 0.2
	d.prestige = 0.3 if reign.is_empty() else 0.45
	if not reign.is_empty():
		d.model_polity_id = (reign.get("polity", polity) as Organization).org_id
		d.model_ruler_id = (reign["ruler"] as NotableIndividual).person_id
	d.name = _name_for(d, thinker, parent, reign, rng)
	var work := (["『%s綱要』", "『%s原論』", "『%s要義』"][rng.randi_range(0, 2)] as String) \
		% _stem(d.name)
	d.thinkers = [{"person": String(thinker.person_id), "tick": tick, "kind": "founded",
		"work": work, "teacher": ""}]

	var how := ""
	match derivation:
		"root":
			how = "世界で初めての思想である"
		"development":
			how = "%sを受け継ぎ、改めたものだ" % parent.name
		"schism":
			how = "%sの解釈をめぐって袂を分かった" % parent.name
		"reaction":
			how = "%sへの反対から生まれた" % parent.name
		"synthesis":
			how = "%sと%sを一つにした" % [parent.name, second.name]
		"revival":
			how = "廃れた%sを蘇らせた" % parent.name
		"governance":
			var ruler: NotableIndividual = reign["ruler"]
			how = "%sの治世を範として体系にした%s" % [ruler.full_name,
				"" if parent == null else "（%sの流れを汲む）" % parent.name]
	var text := "%sの%sが%sを著し、%sを説いた。%s。" % [polity.formal_name(), thinker.full_name,
		work, d.name, how]
	HistoryLog.emit_event(HistoryEvent.EventType.DOCTRINE, tick, text,
		{"action": "born", "doctrine": d.to_dict(), "doctrine_id": String(d.doctrine_id),
			"derivation": derivation, "polity": String(polity.org_id)},
		polity.org_id, thinker.person_id,
		parent.origin_event_id if parent != null else polity.origin_event_id)


## Which existing doctrine a new one comes out of, and how.
static func _lineage_for(probe: Doctrine, polity: Organization, fallen: Dictionary,
		reign: Dictionary) -> Dictionary:
	var creed := creed_of(polity)
	if not fallen.is_empty() and fallen.has("creed"):
		var mourned: Doctrine = get_doctrine(StringName(fallen["creed"]))
		if mourned != null and mourned.is_alive():
			return {"parent": mourned, "second": null, "derivation": "development"}
	if not fallen.is_empty():
		# Mourning a regime against whatever the new one holds, or the nearest.
		var against := creed if creed != null else _farthest_prominent(probe)
		if against != null:
			return {"parent": against, "second": null, "derivation": "reaction"}
	if not reign.is_empty() and creed != null:
		return {"parent": creed, "second": null, "derivation": "governance"}
	var nearest: Doctrine = null
	var near := INF
	var second: Doctrine = null
	var second_near := INF
	for d in all():
		var dist := doctrine_distance(probe, d)
		if dist < near:
			second = nearest
			second_near = near
			nearest = d
			near = dist
		elif dist < second_near:
			second = d
			second_near = dist
	if nearest == null:
		return {"parent": null, "second": null, "derivation": "root"}
	if not nearest.is_alive() and near < 0.12 and not _was_revived(nearest):
		var dead_years := float(SimClock.current_tick - nearest.state_tick) / SimConfig.TICKS_PER_YEAR
		if dead_years >= REVIVAL_YEARS:
			return {"parent": nearest, "second": null, "derivation": "revival"}
	if second != null and nearest.is_alive() and second.is_alive() and near < 0.12 \
			and second_near < 0.14 and doctrine_distance(nearest, second) > 0.1:
		return {"parent": nearest, "second": second, "derivation": "synthesis"}
	if near < 0.07:
		return {"parent": nearest, "second": null, "derivation": "development"}
	if near < 0.16:
		return {"parent": nearest, "second": null, "derivation": "schism"}
	var against := _farthest_prominent(probe)
	return {"parent": against if against != null else nearest, "second": null,
		"derivation": "reaction"}


## A doctrine is brought back once; after that it is somebody else's.
static func _was_revived(d: Doctrine) -> bool:
	for c in children_of(d.doctrine_id):
		if c.derivation == "revival":
			return true
	return d.derivation == "revival"


static func _farthest_prominent(probe: Doctrine) -> Doctrine:
	var best: Doctrine = null
	var score := -INF
	for d in living():
		var s := doctrine_distance(probe, d) + d.prestige * 0.2
		if s > score:
			score = s
			best = d
	return best


static func _opposite_basis(basis: int) -> int:
	match basis:
		PoliticalSystemAxes.LegitimacyBasis.HEREDITARY:
			return PoliticalSystemAxes.LegitimacyBasis.ELECTED
		PoliticalSystemAxes.LegitimacyBasis.ELECTED:
			return PoliticalSystemAxes.LegitimacyBasis.HEREDITARY
		PoliticalSystemAxes.LegitimacyBasis.THEOCRATIC:
			return PoliticalSystemAxes.LegitimacyBasis.MERITOCRATIC
		PoliticalSystemAxes.LegitimacyBasis.MILITARY_STRENGTH:
			return PoliticalSystemAxes.LegitimacyBasis.ELECTED
		PoliticalSystemAxes.LegitimacyBasis.WEALTH_BASED:
			return PoliticalSystemAxes.LegitimacyBasis.THEOCRATIC
	return PoliticalSystemAxes.LegitimacyBasis.HEREDITARY


## A regime of this country that fell in the last decade: what it was, and the
## creed it held.
static func _fallen_regime(polity: Organization, tick: int) -> Dictionary:
	for i in range(HistoryLog.backbone.size() - 1, -1, -1):
		var e: HistoryEvent = HistoryLog.backbone[i]
		if e.tick < tick - 10 * SimConfig.TICKS_PER_YEAR:
			break
		if e.event_type == HistoryEvent.EventType.SCHISM \
				and e.subject_org_id == polity.org_id and polity.parent_org_id != &"":
			var old := GameState.get_organization(polity.parent_org_id)
			if old != null and old.kind == Organization.OrgKind.POLITICAL_SYSTEM \
					and old.ideology != null:
				var axes := {}
				for a in PoliticalSystemAxes.AXIS_NAMES:
					axes[String(a)] = old.ideology_baseline.get_axis(a) \
						if old.ideology_baseline != null else old.ideology.get_axis(a)
				var out := {"axes": axes, "basis": old.ideology.legitimacy_basis,
					"structure": old.ideology.decision_structure}
				if old.doctrine_id != &"":
					out["creed"] = String(old.doctrine_id)
				return out
	return {}


static func _name_for(d: Doctrine, founder: NotableIndividual, parent: Doctrine,
		reign: Dictionary, rng: RandomNumberGenerator) -> String:
	var taken := {}
	for other in all():
		taken[other.name] = true
	var options: Array[String] = []
	if d.derivation == "revival" and parent != null and not parent.name.begins_with("新"):
		options.append("新" + parent.name)
	if not reign.is_empty():
		var ruler: NotableIndividual = reign["ruler"]
		options.append("%s王道論" % ruler.given_name)
		options.append("%s主義" % ruler.given_name)
	# From what it argues: its basis, or the axis it leans hardest on.
	var named: Array = []
	if rng.randf() < 0.5:
		named.append_array(BASIS_NAMES.get(d.basis, []))
	var strongest := ""
	var lean := 0.0
	for a in PoliticalSystemAxes.AXIS_NAMES:
		var v := float(d.claims.get(String(a), 0.0))
		if absf(v) > absf(lean):
			lean = v
			strongest = String(a)
	if strongest != "":
		named.append_array(AXIS_NAMES.get(strongest + ("+" if lean > 0.0 else "-"), []))
	named.append_array(BASIS_NAMES.get(d.basis, []))
	for n in named:
		options.append(String(n))
	# Or from whoever wrote it.
	options.append("%s主義" % founder.given_name)
	options.append("%s学派" % founder.given_name)
	for n in options:
		if not taken.has(n):
			return n
	var i := 2
	while taken.has("%s学派（第%d）" % [founder.given_name, i]):
		i += 1
	return "%s学派（第%d）" % [founder.given_name, i]


## The part of a name a book is titled after: 共和主義 -> 共和.
static func _stem(name: String) -> String:
	for suffix in ["主義", "学派", "論"]:
		if name.ends_with(suffix) and name.length() > suffix.length():
			return name.substr(0, name.length() - suffix.length())
	return name


# ================================================================== revisions

## Every few decades somebody takes up a living doctrine and writes it again —
## a pupil of the last to have done so where one can be found. A revision moves
## it toward the time it is written in; moved far enough, it is a new doctrine.
static func _consider_revisions(tick: int, rng: RandomNumberGenerator) -> void:
	for d in living():
		if rng.randf() >= 1.0 / REVISION_YEARS:
			continue
		var home := GameState.get_organization(d.home_polity_id)
		if home == null or not home.is_active():
			home = _best_home(d)
		if home == null or home.ideology == null:
			continue
		var thinker := _thinker(home, tick, rng, true)
		if thinker == null:
			continue
		var moved := {}
		for a in PoliticalSystemAxes.AXIS_NAMES:
			var key := String(a)
			moved[key] = lerpf(float(d.claims.get(key, 0.0)), home.ideology.get_axis(a), 0.2) \
				+ rng.randf_range(-0.06, 0.06)
		var origin := _origin_claims(d)
		if claims_distance(moved, origin) > SPLIT_DRIFT and freedom_of(home) > FREE_FLOOR:
			_birth_split(d, home, thinker, tick, rng)
			continue
		var last: Dictionary = d.thinkers.back() if not d.thinkers.is_empty() else {}
		var teacher := String(last.get("person", ""))
		var work := (WORK_FORMS[rng.randi_range(0, WORK_FORMS.size() - 1)] as String) % _stem(d.name)
		HistoryLog.emit_event(HistoryEvent.EventType.DOCTRINE, tick,
			"%sの%sが%sを著し、%sを改めた。" % [home.formal_name(), thinker.full_name, work, d.name],
			{"action": "revised", "doctrine_id": String(d.doctrine_id), "person": String(thinker.person_id),
				"work": work, "teacher": teacher, "claims": moved,
				"maturity": minf(1.0, d.maturity + 0.15), "polity": String(home.org_id)},
			home.org_id, thinker.person_id, d.origin_event_id)


## What a doctrine argued when it was written, before any revision.
static func _origin_claims(d: Doctrine) -> Dictionary:
	return d.origin_claims if not d.origin_claims.is_empty() else d.claims


## A revision that went too far: the pupil founds a school of their own.
static func _birth_split(d: Doctrine, home: Organization, thinker: NotableIndividual, tick: int,
		rng: RandomNumberGenerator) -> void:
	var child := Doctrine.new()
	child.doctrine_id = GameState.mint_doctrine_id()
	var claims := {}
	for a in PoliticalSystemAxes.AXIS_NAMES:
		claims[String(a)] = lerpf(float(d.claims.get(String(a), 0.0)), home.ideology.get_axis(a), 0.5)
	child.claims = claims
	child.basis = d.basis
	child.structure = d.structure
	child.change = clampf(d.change + rng.randf_range(-0.3, 0.3), -1.0, 1.0)
	child.parent_id = d.doctrine_id
	child.derivation = "schism"
	child.founder_id = thinker.person_id
	child.born_tick = tick
	child.born_polity_id = home.org_id
	child.home_polity_id = home.org_id
	child.state_tick = tick
	child.prestige = 0.25
	child.name = _name_for(child, thinker, d, {}, rng)
	var last: Dictionary = d.thinkers.back() if not d.thinkers.is_empty() else {}
	var work := "『%s批判』" % _stem(d.name)
	child.thinkers = [{"person": String(thinker.person_id), "tick": tick, "kind": "founded",
		"work": work, "teacher": String(last.get("person", ""))}]
	HistoryLog.emit_event(HistoryEvent.EventType.DOCTRINE, tick,
		"%sの%sは%sで師の%sを批判し、%sを唱えて一派を立てた。" % [home.formal_name(),
			thinker.full_name, work, d.name, child.name],
		{"action": "born", "doctrine": child.to_dict(), "doctrine_id": String(child.doctrine_id),
			"derivation": "schism", "polity": String(home.org_id)},
		home.org_id, thinker.person_id, d.origin_event_id)


static func _best_home(d: Doctrine) -> Organization:
	var best: Organization = null
	var most := -1.0
	for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		if polity.ideology == null:
			continue
		var c := closeness(d, polity.ideology) + freedom_of(polity) * 0.3
		if c > most:
			most = c
			best = polity
	return best


# ===================================================================== creeds

## Whether a country takes a doctrine up as its creed, keeps it, or lets it go.
static func _consider_creed(polity: Organization, tick: int, rng: RandomNumberGenerator) -> void:
	if polity.ideology == null:
		return
	var creed := creed_of(polity)
	if creed != null:
		var c := closeness(creed, polity.ideology)
		if c < ABANDON_CLOSENESS or not creed.is_alive():
			_abandon(polity, creed, tick, "drift" if creed.is_alive() else "faded")
			creed = null
		else:
			# A creed pulls the country's ideals toward its picture, and is a
			# source of the regime's right to rule if the great families share
			# it — and a drag on it if they do not.
			for a in PoliticalSystemAxes.AXIS_NAMES:
				polity.ideology.nudge_axis(a, float(creed.claims.get(String(a), 0.0)), CREED_PULL)
			polity.legitimacy = clampf(polity.legitimacy
				+ CREED_LEGITIMACY * (creed.support - 0.45) * 2.0, 0.05, 1.0)
			return
	var reason := _occasion(polity, tick)
	var best: Doctrine = null
	var most := ADOPT_CLOSENESS
	for d in living():
		if d.state == "underground" and freedom_of(polity) < FREE_FLOOR:
			continue
		var c := closeness(d, polity.ideology) + 0.25 * d.prestige
		if reason.has("doctrine") and StringName(reason["doctrine"]) == d.doctrine_id:
			c += 0.4
		if c > most:
			most = c
			best = d
	if best == null:
		return
	var chance := 0.5 if not reason.is_empty() else 0.02 * best.prestige
	if rng.randf() >= chance:
		return
	_adopt(polity, best, tick, String(reason.get("why", "")))


## What makes a country reach for a creed now: a new regime, a chamber held by a
## faction marching under one, a ruler who was taught one.
static func _occasion(polity: Organization, tick: int) -> Dictionary:
	if _regime_is_new(polity, tick):
		return {"why": "新しい体制は"}
	if polity.seat_total > 0:
		for faction_id in polity.faction_seats:
			var faction := GameState.get_organization(faction_id)
			if faction != null and faction.doctrine_id != &"" \
					and float(polity.faction_seats[faction_id]) / float(polity.seat_total) > 0.5:
				return {"why": "議場を握った%sが" % faction.formal_name(),
					"doctrine": String(faction.doctrine_id)}
	var ruler := GameState.get_current_leader(polity.org_id)
	if ruler != null:
		for entry in works_of(ruler.person_id):
			return {"why": "自ら筆を執った長が", "doctrine": String((entry[0] as Doctrine).doctrine_id)}
		for d in living():
			for t in d.thinkers:
				var writer := GameState.get_person(StringName(t.get("person", "")))
				if writer != null and writer.house_org_id == ruler.house_org_id and writer.is_alive():
					return {"why": "門人である長が", "doctrine": String(d.doctrine_id)}
	return {}


## Whether this country's present order was set up in the last few years.
static func _regime_is_new(polity: Organization, tick: int) -> bool:
	for i in range(HistoryLog.backbone.size() - 1, -1, -1):
		var e: HistoryEvent = HistoryLog.backbone[i]
		if e.tick < tick - 3 * SimConfig.TICKS_PER_YEAR:
			break
		if e.subject_org_id != polity.org_id:
			continue
		if e.event_type == HistoryEvent.EventType.SCHISM and polity.parent_org_id != &"":
			return true
		if e.event_type == HistoryEvent.EventType.POWER_TRANSFER \
				and bool(e.payload.get("regime_change", false)):
			return true
	return false


static func _adopt(polity: Organization, d: Doctrine, tick: int, why: String) -> void:
	var text := "%sは%sを国是とした。" % [polity.formal_name(), d.name]
	if why != "":
		text = "%s%sを国是に掲げた（%s）。" % [why, d.name, polity.formal_name()]
	HistoryLog.emit_event(HistoryEvent.EventType.DOCTRINE, tick, text,
		{"action": "adopted", "doctrine_id": String(d.doctrine_id), "polity": String(polity.org_id)},
		polity.org_id, polity.leader_person_id, d.origin_event_id)


static func _abandon(polity: Organization, d: Doctrine, tick: int, reason: String,
		polity_id: StringName = &"") -> void:
	if polity != null:
		polity_id = polity.org_id
	var text: String = {
		"drift": "%sは%sを国是から外した。国の向きはもはやその教えと合わない。",
		"faded": "%sは廃れた%sを国是から外した。",
		"fell": "%sが倒れ、%sは国是としての拠り所を失った。",
	}.get(reason, "%sは%sを国是から外した。") % [polity.formal_name() if polity != null
		else "その国", d.name]
	HistoryLog.emit_event(HistoryEvent.EventType.DOCTRINE, tick, text,
		{"action": "abandoned", "doctrine_id": String(d.doctrine_id), "polity": String(polity_id),
			"reason": reason},
		polity_id, polity.leader_person_id if polity != null else &"", d.origin_event_id)


## A country that fell takes its creed's good name down with it.
static func _settle_fallen(tick: int) -> void:
	for d in all():
		for a in d.adoptions:
			if int(a.get("end", -1)) >= 0:
				continue
			var polity_id := StringName(a.get("polity", ""))
			var polity := GameState.get_organization(polity_id)
			if polity == null or not polity.is_active():
				d.prestige = maxf(0.0, d.prestige - 0.2)
				_abandon(polity, d, tick, "fell", polity_id)


## Factions take the doctrine nearest their own ideals as their platform.
static func _consider_platforms(tick: int) -> void:
	for faction in GameState.organizations_of_kind(Organization.OrgKind.FACTION):
		if faction.ideology == null:
			continue
		var best: Doctrine = null
		var most := 0.65
		for d in living():
			var c := closeness(d, faction.ideology)
			if c > most + (0.08 if d.doctrine_id != faction.doctrine_id else 0.0):
				most = c
				best = d
		var current := get_doctrine(faction.doctrine_id)
		if current != null and current.is_alive() and closeness(current, faction.ideology) >= 0.5:
			continue
		var new_id := best.doctrine_id if best != null else &""
		if new_id == faction.doctrine_id:
			continue
		HistoryLog.emit_event(HistoryEvent.EventType.DOCTRINE, tick,
			"%sは%s。" % [faction.formal_name(), "%sを綱領に掲げた" % best.name if best != null
				else "掲げていた綱領を降ろした"],
			{"action": "platform", "doctrine_id": String(new_id), "faction": String(faction.org_id)},
			faction.org_id, faction.leader_person_id, faction.origin_event_id)


## A closed regime that cannot stomach a doctrine drives its thinkers out.
static func _consider_suppression(polities: Array[Organization], tick: int,
		rng: RandomNumberGenerator) -> void:
	for d in living():
		var home := GameState.get_organization(d.home_polity_id)
		if home == null or not home.is_active() or home.ideology == null:
			continue
		if freedom_of(home) >= FREE_FLOOR or closeness(d, home.ideology) >= 0.35 \
				or home.doctrine_id == d.doctrine_id:
			continue
		if rng.randf() >= 0.15:
			continue
		var victim: NotableIndividual = null
		for t in d.thinkers:
			var p := GameState.get_person(StringName(t.get("person", "")))
			if p != null and p.is_alive():
				victim = p
		var refuge: Organization = null
		var best := FREE_FLOOR
		for polity in polities:
			if polity.org_id != home.org_id and polity.ideology != null and freedom_of(polity) > best:
				best = freedom_of(polity)
				refuge = polity
		var fate := "exiled" if refuge != null else "jailed"
		var text := "%sは%sを危険な教えとして禁じた。" % [home.formal_name(), d.name]
		if victim != null:
			text += "%sは%s。" % [victim.full_name, "国を追われた" if fate == "exiled" else "獄に繋がれた"]
		text += "教えは%s。" % ("%sへ移った" % refuge.formal_name() if refuge != null else "地下に潜った")
		HistoryLog.emit_event(HistoryEvent.EventType.DOCTRINE, tick, text,
			{"action": "suppressed", "doctrine_id": String(d.doctrine_id), "polity": String(home.org_id),
				"person": String(victim.person_id) if victim != null else "", "fate": fate,
				"home": String(refuge.org_id) if refuge != null else String(home.org_id),
				"state": "rising" if refuge != null else "underground"},
			home.org_id, victim.person_id if victim != null else &"", d.origin_event_id)


## How admired each doctrine is, how widely shared, what the faith makes of it —
## and the ones nobody holds any more fade away.
static func _settle_standing(polities: Array[Organization], tick: int) -> void:
	var holders: Array[Organization] = []
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.is_noble() and house.ideology != null:
			holders.append(house)
	for faction in GameState.organizations_of_kind(Organization.OrgKind.FACTION):
		if faction.ideology != null:
			holders.append(faction)
	var faith := Religion.dominant_faith()
	for d in all():
		if not d.is_alive():
			continue
		var weight := 0.0
		var shared := 0.0
		for org in holders:
			var w := maxf(1.0, org.power_score)
			weight += w
			shared += w * closeness(d, org.ideology)
		d.support = shared / weight if weight > 0.0 else 0.0
		var held := d.adopted_by()
		if held.is_empty():
			d.prestige = maxf(0.0, d.prestige - NEGLECT)
		for polity_id in held:
			var polity := GameState.get_organization(polity_id)
			if polity != null:
				# A creed is judged by the country that holds it.
				d.prestige = clampf(d.prestige + 0.03 * (polity.legitimacy - 0.5)
					+ 0.02 * (_prosperity(polity) - 0.4), 0.0, 1.0)
		d.prestige = clampf(d.prestige + 0.01 * (d.support - 0.4), 0.0, 1.0)
		# What the dominant faith makes of it, once it has decided.
		if faith != null and d.faith_stance == "":
			var theocratic := float(d.claims.get("secular_theocratic", 0.0))
			var stance := "blessed" if theocratic >= 0.5 \
				or d.basis == PoliticalSystemAxes.LegitimacyBasis.THEOCRATIC else (
				"heresy" if theocratic <= -0.5 or d.change >= 0.75 else "")
			if stance != "":
				HistoryLog.emit_event(HistoryEvent.EventType.DOCTRINE, tick,
					"%sは%sを%s。" % [faith.display_name, d.name,
						"祝福した" if stance == "blessed" else "異端と断じた"],
					{"action": "faith", "doctrine_id": String(d.doctrine_id), "stance": stance,
						"faith": String(faith.org_id)},
					faith.org_id, faith.leader_person_id, d.origin_event_id)
		if d.faith_stance == "blessed":
			d.prestige = minf(1.0, d.prestige + 0.004)
		elif d.faith_stance == "heresy" and Religion.division() < 0.3:
			d.prestige = maxf(0.0, d.prestige - 0.004)
		var age := float(tick - d.born_tick) / SimConfig.TICKS_PER_YEAR
		var platform := false
		for faction in GameState.organizations_of_kind(Organization.OrgKind.FACTION):
			if faction.doctrine_id == d.doctrine_id:
				platform = true
		if d.prestige < FADE_PRESTIGE and held.is_empty() and not platform and age >= FADE_MIN_YEARS:
			HistoryLog.emit_event(HistoryEvent.EventType.DOCTRINE, tick,
				"%sを説く者は絶え、その教えは廃れた。" % d.name,
				{"action": "state", "doctrine_id": String(d.doctrine_id), "state": "faded"},
				d.home_polity_id, &"", d.origin_event_id)
		elif d.state == "underground" and not held.is_empty():
			HistoryLog.emit_event(HistoryEvent.EventType.DOCTRINE, tick,
				"%sはふたたび表で語られるようになった。" % d.name,
				{"action": "state", "doctrine_id": String(d.doctrine_id), "state": "rising"},
				d.home_polity_id, &"", d.origin_event_id)

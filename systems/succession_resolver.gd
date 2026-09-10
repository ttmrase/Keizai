class_name SuccessionResolver
extends RefCounted

## Fills an empty seat. When more than one credible claimant exists the contest
## is decided by weight, not by rank alone — and an ambitious loser may walk out
## and found their own line, which is where most branches in a long game come from.

## Fallback used when no rule is authored for an organization's kind.
const DEFAULT_SCHISM_CHANCE_ON_LOSS := 0.3


static func resolve(org: Organization, tick: int) -> void:
	var rule := _rule_for(org)
	var candidates := _eligible(_candidates(org, tick, rule), org)
	if candidates.is_empty():
		# Nobody alive can take it. The seat stays empty until some house
		# produces an heir who can — people are never conjured up to fill a post,
		# so an institution really can outlive everyone willing to lead it.
		return

	var rng := RngService.stream(&"rules")
	var weights: Array = []
	for c in candidates:
		weights.append(_claim_weight(c, org, tick, rule))

	var winner: NotableIndividual = RngService.pick_weighted(&"rules", candidates, weights)
	if winner == null:
		return

	var previous_id := _previous_leader_id(org)
	var previous := GameState.get_person(previous_id)
	var contested := candidates.size() > 1 and rule != null and rule.allow_dispute
	var minority := contested and _is_a_minority(org, previous, tick)

	var fallout := {}
	if contested:
		fallout = _settle_dispute(org, candidates, winner, minority, tick, rule)

	var text := "%sの%sに%sが就いた。" % [org.display_name, org.leadership_title, winner.full_name]
	if contested:
		text = "%s%sの%sをめぐる争いの末、%sが座に就いた。%s" % [
			"幼い直子を差し置いて、" if minority else "",
			org.display_name, org.leadership_title, winner.full_name,
			fallout.get("text", "")]

	var payload := {
		"previous_leader_id": String(previous_id),
		"contested": contested,
		"claimants": candidates.size(),
	}
	if minority:
		payload["minority"] = true
	if not fallout.is_empty():
		payload["severity"] = fallout["severity_name"]
		payload["loser_id"] = String(fallout["loser"].person_id)
		if fallout["severity"] == Severity.RETIREMENT:
			payload["retire_from"] = String(org.org_id)
		elif fallout["severity"] == Severity.DISINHERITANCE:
			payload["disinherit"] = true

	HistoryLog.emit_event(
		HistoryEvent.EventType.SUCCESSION,
		tick,
		text,
		payload,
		org.org_id,
		winner.person_id,
		previous.death_event_id if previous != null else org.origin_event_id)

	if not fallout.is_empty():
		_settle_backers(org, fallout, tick)
		if fallout["severity"] == Severity.DEPARTURE:
			SchismResolver.create_branch(org, _succession_schism_rule(org, rule), tick,
				fallout["loser"])


# ---------------------------------------------------------------- candidates

## A monarch may also head their own house — different kinds of authority, and
## historically the same person. Holding two thrones at once is another matter:
## rival states descended from the same dynasty would otherwise all crown the
## same claimant and quietly become one state again.
static func _eligible(candidates: Array[NotableIndividual],
		org: Organization) -> Array[NotableIndividual]:
	var out: Array[NotableIndividual] = []
	for p in candidates:
		if p == null or not p.is_alive():
			continue
		if _already_leads_kind(p, org.kind):
			continue
		# Somebody who stood down from this seat is not put forward for it again,
		# and somebody who was cut off is not put forward for anything.
		if p.is_disinherited() or p.has_retired_from(org.org_id):
			continue
		out.append(p)
	return out


static func _already_leads_kind(person: NotableIndividual, kind: Organization.OrgKind) -> bool:
	for t in person.role_history:
		if not t.is_current():
			continue
		var held := GameState.get_organization(t.org_id)
		if held != null and held.is_active() and held.kind == kind:
			return true
	return false

static func _candidates(org: Organization, tick: int, rule: TriggerRule) -> Array[NotableIndividual]:
	var method := rule.method if rule != null else TriggerRule.SuccessionMethod.PRIMOGENITURE
	var basis := org.ideology.legitimacy_basis if org.ideology != null \
		else PoliticalSystemAxes.LegitimacyBasis.HEREDITARY

	# The regime's own legitimacy basis overrides the authored default: once a
	# polity has drifted to electing its leaders, blood stops deciding.
	match basis:
		PoliticalSystemAxes.LegitimacyBasis.ELECTED, PoliticalSystemAxes.LegitimacyBasis.MERITOCRATIC:
			method = TriggerRule.SuccessionMethod.ELECTIVE
		PoliticalSystemAxes.LegitimacyBasis.MILITARY_STRENGTH:
			method = TriggerRule.SuccessionMethod.MILITARY_STRONGEST
		_:
			pass

	# A house can only be headed by its own blood. If none of it is left standing,
	# the house has no head and will shortly have no house either — an outsider is
	# never brought in to keep the name alive.
	if org.kind == Organization.OrgKind.HOUSE:
		return _house_candidates(org, tick)

	# A guild or faction whose leadership one family has held for generations
	# fills the seat from that family — the office has become theirs in practice
	# long before anybody writes it down.
	if org.kind != Organization.OrgKind.POLITICAL_SYSTEM and org.patron_house_id != &"" \
			and SocialTies.office_basis(org) == SocialTies.OfficeBasis.HEREDITARY:
		var from_patron := _patron_house_candidates(org, tick)
		if not from_patron.is_empty():
			return from_patron

	if org.kind == Organization.OrgKind.POLITICAL_SYSTEM \
			and method == TriggerRule.SuccessionMethod.PRIMOGENITURE:
		var from_house := _ruling_house_candidates(org, tick)
		if not from_house.is_empty():
			return from_house

	if method == TriggerRule.SuccessionMethod.PRIMOGENITURE:
		var heirs := _bloodline_heirs(org, tick)
		if not heirs.is_empty():
			return heirs

	return _open_candidates(org, tick)


## The adults of the family that has come to own this office.
static func _patron_house_candidates(org: Organization, tick: int) -> Array[NotableIndividual]:
	var house := GameState.get_organization(org.patron_house_id)
	if house == null or not house.is_active():
		return []
	var out: Array[NotableIndividual] = []
	for member in GameState.house_members(house.org_id):
		if member.is_adult(tick) and member.current_tenure() == null:
			out.append(member)
	return out


## The house's own adults, children of the late head first.
static func _house_candidates(org: Organization, tick: int) -> Array[NotableIndividual]:
	var previous := GameState.get_person(_previous_leader_id(org))
	var direct: Array[NotableIndividual] = []
	var kin: Array[NotableIndividual] = []
	for member in GameState.house_members(org.org_id):
		if not member.is_adult(tick) or member.current_tenure() != null:
			continue
		if previous != null and previous.children_ids.has(member.person_id):
			direct.append(member)
		else:
			kin.append(member)
	return direct if not direct.is_empty() else kin


static func _bloodline_heirs(org: Organization, tick: int) -> Array[NotableIndividual]:
	var out: Array[NotableIndividual] = []
	var previous := GameState.get_person(_previous_leader_id(org))
	if previous != null:
		for child in GameState.children_of(previous.person_id):
			if child.is_adult(tick) and child.current_tenure() == null:
				out.append(child)
	if out.is_empty() and org.kind == Organization.OrgKind.HOUSE:
		for member in GameState.house_members(org.org_id):
			if member.is_adult(tick) and member.current_tenure() == null:
				out.append(member)
	return out


static func _ruling_house_candidates(org: Organization, tick: int) -> Array[NotableIndividual]:
	var previous := GameState.get_person(_previous_leader_id(org))
	if previous == null or previous.house_org_id == &"":
		return []
	var house := GameState.get_organization(previous.house_org_id)
	if house == null or not house.is_active():
		return []
	# The crown follows whoever now heads the house that held it.
	var head := GameState.get_person(house.leader_person_id)
	if head != null and head.is_alive():
		return [head]
	var out: Array[NotableIndividual] = []
	for member in GameState.house_members(house.org_id):
		if member.is_adult(tick):
			out.append(member)
	return out


static func _open_candidates(org: Organization, tick: int) -> Array[NotableIndividual]:
	var out: Array[NotableIndividual] = []
	for p in GameState.living_people():
		if not p.is_adult(tick) or p.current_tenure() != null:
			continue
		if p.age_years(tick) > 68:
			continue
		out.append(p)
	# Keep the contest legible: the few strongest claims, not the whole populace.
	out.sort_custom(func(a, b): return _static_prestige(a) > _static_prestige(b))
	return out.slice(0, 4)


static func _static_prestige(p: NotableIndividual) -> float:
	var score := 1.0
	if p.has_tag(&"ambitious"):
		score += 1.2
	if p.has_tag(&"martial"):
		score += 0.6
	if p.has_tag(&"scholarly"):
		score += 0.4
	if p.house_org_id != &"":
		score += 0.8
	return score


static func _claim_weight(p: NotableIndividual, org: Organization, tick: int,
		rule: TriggerRule) -> float:
	var w := _static_prestige(p)
	var method := rule.method if rule != null else TriggerRule.SuccessionMethod.PRIMOGENITURE
	match method:
		TriggerRule.SuccessionMethod.PRIMOGENITURE:
			# Seniority counts, but does not settle it outright.
			w += clampf(p.age_years(tick) / 40.0, 0.0, 1.5)
		TriggerRule.SuccessionMethod.MILITARY_STRONGEST:
			w += 2.0 if p.has_tag(&"martial") else 0.0
		TriggerRule.SuccessionMethod.MERITOCRATIC_APPOINTMENT:
			w += 1.5 if p.has_tag(&"scholarly") else 0.0
		TriggerRule.SuccessionMethod.ELECTIVE:
			w += 1.2 if p.has_tag(&"just") else 0.0
	if org.ideology != null \
			and org.ideology.legitimacy_basis == PoliticalSystemAxes.LegitimacyBasis.THEOCRATIC \
			and p.has_tag(&"pious"):
		w += 1.5
	# Where birth counts, it counts here. A duke's son walks into a temple or a
	# counting house; under a popular assembly the same name buys him nothing,
	# and a knight's son never had much to spend.
	w += HouseRank.weight_for(org) * HouseRank.precedence_of_person(p) * 0.35
	return maxf(0.1, w)


# ------------------------------------------------------------------ fallout

## How badly a contested succession ends. Most quarrels are settled by somebody
## standing aside; a real one costs the family a branch; the worst end with a
## claimant cut off entirely.
enum Severity { RETIREMENT, DEPARTURE, DISINHERITANCE }

const SEVERITY_NAMES := {
	Severity.RETIREMENT: "retirement",
	Severity.DEPARTURE: "departure",
	Severity.DISINHERITANCE: "disinheritance",
}

## Heat above which the loser leaves with a following, and above which they are
## cut off instead.
const DEPARTURE_HEAT := 0.78
const DISINHERITANCE_HEAT := 0.97

## What sharpens a quarrel: a close-run contest, an ambitious loser, a seat worth
## having, and a succession that went sideways over the late head's own children.
const CLOSENESS_HEAT := 0.45
const AMBITION_HEAT := 0.28
const STAKES_HEAT := 0.22
const MINORITY_HEAT := 0.18


## Works out who lost, how badly they took it, and who backed whom. Nothing is
## recorded here — the caller folds it into the one succession event, so the
## chronicle reads as a single thing that happened rather than three.
static func _settle_dispute(org: Organization, candidates: Array[NotableIndividual],
		winner: NotableIndividual, minority: bool, tick: int, rule: TriggerRule) -> Dictionary:
	var loser: NotableIndividual = null
	var loser_weight := -1.0
	var winner_weight := maxf(0.01, _claim_weight(winner, org, tick, rule))
	for p in candidates:
		if p.person_id == winner.person_id:
			continue
		var w := _claim_weight(p, org, tick, rule)
		if w > loser_weight:
			loser_weight = w
			loser = p
	if loser == null:
		return {}

	var heat := CLOSENESS_HEAT * clampf(loser_weight / winner_weight, 0.0, 1.0)
	if loser.has_tag(&"ambitious"):
		heat += AMBITION_HEAT
	if loser.has_tag(&"cautious"):
		heat -= AMBITION_HEAT
	heat += STAKES_HEAT * clampf(HouseRank.precedence(org) / 8.0, 0.0, 1.0)
	if minority:
		heat += MINORITY_HEAT
	heat += RngService.stream(&"rules").randf_range(-0.18, 0.18)

	var severity := Severity.RETIREMENT
	if heat >= DISINHERITANCE_HEAT:
		severity = Severity.DISINHERITANCE
	elif heat >= DEPARTURE_HEAT:
		severity = Severity.DEPARTURE

	# A claimant only storms off to found a house if there is a house to found.
	# Where the world has no room for another, the quarrel ends the quiet way
	# instead of the chronicle recording a departure that never happened.
	if severity == Severity.DEPARTURE \
			and not SchismResolver.has_room_for_branch(org, _succession_schism_rule(org, rule)):
		severity = Severity.RETIREMENT

	var backers := {}
	if severity != Severity.RETIREMENT:
		backers = _take_sides(org, winner, loser)

	return {
		"severity": severity,
		"severity_name": SEVERITY_NAMES[severity],
		"loser": loser,
		"backers": backers,
		"text": _fallout_text(severity, winner, loser, backers),
	}


static func _fallout_text(severity: Severity, winner: NotableIndividual,
		loser: NotableIndividual, backers: Dictionary) -> String:
	var taken := _sides_text(winner, loser, backers)
	match severity:
		Severity.RETIREMENT:
			return "%sは争わずに隠居した。" % loser.full_name
		Severity.DEPARTURE:
			return "%s%sは家を出た。" % [taken, loser.full_name]
	return "%s%sは廃嫡され、家を追われた。" % [taken, loser.full_name]


## Who the households in service came out for. Named, because whose side they
## took is the thing their own standing then rests on, and a family that reads
## the room wrong should be seen doing it.
static func _sides_text(winner: NotableIndividual, loser: NotableIndividual,
		backers: Dictionary) -> String:
	if backers.is_empty():
		return ""
	var for_winner: Array[String] = []
	var for_loser: Array[String] = []
	for house_id in backers:
		var house := GameState.get_organization(house_id)
		if house == null:
			continue
		if bool(backers[house_id]):
			for_winner.append(house.display_name)
		else:
			for_loser.append(house.display_name)
	if for_loser.is_empty():
		return "%sはこぞって%sを推した。" % ["・".join(for_winner.slice(0, 2)), winner.full_name]
	if for_winner.is_empty():
		return "%sは%sを推したが及ばなかった。" % ["・".join(for_loser.slice(0, 2)), loser.full_name]
	return "%sは%sを、%sは%sを推し、家中は割れた。" % [
		"・".join(for_winner.slice(0, 2)), winner.full_name,
		"・".join(for_loser.slice(0, 2)), loser.full_name]


## A succession only goes sideways like this when the late head left children too
## young to hold anything, which is the sharpest way for a family to lose one.
static func _is_a_minority(org: Organization, previous: NotableIndividual, tick: int) -> bool:
	if org.kind != Organization.OrgKind.HOUSE or previous == null:
		return false
	for child_id in previous.children_ids:
		var child := GameState.get_person(child_id)
		if child != null and child.is_alive() and not child.is_adult(tick):
			return true
	return false


# --------------------------------------------------------- the families below

## Which way each household in service jumps. They back whoever they are closer
## to — by blood, by belief, and by whether the liege has been worth serving —
## and the choice is what their own standing then rests on.
static func _take_sides(org: Organization, winner: NotableIndividual,
		loser: NotableIndividual) -> Dictionary:
	var out := {}
	for house in Retainers.retainers_of(org.org_id):
		var for_winner := _affinity_to(house, winner) + house.loyalty * 0.4
		var for_loser := _affinity_to(house, loser)
		if is_equal_approx(for_winner, for_loser):
			continue
		out[house.org_id] = for_winner > for_loser
	return out


static func _affinity_to(house: Organization, claimant: NotableIndividual) -> float:
	var score := 0.0
	# Blood already shared is the plainest reason to prefer somebody.
	for member in GameState.house_members(house.org_id):
		if member.spouse_ids.has(claimant.person_id):
			score += 0.6
		if claimant.father_id != &"" and member.person_id == claimant.father_id:
			score += 0.4
	if house.ideology != null:
		var trait_bias := 0.0
		if claimant.has_tag(&"just"):
			trait_bias += 0.2
		if claimant.has_tag(&"martial"):
			trait_bias += house.ideology.get_axis(&"militarism_pacifism") * 0.3
		if claimant.has_tag(&"pious"):
			trait_bias += house.ideology.get_axis(&"secular_theocratic") * 0.3
		score += trait_bias
	# Derived rather than rolled, so the same world settles the same way twice.
	score += float(absi(hash(str(house.org_id, ":", claimant.person_id))) % 1000) / 3000.0
	return score


## Standing in service is not held, it is earned in the liege's quarrels — and
## lost in them. Favour is a continuous value like power and loyalty, so it moves
## here rather than through the record; what it is worth is read back as a rank.
const BACKING_REWARD := 0.55
const BACKING_PENALTY := 0.45


static func _settle_backers(org: Organization, fallout: Dictionary, tick: int) -> void:
	var backers: Dictionary = fallout.get("backers", {})
	for house_id in backers:
		var house := GameState.get_organization(house_id)
		if house == null or not house.is_active():
			continue
		if bool(backers[house_id]):
			house.favour += BACKING_REWARD
			house.loyalty = clampf(house.loyalty + 0.15, 0.0, 1.0)
		else:
			house.favour = maxf(0.0, house.favour - BACKING_PENALTY)
			house.loyalty = clampf(house.loyalty - 0.25, 0.0, 1.0)


## A synthetic rule describing "the losing claimant takes their followers and
## leaves". Authored rules cover pressures from the world; this one is internal
## to a contested succession, so it is built here rather than sitting in content.
static func _succession_schism_rule(org: Organization, base: TriggerRule) -> TriggerRule:
	var r := TriggerRule.new()
	r.rule_id = &"succession_breakaway"
	r.rule_type = TriggerRule.RuleType.SCHISM
	r.schism_kind = &"succession_dispute"
	r.applies_to_kind = org.kind
	r.inherited_member_fraction = Vector2(0.15, 0.4)
	r.ideology_drift_bias = {"tradition_reform": -0.2, "centralization": -0.25}
	r.branch_leadership_title = org.leadership_title
	r.chronicle_template = "{leader}は継承の裁定を認めず、{parent}を割って{branch}を立てた。"
	return r


static func _rule_for(org: Organization) -> TriggerRule:
	for rule in ContentRegistry.rules():
		if rule.rule_type != TriggerRule.RuleType.SUCCESSION:
			continue
		if rule.applies_to_kind != org.kind:
			continue
		if rule.applies_to_archetypes.is_empty() or rule.applies_to_archetypes.has(org.archetype_id):
			return rule
	return null


static func _previous_leader_id(org: Organization) -> StringName:
	# The seat is already cleared by the death, so the predecessor is whoever
	# most recently closed a tenure here.
	var best_tick := -1
	var best_id := &""
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		for t in p.role_history:
			if t.org_id == org.org_id and t.end_tick > best_tick:
				best_tick = t.end_tick
				best_id = p.person_id
	return best_id

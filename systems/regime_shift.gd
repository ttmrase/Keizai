class_name RegimeShift
extends RefCounted

## Why a regime falls, and what replaces it.
##
## Until now the country's ideology drifted but its institutions never did: the
## crown stayed a crown however strong the guilds got, and only the adjectives in
## front of it changed. This is the part that lets the machine itself be taken.
## What a regime rests on and who decides in it are discrete facts, and they
## change hands when somebody else is visibly holding the country up.
##
## Three things can hold a country up instead of its government: a bloc with the
## seats (see SocialTies), a trade strong enough to outweigh the throne, or a
## population angry enough that neither of those matters. Each wants a different
## constitution, and the strongest of them writes it.
##
## Legitimacy is the regime's side of that argument. It is not a dial anyone
## sets: it drains while somebody else is holding the country up and recovers
## while nobody is, which is why a regime can survive one strong guild for
## generations and then fall to the same guild in a bad decade.

## How far a challenger's hold must exceed the regime's standing before the
## settlement of the last upheaval stops holding.
const UPHEAVAL_THRESHOLD := 0.34
## Regimes are not overturned twice in a lifetime.
const COOLDOWN_TICKS := 400

## Seats a bloc needs before the chamber is a claim on the country.
const CHAMBER_PLURALITY := 0.40
## Unrest at which the street is a claimant in its own right.
const STREET_FLOOR := 0.45

const LEGITIMACY_DRIFT := 0.02
## Legitimacy a regime keeps when nobody at all is challenging it.
const LEGITIMACY_CEILING := 0.95
const LEGITIMACY_ELBOW := 0.95

## How hard the new order pulls the country's ideals toward its own.
const AXIS_SEIZURE := 0.55
## What a regime's standing is worth the morning after it is installed.
const FRESH_LEGITIMACY := 0.55


static func consider_all(tick: int) -> void:
	for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		_consider(polity, tick)


static func _consider(polity: Organization, tick: int) -> void:
	if polity.ideology == null:
		return

	var claimant := _claimant(polity)
	var hold: float = claimant.get("hold", 0.0)
	_erode_legitimacy(polity, hold)

	var last: int = int(polity.last_fired_tick.get(&"regime_shift", -999999))
	if tick - last < COOLDOWN_TICKS or claimant.is_empty():
		return

	# What is left of the regime's own standing is what it defends itself with,
	# and a country that no longer believes what it was founded on defends itself
	# with less.
	var drift := 0.0
	if polity.ideology_baseline != null:
		drift = polity.ideology.ideological_distance(polity.ideology_baseline)
	if hold - polity.legitimacy + drift < UPHEAVAL_THRESHOLD:
		return

	polity.last_fired_tick[&"regime_shift"] = tick
	_overturn(polity, claimant, tick)


## Legitimacy drains while somebody else is holding the country up and recovers
## while nobody is. Slowly either way — this is the reason a regime survives one
## strong decade and falls in the next one exactly like it.
static func _erode_legitimacy(polity: Organization, hold: float) -> void:
	var target := clampf(LEGITIMACY_ELBOW - hold, 0.05, LEGITIMACY_CEILING)
	polity.legitimacy = move_toward(polity.legitimacy, target, LEGITIMACY_DRIFT)


# ---------------------------------------------------------------- challengers

## Whoever is in a position to impose terms, on what grounds, and how firm their
## hold on the country is. Empty when the regime faces nobody who wants anything
## different from what it already is.
static func _claimant(polity: Organization) -> Dictionary:
	var best := {}
	var best_hold := 0.0

	for candidate in [_chamber_claim(polity), _trade_claim(polity), _street_claim(polity)]:
		if candidate.is_empty():
			continue
		if float(candidate["hold"]) > best_hold:
			best_hold = float(candidate["hold"])
			best = candidate
	return best


## The chamber. A bloc holding two seats in five and believing something other
## than the regime does has a claim it can press.
static func _chamber_claim(polity: Organization) -> Dictionary:
	var bloc := SocialTies.largest_bloc(polity)
	if bloc == null or polity.seat_total <= 0:
		return {}
	var share := float(polity.faction_seats.get(bloc.org_id, 0)) / float(polity.seat_total)
	if share < CHAMBER_PLURALITY or not _differs(polity, bloc):
		return {}
	return {"org": bloc, "ground": "議会", "hold": share}


## The purse and the trade. One organization against many is not a fair
## comparison, so a guild is measured as its whole estate against the throne:
## when the trades between them outweigh the crown, the crown is a formality.
static func _trade_claim(polity: Organization) -> Dictionary:
	var guilds := GameState.organizations_of_kind(Organization.OrgKind.GUILD)
	if guilds.is_empty():
		return {}
	var estate := 0.0
	var leader: Organization = null
	for g in guilds:
		estate += g.power_score
		if leader == null or g.power_score > leader.power_score:
			leader = g
	var hold := estate / maxf(1.0, estate + polity.power_score)
	if leader == null:
		return {}
	var basis := PoliticalSystemGenerator.legitimacy_for_archetype(
		leader.archetype_id, polity.ideology.legitimacy_basis)
	if basis == polity.ideology.legitimacy_basis:
		return {}
	return {"org": leader, "ground": "実力", "hold": hold, "basis": basis}


## The street. Enough anger and it does not matter who has the seats or the
## money — what follows answers to a crowd, and elects.
static func _street_claim(polity: Organization) -> Dictionary:
	var unrest := WorldStateQuery.get_value(&"org.governed.avg_unrest", polity)
	if unrest < STREET_FLOOR:
		return {}
	if polity.ideology.legitimacy_basis == PoliticalSystemAxes.LegitimacyBasis.ELECTED:
		return {}
	var voice := SocialTies.largest_bloc(polity)
	if voice == null:
		return {}
	return {
		"org": voice,
		"ground": "民衆",
		"hold": unrest,
		"basis": PoliticalSystemAxes.LegitimacyBasis.ELECTED,
		"structure": PoliticalSystemAxes.DecisionStructure.ASSEMBLY,
	}


static func _differs(polity: Organization, other: Organization) -> bool:
	if other.ideology == null:
		return false
	return other.ideology.legitimacy_basis != polity.ideology.legitimacy_basis \
		or other.ideology.decision_structure != polity.ideology.decision_structure


# ------------------------------------------------------------------ the fall

static func _overturn(polity: Organization, claimant: Dictionary, tick: int) -> void:
	var winner: Organization = claimant["org"]
	var basis: int = claimant.get("basis", -1)
	if basis < 0:
		basis = winner.ideology.legitimacy_basis if winner.ideology != null \
			else PoliticalSystemAxes.LegitimacyBasis.ELECTED
	var structure: int = claimant.get("structure", _structure_for(winner, claimant.get("ground", "")))

	var axis_shift := {}
	if winner.ideology != null:
		for a in PoliticalSystemAxes.AXIS_NAMES:
			axis_shift[String(a)] = winner.ideology.get_axis(a)

	# Blood keeps the throne only where the new order still runs on blood.
	var deposed := basis != PoliticalSystemAxes.LegitimacyBasis.HEREDITARY
	var ruler := GameState.get_person(polity.leader_person_id)

	HistoryLog.emit_event(
		HistoryEvent.EventType.POWER_TRANSFER,
		tick,
		_chronicle_text(polity, winner, claimant.get("ground", ""), ruler, deposed),
		{
			"regime_change": true,
			"legitimacy_basis": PoliticalSystemAxes.LEGITIMACY_NAMES[basis],
			"decision_structure": PoliticalSystemAxes.STRUCTURE_NAMES[structure],
			"axis_shift": axis_shift,
			"depose_ruler": deposed,
			"claimant_org_id": String(winner.org_id),
			"ground": claimant.get("ground", ""),
			"legitimacy_cost": 0.0,
		},
		polity.org_id,
		polity.leader_person_id,
		polity.origin_event_id)

	# A body owned by a family means a family has taken the state, and a family
	# that has taken the state settles its accounts: a rival stripped of its land
	# and lowered, its own most loyal servants raised in that rival's place.
	var patron := GameState.get_organization(winner.patron_house_id)
	if patron != null and patron.is_active():
		Retainers.reward_and_punish(patron, tick)


## How the winner will decide things. A guild that buys a country runs it the way
## it runs a guild hall; a faction brings its own habits.
static func _structure_for(winner: Organization, ground: String) -> int:
	if ground == "実力":
		return PoliticalSystemAxes.DecisionStructure.OLIGARCHIC_COUNCIL
	if winner.ideology != null:
		return winner.ideology.decision_structure
	return PoliticalSystemAxes.DecisionStructure.ASSEMBLY


static func _chronicle_text(polity: Organization, winner: Organization, ground: String,
		ruler: NotableIndividual, deposed: bool) -> String:
	var how: String = {
		"議会": "議場の多数を握った",
		"実力": "国の富と人を握った",
		"民衆": "怒れる民を背にした",
	}.get(ground, "力を得た")
	var fate := "%sは座を追われた。" % ruler.full_name if deposed and ruler != null \
		else "王座はかろうじて残された。"
	return "%sで政変が起きた。%s%sが国の形を書き換え、%s" \
		% [polity.display_name, how, winner.display_name, fate]


## Whether the regime is currently being outweighed, and by whom — for the
## dashboard, so the player can watch the pressure build rather than only read
## about the collapse afterwards.
static func standing_challenge(polity: Organization) -> Dictionary:
	return _claimant(polity)

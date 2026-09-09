class_name PolityFormEvaluator
extends RefCounted

## Reads the current form of government off the balance of power.
##
## This is what ties factions and political systems together into something the
## player can actually read: a faction is a body of opinion, a political system
## is the machinery, and the *form* — feudal kingdom, merchant republic,
## theocracy — is what you get when a particular opinion captures a particular
## machine. It is recomputed every power epoch, so a country can become
## something else without anyone declaring it.

const FALLBACK_FORM := &"kingdom"


## A country does not rename itself every time one guild's standing wobbles, so
## the form it already has counts for something. Without this the chronicle fills
## with a realm crossing back and forth between two neighbouring descriptions of
## the same situation.
const INCUMBENT_BONUS := 8


static func evaluate(polity: Organization) -> PolityForm:
	var best: PolityForm = null
	var best_priority := -99999
	for form in ContentRegistry.polity_forms():
		var priority: int = form.priority
		if form.form_id == polity.polity_form_id:
			priority += INCUMBENT_BONUS
		if priority <= best_priority:
			continue
		var holds := true
		for condition in form.conditions:
			if not RuleConditionEvaluator.holds(condition, polity):
				holds = false
				break
		if holds:
			best = form
			best_priority = priority
	if best == null:
		best = ContentRegistry.get_polity_form(FALLBACK_FORM)
	return best


## Applies the current form to every political system, renaming the offices it
## implies. A change of form is chronicled — it is one of the more consequential
## things that can happen without anybody intending it.
static func refresh_all(tick: int) -> void:
	for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		var form := evaluate(polity)
		if form == null:
			continue
		if polity.polity_form_id == form.form_id:
			polity.leadership_title = form.ruler_title
			continue

		var previous := ContentRegistry.get_polity_form(polity.polity_form_id)
		polity.polity_form_id = form.form_id
		polity.leadership_title = form.ruler_title

		# The founding of the world is not a change of form; only report a shift
		# from something into something else.
		if previous != null:
			HistoryLog.emit_event(
				HistoryEvent.EventType.IDEOLOGY_SHIFT,
				tick,
				"%sの統治のかたちが「%s」から「%s」へと移り変わった。"
					% [polity.display_name, previous.display_name, form.display_name],
				{"from_form": String(previous.form_id), "to_form": String(form.form_id)},
				polity.org_id,
				polity.leader_person_id,
				polity.origin_event_id)


## The title a house head carries when their house holds a region, under
## whichever form governs that region.
##
## Where the regime runs on pedigree the title is the family's own rank — a
## 公爵家 holds a duchy and is addressed as one, while the house next door with
## the same land is only a 男爵. Where it does not, everybody holding a region is
## whatever the form calls them: a mayor is a mayor however old the family is.
static func local_title_for(settlement_id: StringName) -> String:
	var settlement: SettlementState = GameState.world.settlements.get(settlement_id)
	if settlement == null:
		return "領主"
	var polity := GameState.get_organization(settlement.controlling_org_id)
	if polity == null:
		return "領主"
	var form := ContentRegistry.get_polity_form(polity.polity_form_id)
	if form == null:
		return "領主"
	if HouseRank.regard_in_realm(polity) >= RANK_TITLE_REGARD and settlement.ruling_house_id != &"":
		return HouseRank.title_of(settlement.ruling_house_id)
	return form.local_ruler_title


## How much a realm has to care about birth before it addresses its lords by
## their family's rank rather than by their office.
const RANK_TITLE_REGARD := 0.5


## A polity founded between one epoch and the next has not been read yet. It is
## still a country in the meantime, so answer with the fallback rather than with
## nothing — the UI should never show a realm with no form at all.
static func form_of(polity: Organization) -> PolityForm:
	if polity == null:
		return null
	var form := ContentRegistry.get_polity_form(polity.polity_form_id)
	return form if form != null else ContentRegistry.get_polity_form(FALLBACK_FORM)

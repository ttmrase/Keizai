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


static func evaluate(polity: Organization) -> PolityForm:
	var best: PolityForm = null
	for form in ContentRegistry.polity_forms():
		if best != null and form.priority <= best.priority:
			continue
		var holds := true
		for condition in form.conditions:
			if not RuleConditionEvaluator.holds(condition, polity):
				holds = false
				break
		if holds:
			best = form
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
static func local_title_for(settlement_id: StringName) -> String:
	var settlement: SettlementState = GameState.world.settlements.get(settlement_id)
	if settlement == null:
		return "領主"
	var polity := GameState.get_organization(settlement.controlling_org_id)
	if polity == null:
		return "領主"
	var form := ContentRegistry.get_polity_form(polity.polity_form_id)
	return form.local_ruler_title if form != null else "領主"


static func form_of(polity: Organization) -> PolityForm:
	if polity == null:
		return null
	return ContentRegistry.get_polity_form(polity.polity_form_id)

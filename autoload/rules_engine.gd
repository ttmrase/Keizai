extends Node

## Evaluates the authored pressure rules each tick and lets the society react.
##
## Nothing here encodes a specific institution. The rules under res://data/rules/
## say which world conditions matter and what the response is, so adding a new
## social pressure — or a whole new kind of institution the world can invent — is
## a content change. The engine only knows how to check conditions and hand off
## to a resolver.

func evaluate_tick(tick: int) -> void:
	_fill_empty_seats(tick)
	if tick % SimConfig.RULES_MIN_CHECK_INTERVAL != 0:
		return
	_evaluate_pressures(tick)


## An organization without a leader is broken, so successions resolve
## immediately rather than waiting for the rule cadence.
func _fill_empty_seats(tick: int) -> void:
	# Houses first: a crown follows whoever now heads the house that held it.
	for kind in [Organization.OrgKind.HOUSE, Organization.OrgKind.POLITICAL_SYSTEM,
			Organization.OrgKind.GUILD, Organization.OrgKind.FACTION,
			Organization.OrgKind.RELIGION]:
		for org in GameState.organizations_of_kind(kind):
			if _is_leaderless_by_nature(org):
				continue
			if org.leader_person_id == &"":
				SuccessionResolver.resolve(org, tick)
			else:
				var leader := GameState.get_person(org.leader_person_id)
				if leader == null or not leader.is_alive():
					org.leader_person_id = &""
					SuccessionResolver.resolve(org, tick)


## Some bodies have no seat. The oldest faith in the world has no priesthood —
## it is what people believe before anyone organizes it — and electing it a head
## every tick would make it the wrong thing entirely.
func _is_leaderless_by_nature(org: Organization) -> bool:
	var profile := ContentRegistry.get_power_profile(org.archetype_id)
	return profile != null and profile.leaderless


func _evaluate_pressures(tick: int) -> void:
	var rng := RngService.stream(&"rules")
	# Snapshot: firing a rule creates organizations, and a newborn branch should
	# not be evaluated in the same pass that created it.
	var orgs := GameState.active_organizations()
	for org in orgs:
		for rule in ContentRegistry.rules():
			if not _applies(rule, org):
				continue
			if tick - int(org.last_fired_tick.get(rule.rule_id, -999999)) < rule.cooldown_ticks:
				continue
			if not RuleConditionEvaluator.all_hold(rule, org):
				continue
			# A body led by somebody out of a house of scholars argues its way
			# apart far more readily than one led out of a house of courtiers.
			if rng.randf() > rule.chance_per_tick * HouseCharacter.schism_affinity(org):
				continue
			if _fire(rule, org, tick):
				org.last_fired_tick[rule.rule_id] = tick
				break   # one upheaval per organization per pass


func _applies(rule: TriggerRule, org: Organization) -> bool:
	if rule.rule_type == TriggerRule.RuleType.SUCCESSION:
		return false          # handled by _fill_empty_seats
	if rule.applies_to_kind != org.kind:
		return false
	if not rule.applies_to_archetypes.is_empty() \
			and not rule.applies_to_archetypes.has(org.archetype_id):
		return false
	if rule.rule_type == TriggerRule.RuleType.SCHISM:
		if org.member_count < rule.min_parent_members:
			return false
		if rule.max_instances_of_archetype > 0 and rule.branch_archetype_id != &"":
			var existing := WorldStateQuery.get_value(
				StringName("count.archetype." + String(rule.branch_archetype_id)))
			if existing >= rule.max_instances_of_archetype:
				return false
	return true


func _fire(rule: TriggerRule, org: Organization, tick: int) -> bool:
	match rule.rule_type:
		TriggerRule.RuleType.SCHISM:
			return SchismResolver.create_branch(org, rule, tick) != null
		TriggerRule.RuleType.POWER_SHIFT:
			return _shift_power(rule, org, tick)
		TriggerRule.RuleType.CONFLICT:
			return _declare_conflict(rule, org, tick)
	return false


## A weakened ruler loses a settlement to whoever is strongest nearby. The loser
## also takes a legitimacy hit, which is often what triggers the next schism —
## defeat needs no special-case code of its own.
func _shift_power(rule: TriggerRule, org: Organization, tick: int) -> bool:
	if org.governs_settlement_ids.is_empty():
		return false
	var rival := _strongest_rival(org)
	if rival == null or rival.power_score <= org.power_score:
		return false

	var settlement_id: StringName = org.governs_settlement_ids[
		RngService.stream(&"rules").randi_range(0, org.governs_settlement_ids.size() - 1)]
	var s: SettlementState = GameState.world.settlements.get(settlement_id)
	var place := s.display_name if s != null else "ある土地"
	var reason := RuleConditionEvaluator.describe(rule, org)

	var text := rule.chronicle_template
	if text.is_empty():
		text = "{reason}により、{place}は{from}の手を離れ{to}に従った。"
	text = text.replace("{place}", place).replace("{from}", org.display_name) \
		.replace("{to}", rival.display_name).replace("{reason}", reason)

	HistoryLog.emit_event(
		HistoryEvent.EventType.POWER_TRANSFER,
		tick,
		text,
		{
			"from_org_id": String(org.org_id),
			"settlement_id": String(settlement_id),
			"legitimacy_cost": 0.15,
			"rule_id": String(rule.rule_id),
		},
		rival.org_id,
		rival.leader_person_id,
		org.origin_event_id)
	return true


func _declare_conflict(rule: TriggerRule, org: Organization, tick: int) -> bool:
	var rival := _strongest_rival(org)
	if rival == null:
		return false
	var reason := RuleConditionEvaluator.describe(rule, org)
	var text := rule.chronicle_template
	if text.is_empty():
		text = "{reason}をめぐり、{a}と{b}が公然と対立した。"
	text = text.replace("{a}", org.display_name).replace("{b}", rival.display_name) \
		.replace("{reason}", reason)

	# Resolved immediately by relative strength; the interesting consequence is
	# the legitimacy damage, not a tactical outcome.
	var org_strength: float = org.power_score * (1.0 + _militarism(org) * 0.5)
	var rival_strength: float = rival.power_score * (1.0 + _militarism(rival) * 0.5)
	var loser := org if org_strength < rival_strength else rival

	HistoryLog.emit_event(
		HistoryEvent.EventType.CONFLICT_RESOLVED,
		tick,
		"%s %sが退いた。" % [text, loser.display_name],
		{"loser_org_id": String(loser.org_id), "rule_id": String(rule.rule_id)},
		org.org_id, &"", org.origin_event_id)

	loser.legitimacy = clampf(loser.legitimacy - 0.2, 0.0, 1.0)
	loser.member_count = maxi(5, int(loser.member_count * 0.85))
	if loser.ideology != null:
		loser.ideology.add_tag(&"war_torn")
	return true


func _strongest_rival(org: Organization) -> Organization:
	var best: Organization = null
	for other in GameState.active_organizations():
		if other.org_id == org.org_id:
			continue
		if best == null or other.power_score > best.power_score:
			best = other
	return best


func _militarism(org: Organization) -> float:
	if org.ideology == null:
		return 0.0
	return maxf(0.0, org.ideology.get_axis(&"militarism_pacifism"))

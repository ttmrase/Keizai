class_name PoliticalSystemGenerator
extends RefCounted

## Builds ideologies out of composable axes and names the result, rather than
## picking a regime from a fixed list. The same code names guilds, houses,
## factions and political systems — only the word bank differs by kind.
##
## Axes drift each epoch toward whatever the world currently rewards, so a
## regime founded as a traditionalist hereditary autocracy can become something
## its founders would not recognise, which is exactly what makes a schism
## meaningful when the old guard refuses to follow.

const _AXIS_LABELS := {
	&"centralization": ["地方分権", "中央集権"],
	&"tradition_reform": ["伝統主義", "改革主義"],
	&"militarism_pacifism": ["平和主義", "軍国主義"],
	&"isolationism_commerce": ["鎖国", "通商主義"],
	&"secular_theocratic": ["世俗主義", "神権主義"],
}

const _AXIS_ADJECTIVES := {
	&"centralization": ["分権的な", "中央集権的な"],
	&"tradition_reform": ["守旧的な", "革新的な"],
	&"militarism_pacifism": ["穏健な", "尚武の"],
	&"isolationism_commerce": ["閉ざされた", "開かれた"],
	&"secular_theocratic": ["世俗の", "神聖な"],
}

const _LEGITIMACY_JP := {
	PoliticalSystemAxes.LegitimacyBasis.HEREDITARY: "世襲",
	PoliticalSystemAxes.LegitimacyBasis.ELECTED: "選挙",
	PoliticalSystemAxes.LegitimacyBasis.MERITOCRATIC: "実力主義",
	PoliticalSystemAxes.LegitimacyBasis.THEOCRATIC: "神権",
	PoliticalSystemAxes.LegitimacyBasis.MILITARY_STRENGTH: "軍事",
	PoliticalSystemAxes.LegitimacyBasis.WEALTH_BASED: "金権",
}

const _STRUCTURE_JP := {
	PoliticalSystemAxes.DecisionStructure.AUTOCRATIC: "専制",
	PoliticalSystemAxes.DecisionStructure.OLIGARCHIC_COUNCIL: "評議制",
	PoliticalSystemAxes.DecisionStructure.ASSEMBLY: "議会制",
}

## An axis must be at least this strong to show up in a name or description.
const STRONG_AXIS := 0.35


static func generate_root_axes() -> PoliticalSystemAxes:
	var rng := RngService.stream(&"ideology")
	var axes := PoliticalSystemAxes.new()
	axes.legitimacy_basis = PoliticalSystemAxes.LegitimacyBasis.HEREDITARY
	axes.decision_structure = PoliticalSystemAxes.DecisionStructure.AUTOCRATIC
	# A world starts near the middle, so where it ends up is the world's doing.
	for a in PoliticalSystemAxes.AXIS_NAMES:
		axes.set_axis(a, rng.randf_range(-0.25, 0.25))
	axes.set_axis(&"tradition_reform", rng.randf_range(-0.45, -0.1))
	return axes


## Ideology for a branch: a deep copy of the parent's, pushed by whatever the
## split was about, then jittered so no two schisms feel identical.
static func generate_branch_axes(parent: Organization, drift_bias: Dictionary) -> PoliticalSystemAxes:
	var rng := RngService.stream(&"ideology")
	var axes: PoliticalSystemAxes = parent.ideology.clone() if parent.ideology != null \
		else generate_root_axes()
	for key in drift_bias:
		var axis := StringName(key)
		axes.set_axis(axis, axes.get_axis(axis) + float(drift_bias[key]))
	for a in PoliticalSystemAxes.AXIS_NAMES:
		axes.set_axis(a, axes.get_axis(a) + rng.randf_range(-0.12, 0.12))
	return axes


## Pulls every organization's ideology toward what the current world rewards.
## Called on the drift epoch, not every tick — ideology should move like weather,
## not like a dial.
static func drift_all(tick: int) -> void:
	var world: WorldState = GameState.world
	var threat := world.global_monster_threat_level
	var scarcity := 1.0 - clampf(world.global_harvest_modifier, 0.0, 1.0)
	var unrest := world.global_unrest
	var trade := clampf(world.global_wealth / 4000.0, 0.0, 1.0)
	var faith := clampf(world.recent_disaster_pressure / 6.0, 0.0, 1.0)

	for org in GameState.active_organizations():
		if org.ideology == null:
			continue
		var rate := 0.02
		# Danger pushes societies toward arms and central command; peace and
		# trade pull the other way.
		org.ideology.nudge_axis(&"militarism_pacifism", threat * 2.0 - 0.6, rate)
		org.ideology.nudge_axis(&"centralization", (threat + unrest) - 0.7, rate)
		org.ideology.nudge_axis(&"isolationism_commerce", trade * 2.0 - 0.8, rate)
		org.ideology.nudge_axis(&"secular_theocratic", faith * 2.0 - 0.7, rate)
		# Hardship discredits the old way of doing things.
		org.ideology.nudge_axis(&"tradition_reform", (scarcity + unrest) - 0.75, rate * 0.8)


## Chooses a legitimacy basis that fits an archetype's character. Used when a
## specialization branch invents a new kind of institution for itself.
static func legitimacy_for_archetype(archetype_id: StringName,
		fallback: PoliticalSystemAxes.LegitimacyBasis) -> PoliticalSystemAxes.LegitimacyBasis:
	match archetype_id:
		&"temple_faction":
			return PoliticalSystemAxes.LegitimacyBasis.THEOCRATIC
		&"monster_hunters_guild":
			return PoliticalSystemAxes.LegitimacyBasis.MILITARY_STRENGTH
		&"merchants_guild":
			return PoliticalSystemAxes.LegitimacyBasis.WEALTH_BASED
		&"artisans_guild", &"mage_guild":
			return PoliticalSystemAxes.LegitimacyBasis.MERITOCRATIC
		&"farmers_faction":
			return PoliticalSystemAxes.LegitimacyBasis.ELECTED
	return fallback


# ------------------------------------------------------------------- naming

static func name_and_describe(org: Organization, is_branch: bool = false,
		parent: Organization = null) -> Dictionary:
	var template := _template_for(org)
	var tokens := _build_tokens(org, template)
	tokens["parent"] = parent.display_name if parent != null else ""
	var pattern := template.name_pattern if template != null else "{legitimacy}{structure}"
	if is_branch and template != null and not template.branch_name_pattern.is_empty():
		pattern = template.branch_name_pattern
	var desc_pattern := template.description_pattern if template != null else "イデオロギー:{ideology}"
	if is_branch and template != null and not template.branch_description_pattern.is_empty():
		desc_pattern = template.branch_description_pattern
	return {
		"display_name": _ensure_unique(_resolve(pattern, tokens), org, tokens),
		"description": _resolve(desc_pattern, tokens),
	}


## Two regimes assembled from the same axes would otherwise carry the same name,
## which makes a lineage tree unreadable. Distinguish by seat first, since that
## is how people actually tell two rival courts apart, then by ruling family.
static func _ensure_unique(name: String, org: Organization, tokens: Dictionary) -> String:
	if name.is_empty():
		name = "無名の集団"
	if not _name_taken(name, org):
		return name
	var by_place := "%sの%s" % [tokens.get("place", ""), name]
	if tokens.get("place", "") != "" and not _name_taken(by_place, org):
		return by_place
	var leader := GameState.get_person(org.leader_person_id)
	if leader != null and leader.family_name != "":
		var by_family := "%s系%s" % [leader.family_name, name]
		if not _name_taken(by_family, org):
			return by_family
	var rng := RngService.stream(&"naming")
	return "%s(%s)" % [name, NameGenerator.family_stem()]


static func _name_taken(name: String, org: Organization) -> bool:
	for other in GameState.organizations.values():
		if other.org_id != org.org_id and other.display_name == name:
			return true
	return false


static func _template_for(org: Organization) -> NameTemplate:
	var generic: NameTemplate = null
	for t in ContentRegistry.name_templates():
		if not t.matches(org.kind, org.archetype_id):
			continue
		if not t.archetype_filter.is_empty():
			return t          # archetype-specific wins outright
		generic = t
	return generic


static func _build_tokens(org: Organization, template: NameTemplate) -> Dictionary:
	var rng := RngService.stream(&"naming")
	var axes: PoliticalSystemAxes = org.ideology
	var tokens := {
		"legitimacy": _LEGITIMACY_JP.get(axes.legitimacy_basis, "") if axes != null else "",
		"structure": _STRUCTURE_JP.get(axes.decision_structure, "") if axes != null else "",
		"adjective": _adjective_for(axes),
		"ideology": ideology_summary(axes),
		"noun": _archetype_noun(org, rng),
		"founder": _founder_given_name(org),
		"place": _seat_name(org),
		"stem": NameGenerator.family_stem(),
	}
	if template != null:
		for slot in template.word_bank:
			var options: Array = template.word_bank[slot]
			if options is Array and not options.is_empty():
				tokens[String(slot)] = options[rng.randi_range(0, options.size() - 1)]
	return tokens


static func _resolve(pattern: String, tokens: Dictionary) -> String:
	var out := pattern
	for key in tokens:
		out = out.replace("{%s}" % key, str(tokens[key]))
	# Any slot with no value collapses rather than leaving braces on screen.
	while out.contains("{"):
		var start := out.find("{")
		var end := out.find("}", start)
		if end < 0:
			break
		out = out.substr(0, start) + out.substr(end + 1)
	return out.strip_edges()


## "軍国主義・鎖国" — only the axes actually strong enough to characterize it.
static func ideology_summary(axes: PoliticalSystemAxes) -> String:
	if axes == null:
		return "中庸"
	var parts: Array[String] = []
	for a in PoliticalSystemAxes.AXIS_NAMES:
		var v := axes.get_axis(a)
		if absf(v) < STRONG_AXIS:
			continue
		parts.append(_AXIS_LABELS[a][1] if v > 0.0 else _AXIS_LABELS[a][0])
	if parts.is_empty():
		return "中庸"
	return "・".join(parts)


static func _adjective_for(axes: PoliticalSystemAxes) -> String:
	if axes == null:
		return ""
	var best_axis := &""
	var best_value := STRONG_AXIS
	for a in PoliticalSystemAxes.AXIS_NAMES:
		var v: float = absf(axes.get_axis(a))
		if v > best_value:
			best_value = v
			best_axis = a
	if best_axis == &"":
		return ""
	return _AXIS_ADJECTIVES[best_axis][1] if axes.get_axis(best_axis) > 0.0 \
		else _AXIS_ADJECTIVES[best_axis][0]


static func _archetype_noun(org: Organization, rng: RandomNumberGenerator) -> String:
	var profile := ContentRegistry.get_power_profile(org.archetype_id)
	if profile != null and not profile.noun_bank.is_empty():
		return profile.noun_bank[rng.randi_range(0, profile.noun_bank.size() - 1)]
	match org.kind:
		Organization.OrgKind.GUILD:
			return "組合"
		Organization.OrgKind.HOUSE:
			return "家"
		Organization.OrgKind.FACTION:
			return "派"
	return "体制"


static func _founder_given_name(org: Organization) -> String:
	var leader := GameState.get_person(org.leader_person_id)
	if leader == null:
		return ""
	var parts := leader.full_name.split("・")
	return parts[parts.size() - 1]


static func _seat_name(org: Organization) -> String:
	var seat_id := org.dynasty_seat_settlement_id
	if seat_id == &"" and not org.governs_settlement_ids.is_empty():
		seat_id = org.governs_settlement_ids[0]
	var s: SettlementState = GameState.world.settlements.get(seat_id)
	return s.display_name if s != null else "辺境"

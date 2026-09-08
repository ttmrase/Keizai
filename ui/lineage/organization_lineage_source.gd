class_name OrganizationLineageSource
extends LineageSource

## The institution tree: how every guild, house, faction and regime descends from
## the four the world began with.

func roots() -> Array[StringName]:
	var out: Array[StringName] = []
	for kind in [Organization.OrgKind.POLITICAL_SYSTEM, Organization.OrgKind.HOUSE,
			Organization.OrgKind.GUILD, Organization.OrgKind.FACTION]:
		var root := GameState.root_of_kind(kind)
		if root != null:
			out.append(root.org_id)
	return out


func children(id: StringName) -> Array[StringName]:
	var org := GameState.get_organization(id)
	if org == null:
		return []
	var out: Array[StringName] = []
	for child_id in org.child_org_ids:
		if GameState.get_organization(child_id) != null:
			out.append(child_id)
	return out


func parents(id: StringName) -> Array[StringName]:
	var org := GameState.get_organization(id)
	if org == null or org.parent_org_id == &"":
		return []
	return [org.parent_org_id]


func label(id: StringName) -> String:
	var org := GameState.get_organization(id)
	return org.display_name if org != null else String(id)


func sublabel(id: StringName) -> String:
	var org := GameState.get_organization(id)
	if org == null:
		return ""
	if not org.is_active():
		return "%s・断絶" % Palette.kind_label(org.kind)
	return "%s・%d名・力%d" % [Palette.kind_label(org.kind), org.member_count, int(org.power_score)]


func colour(id: StringName) -> Color:
	var org := GameState.get_organization(id)
	return Palette.for_kind(org.kind) if org != null else Palette.TEXT_MUTED


func is_faded(id: StringName) -> bool:
	var org := GameState.get_organization(id)
	return org != null and not org.is_active()


func exists(id: StringName) -> bool:
	return GameState.get_organization(id) != null


func detail(id: StringName) -> String:
	var org := GameState.get_organization(id)
	if org == null:
		return ""
	var leader := GameState.get_current_leader(id)
	var parent := GameState.get_organization(org.parent_org_id)
	var root := GenealogyValidator.root_ancestor(id)

	var lines: Array[String] = []
	lines.append("[color=#9a9080]%s[/color]  %s" % [Palette.kind_label(org.kind), org.description])
	lines.append("[color=#9a9080]指導者[/color]  %s"
		% (leader.full_name if leader != null else "不在"))
	lines.append("[color=#9a9080]興り[/color]  %d年%s" % [
		int(org.founding_tick / SimConfig.TICKS_PER_YEAR),
		"" if parent == null else "（%sより分派）" % parent.display_name])
	if not org.is_active():
		lines.append("[color=#c85a4a]断絶[/color]  %d年"
			% int(org.dissolved_tick / SimConfig.TICKS_PER_YEAR))
	if root != null:
		lines.append("[color=#9a9080]源流[/color]  %s（%d代前）" % [root.display_name, org.branch_depth])
	if org.ideology != null:
		lines.append("[color=#9a9080]思想[/color]  %s"
			% PoliticalSystemGenerator.ideology_summary(org.ideology))

	if org.kind == Organization.OrgKind.POLITICAL_SYSTEM:
		var form := PolityFormEvaluator.form_of(org)
		if form != null:
			lines.append("[color=#9a9080]統治のかたち[/color]  %s — %s"
				% [form.display_name, form.description])

	if org.kind == Organization.OrgKind.HOUSE:
		if not org.held_settlement_ids.is_empty():
			var places: Array[String] = []
			for settlement_id in org.held_settlement_ids:
				var s: SettlementState = GameState.world.settlements.get(settlement_id)
				if s != null:
					places.append(s.display_name)
			if not places.is_empty():
				lines.append("[color=#9a9080]所領[/color]  %s" % "、".join(places))
		var standing := _relations_text(org)
		if not standing.is_empty():
			lines.append("[color=#9a9080]他家との関係[/color]  %s" % standing)

	return "\n".join(lines)


## Who this house gets on with, and who it does not. Only ties strong enough to
## have a name are worth listing.
func _relations_text(house: Organization) -> String:
	var warm: Array[String] = []
	var cold: Array[String] = []
	for other_id in house.house_relations:
		var other := GameState.get_organization(other_id)
		if other == null or not other.is_active():
			continue
		var value: float = house.house_relations[other_id]
		if value > 0.2:
			warm.append("%s（%s）" % [other.display_name, HouseRelations.describe(value)])
		elif value < -0.2:
			cold.append("%s（%s）" % [other.display_name, HouseRelations.describe(value)])
	var parts: Array[String] = []
	if not warm.is_empty():
		parts.append("[color=#7ab87a]%s[/color]" % "、".join(warm))
	if not cold.is_empty():
		parts.append("[color=#c85a4a]%s[/color]" % "、".join(cold))
	return "　".join(parts)


func search(query: String) -> Array[StringName]:
	var out: Array[StringName] = []
	var needle := query.strip_edges()
	if needle.is_empty():
		return out
	for org in GameState.organizations.values():
		if org.display_name.contains(needle):
			out.append(org.org_id)
	return out

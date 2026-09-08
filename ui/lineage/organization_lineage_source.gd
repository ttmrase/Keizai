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
	return "\n".join(lines)


func search(query: String) -> Array[StringName]:
	var out: Array[StringName] = []
	var needle := query.strip_edges()
	if needle.is_empty():
		return out
	for org in GameState.organizations.values():
		if org.display_name.contains(needle):
			out.append(org.org_id)
	return out

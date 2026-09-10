class_name OrganizationLineageSource
extends LineageSource

## How every institution descends from the one its kind began with.
##
## Which kinds are drawn is set by whoever is using it, because the families and
## everything else do not belong on the same screen. Eight houses with three
## retainer families each, branching for four centuries, is most of the tree and
## crowds the guilds, factions and faiths down to a corner of it — so the view
## keeps two of these: one rooted at the institutions, one rooted at the houses.

## The kinds this instance draws, rooted at the first of each.
var root_kinds: Array[int] = [
	Organization.OrgKind.POLITICAL_SYSTEM,
	Organization.OrgKind.GUILD,
	Organization.OrgKind.FACTION,
	Organization.OrgKind.RELIGION,
]


func roots() -> Array[StringName]:
	var out: Array[StringName] = []
	for kind in root_kinds:
		var root := GameState.root_of_kind(kind)
		if root != null:
			out.append(root.org_id)
	return out


## Three retainer families under each of eight houses is most of the tree and
## almost none of the interest: they hold nothing, and the tree they crowd out is
## the one showing where the guilds, factions and faiths came from. Off by
## default, one tap away, and a retainer house that rises to the nobility appears
## in the ordinary view the moment it does.
var include_retainers := false


func children(id: StringName) -> Array[StringName]:
	var org := GameState.get_organization(id)
	if org == null:
		return []
	var out: Array[StringName] = []
	for child_id in org.child_org_ids:
		var child := GameState.get_organization(child_id)
		if child == null:
			continue
		if not include_retainers and child.standing == Organization.Standing.RETAINER:
			continue
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
	var why := _why_it_branched(org)
	if not why.is_empty():
		lines.append(why)
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
		lines.append("[color=#9a9080]家格[/color]  %s・%s%s" % [
			org.standing_label(),
			HouseRank.tier_name(org.rank_tier) if org.is_noble() else "位なし",
			"　%s" % HouseCharacter.label(org.character_id) if org.character_id != &"" else ""])
		if org.standing == Organization.Standing.RETAINER:
			var liege := GameState.get_organization(org.liege_house_id)
			lines.append("[color=#9a9080]仕える先[/color]  %s（%s）" % [
				liege.display_name if liege != null else "なし",
				Retainers.describe_loyalty(org.loyalty)])
		else:
			var served := Retainers.retainers_of(org.org_id)
			if not served.is_empty():
				var names: Array[String] = []
				for r in served:
					names.append("%s（%s）" % [r.display_name, Retainers.describe_loyalty(r.loyalty)])
				lines.append("[color=#9a9080]側近家[/color]  %s" % "、".join(names))
		var faith := GameState.get_organization(org.faith_id)
		if faith != null:
			lines.append("[color=#9a9080]信仰[/color]  %s" % faith.display_name)
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

	var roll := _leader_roll_text(org)
	if not roll.is_empty():
		lines.append("[color=#9a9080]歴代の%s[/color]\n%s" % [org.leadership_title, roll])

	return "\n".join(lines)


## Why this body exists at all, read back off the event that created it.
##
## Nothing extra is stored for this: the schism that founded a branch already
## records what kind of quarrel it was and the sentence the chronicle printed at
## the time. A family looking at its own cadet branches should be able to see
## which one left over an unfit heir and which one over a marriage.
func _why_it_branched(org: Organization) -> String:
	if org.origin_event_id == &"":
		return ""
	var origin := HistoryLog.find_event(org.origin_event_id)
	if origin == null or origin.event_type != HistoryEvent.EventType.SCHISM:
		return ""
	var kind := StringName(origin.payload.get("schism_kind", ""))
	var lines: Array[String] = ["[color=#9a9080]分かれた理由[/color]  %s"
		% HousePartition.reason_label(kind)]
	var reason: String = origin.payload.get("reason", "")
	if not reason.is_empty():
		lines[0] += "（%s）" % reason
	if not origin.description.is_empty():
		lines.append("[color=#6a6357]%s[/color]" % origin.description)
	return "\n".join(lines)


## Everyone who has held this seat, most recent first. Nothing is stored for
## this — the tenures already sit on the people, and reading them back is how a
## body gets a memory of who has run it.
const ROLL_LIMIT := 12


func _leader_roll_text(org: Organization) -> String:
	var roll := GameState.leader_roll(org.org_id)
	if roll.size() < 2:
		return ""
	var lines: Array[String] = []
	for i in range(roll.size() - 1, maxi(-1, roll.size() - 1 - ROLL_LIMIT), -1):
		var entry: Dictionary = roll[i]
		var t: RoleTenure = entry["tenure"]
		var person: NotableIndividual = entry["person"]
		lines.append("　%d年〜%s　%s" % [
			int(t.start_tick / SimConfig.TICKS_PER_YEAR),
			"現在" if t.is_current() else "%d年" % int(t.end_tick / SimConfig.TICKS_PER_YEAR),
			person.full_name])
	if roll.size() > ROLL_LIMIT:
		lines.append("　…ほか%d名" % (roll.size() - ROLL_LIMIT))
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
		# Only what this view is drawing: finding a house from the institution
		# screen would jump to a node that is not on it.
		if not root_kinds.has(org.kind):
			continue
		if org.display_name.contains(needle):
			out.append(org.org_id)
	return out

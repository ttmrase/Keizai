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


## When set, only the families of this 氏 are drawn, hanging from the house it
## is named for.
var uji_filter: StringName = &""


func roots() -> Array[StringName]:
	var out: Array[StringName] = []
	if uji_filter != &"" and GameState.get_organization(uji_filter) != null:
		out.append(uji_filter)
		return out
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
		if uji_filter != &"":
			if child.uji_id != uji_filter:
				continue
		elif not include_retainers and child.standing == Organization.Standing.RETAINER:
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


## A family's 氏, small, before its own name — unless it is the house the 氏
## is named for, whose name already says it.
func overline(id: StringName) -> String:
	var org := GameState.get_organization(id)
	if org == null or org.kind != Organization.OrgKind.HOUSE or HouseNaming.founded_uji(org):
		return ""
	return HouseNaming.uji_label(org.uji_id)


func sublabel(id: StringName) -> String:
	var org := GameState.get_organization(id)
	if org == null:
		return ""
	if not org.is_active():
		return "%s・断絶" % Palette.kind_label(org.kind)
	if org.kind == Organization.OrgKind.HOUSE:
		var seat := ""
		var held := Offices.held_by(org.org_id)
		if not held.is_empty():
			seat = "・" + Offices.label_of(held[0]["key"], held[0]["polity"])
		return "%s%s・%d名・力%d" % [HouseRank.title_of_house(org), seat, org.member_count,
			int(org.power_score)]
	return "%s・%d名・力%d" % [Palette.kind_label(org.kind), org.member_count, int(org.power_score)]


func colour(id: StringName) -> Color:
	var org := GameState.get_organization(id)
	return Heraldry.of_org(org) if org != null else Palette.TEXT_MUTED


func is_faded(id: StringName) -> bool:
	var org := GameState.get_organization(id)
	return org != null and not org.is_active()


## A family is drawn with its arms, so kin read as kin by the device they share.
func crest(id: StringName) -> StringName:
	var org := GameState.get_organization(id)
	return id if org != null and org.kind == Organization.OrgKind.HOUSE else &""


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
		"（建国の家）" if HouseNaming.founded_uji(org) else
			("" if parent == null else "（%sより分派）" % parent.formal_name())])
	var why := _why_it_branched(org)
	if not why.is_empty():
		lines.append(why)
	if not org.is_active():
		lines.append("[color=#c85a4a]断絶[/color]  %d年"
			% int(org.dissolved_tick / SimConfig.TICKS_PER_YEAR))
	# A family's origin is its 氏, shown below; the root of the house tree is
	# only the first family in it and says nothing about this one.
	if root != null and org.kind != Organization.OrgKind.HOUSE:
		lines.append("[color=#9a9080]源流[/color]  %s（%d代前）" % [root.formal_name(), org.branch_depth])
	if org.ideology != null:
		lines.append("[color=#9a9080]思想[/color]  %s"
			% PoliticalSystemGenerator.ideology_summary(org.ideology))

	if org.kind == Organization.OrgKind.POLITICAL_SYSTEM:
		var form := PolityFormEvaluator.form_of(org)
		if form != null:
			lines.append("[color=#9a9080]統治のかたち[/color]  %s — %s"
				% [form.display_name, form.description])

	if org.kind == Organization.OrgKind.HOUSE:
		var uji_text := uji_lines(org)
		if not uji_text.is_empty():
			lines.append(uji_text)
		var grounds_text := grounds_lines(org)
		if not grounds_text.is_empty():
			lines.append(grounds_text)
		var grudge_text := grudge_lines(org)
		if not grudge_text.is_empty():
			lines.append(grudge_text)
		lines.append("[color=#9a9080]家格[/color]  %s・%s%s" % [
			org.standing_label(),
			HouseRank.tier_name(org.rank_tier) if org.is_noble() else "位なし",
			"　%s" % HouseCharacter.label(org.character_id) if org.character_id != &"" else ""])
		if org.standing == Organization.Standing.RETAINER:
			var liege := GameState.get_organization(org.liege_house_id)
			lines.append("[color=#9a9080]仕える先[/color]  %s（%s）" % [
				liege.formal_name() if liege != null else "なし",
				Retainers.describe_loyalty(org.loyalty)])
		else:
			var served := Retainers.retainers_of(org.org_id)
			if not served.is_empty():
				var names: Array[String] = []
				for r in served:
					names.append("%s（%s）" % [r.formal_name(), Retainers.describe_loyalty(r.loyalty)])
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
		var offices := GameState.offices_of_house(org.org_id)
		if not offices.is_empty():
			var seats: Array[String] = []
			for seat in offices:
				var held: Organization = seat["org"]
				var holder: NotableIndividual = seat["person"]
				seats.append("%s%s（%s）" % [held.formal_name(), seat["title"], holder.given_name])
			lines.append("[color=#9a9080]現任の役[/color]  %s" % "、".join(seats))
		var honour := Honours.honour_label(org)
		if not honour.is_empty():
			lines.append("[color=#9a9080]王家との間柄[/color]  %s" % honour)
		var standing := _relations_text(org)
		if not standing.is_empty():
			lines.append("[color=#9a9080]他家との関係[/color]  %s" % standing)

	var roll := _leader_roll_text(org)
	if not roll.is_empty():
		lines.append("[color=#9a9080]歴代の%s[/color]\n%s" % [org.leadership_title, roll])

	return "\n".join(lines)


## What a family's rank rests on, ground by ground, with the total: the reason
## it is what it is, readable at a glance.
static func grounds_lines(house: Organization) -> String:
	if house == null or house.standing == Organization.Standing.COMMONER:
		return ""
	var grounds := HouseRank.grounds_of(house)
	if grounds.is_empty():
		return ""
	var parts: Array[String] = []
	for g in grounds:
		var value := float(g["value"])
		var colour := "c85a4a" if value < 0.0 else ("d4a748" if value >= 0.4 else "e8e0d0")
		parts.append("[color=#%s]%s %s%.2f[/color]" % [colour, g["label"],
			"+" if value >= 0.0 else "", value])
	var text := "[color=#9a9080]家格の根拠[/color]  計%.2f\n　　%s" % [
		HouseRank.standing_from(grounds), "、".join(parts)]
	var held := Offices.held_by(house.org_id)
	if not held.is_empty():
		var seats: Array[String] = []
		for entry in held:
			seats.append("%s（%s）" % [Offices.label_of(entry["key"], entry["polity"]),
				entry["person"].given_name if entry["person"] != null else "?"])
		text = "[color=#9a9080]要職[/color]  %s\n%s" % ["、".join(seats), text]
	return text


## 遺恨: whom a family resents and who resents it — why, and since when — and
## how its quarrels at court have gone.
static func grudge_lines(house: Organization) -> String:
	if house == null or house.standing == Organization.Standing.COMMONER:
		return ""
	var out: Array[String] = []
	# One line per family: the strongest grudge between them, and how many
	# older ones lie under it.
	var held := _strongest_per(Grudges.held_by(house.org_id), true)
	if not held.is_empty():
		var parts: Array[String] = []
		for entry in held.slice(0, 4):
			parts.append(_grudge_text(entry[0], StringName(entry[0]["target"]), "へ", int(entry[1])))
		out.append("[color=#9a9080]遺恨[/color]  %s" % "\n　　".join(parts))
	var against := _strongest_per(Grudges.against(house.org_id), false)
	if not against.is_empty():
		var parts: Array[String] = []
		for entry in against.slice(0, 3):
			parts.append(_grudge_text(entry[0], Grudges.holder_of(entry[0]), "から", int(entry[1])))
		out.append("[color=#9a9080]恨まれて[/color]  %s" % "\n　　".join(parts))
	if house.intrigue_won > 0 or house.intrigue_lost > 0:
		out.append("[color=#9a9080]政争[/color]  %d勝%d敗" % [house.intrigue_won, house.intrigue_lost])
	var quarrel := Intrigue.involving(house.org_id)
	if not quarrel.is_empty():
		var other := GameState.get_organization(StringName(quarrel["target"]
			if StringName(quarrel["instigator"]) == house.org_id else quarrel["instigator"]))
		out.append("[color=#c85a4a]政争中[/color]  %s%s（%s）" % [
			other.formal_name() if other != null else "?",
			"を狙う" if StringName(quarrel["instigator"]) == house.org_id else "に狙われている",
			Intrigue.prize_label(quarrel)])
	var falls := fall_lines(house)
	if not falls.is_empty():
		out.append(falls)
	return "\n".join(out)


## [grudge, how many others between the same two families], strongest first.
static func _strongest_per(list: Array[Dictionary], by_target: bool) -> Array:
	var seen := {}
	var out: Array = []
	for g in list:
		var other := String(g["target"]) if by_target else String(Grudges.holder_of(g))
		if seen.has(other):
			out[int(seen[other])][1] += 1
			continue
		seen[other] = out.size()
		out.append([g, 0])
	return out


static func _grudge_text(g: Dictionary, other_id: StringName, particle: String, more := 0) -> String:
	var other := GameState.get_organization(other_id)
	var strength := Grudges.strength_of(g)
	var generations := int(g.get("generations", 0))
	var colour := "c85a4a" if strength >= 0.55 else "9a9080"
	return "[color=#%s]%s%s %s[/color]（%s%s。%s%s）" % [colour,
		other.formal_name() if other != null else "絶えた家", particle,
		Grudges.depth_label(strength), Grudges.why_label(g),
		"、%d代前から" % generations if generations > 0 else "", String(g.get("why", "")),
		"。ほかに%d件" % more if more > 0 else ""]


## 降格・左遷: what quarrels at court have cost a family's people, newest first.
static func fall_lines(house: Organization) -> String:
	var entries: Array = []
	for person in GameState.house_members(house.org_id, false):
		for f in person.falls:
			entries.append([int(f.get("tick", 0)), person, f])
	if entries.is_empty():
		return ""
	entries.sort_custom(func(x, y) -> bool: return int(x[0]) > int(y[0]))
	var parts: Array[String] = []
	for entry in entries.slice(0, 4):
		parts.append(fall_text(entry[1], entry[2]))
	return "[color=#9a9080]失脚の経歴[/color]  %s" % "、".join(parts)


static func fall_text(person: NotableIndividual, f: Dictionary, with_name := true) -> String:
	var polity := GameState.get_organization(StringName(f.get("polity", "")))
	var by := GameState.get_organization(StringName(f.get("by", "")))
	var kind := String(f.get("kind", ""))
	var what := Intrigue.fall_label(kind)
	if String(f.get("office", "")) != "":
		what = "%s——%sを解かれる" % [what, Offices.label_of(String(f["office"]), polity)]
	var why := ""
	if by != null:
		why = "（%sとの政争）" % by.formal_name()
	return "%d年 %s%s%s" % [int(int(f.get("tick", 0)) / SimConfig.TICKS_PER_YEAR),
		person.short_name + " " if with_name and person != null else "", what, why]


## The 氏 a family belongs to and every other family of it: where it came from,
## and who else came from the same place.
static func uji_lines(house: Organization) -> String:
	if house == null or house.uji_id == &"":
		return ""
	var kin: Array[String] = []
	for other in HouseNaming.houses_of_uji(house.uji_id):
		if other.org_id == house.org_id:
			continue
		var name := other.display_name if other.org_id != house.uji_id \
			else "%s（宗家）" % other.display_name
		kin.append(name if other.is_active() else "[color=#6a6357]%s・絶[/color]" % name)
	var text := "[color=#9a9080]氏[/color]  %s" % HouseNaming.uji_summary(house.uji_id)
	if not kin.is_empty():
		text += "\n[color=#9a9080]同じ氏の家[/color]  %s" % "、".join(kin)
	return text


## Why this body exists at all, read back off the event that created it.
##
## Nothing extra is stored for this: the schism that founded a branch already
## records what kind of quarrel it was and the sentence the chronicle printed at
## the time. A family looking at its own cadet branches should be able to see
## which one left over an unfit heir and which one over a marriage.
func _why_it_branched(org: Organization) -> String:
	var story := HousePartition.origin_story(org)
	if story.is_empty():
		# Guilds, factions and faiths branch too, and their founding events say
		# so in the same shape; only the peerage labels are house-flavoured.
		if org.origin_event_id == &"":
			return ""
		var origin := HistoryLog.find_event(org.origin_event_id)
		if origin == null or origin.event_type != HistoryEvent.EventType.SCHISM:
			return ""
		story = {
			"label": HousePartition.reason_label(
				StringName(origin.payload.get("schism_kind", ""))),
			"reason": String(origin.payload.get("reason", "")),
			"text": origin.description,
		}
	var lines: Array[String] = ["[color=#9a9080]分かれた理由[/color]  %s" % story["label"]]
	if not String(story.get("reason", "")).is_empty():
		lines[0] += "（%s）" % story["reason"]
	if not String(story.get("text", "")).is_empty():
		lines.append("[color=#6a6357]%s[/color]" % story["text"])
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
			warm.append("%s（%s）" % [other.formal_name(), HouseRelations.describe(value)])
		elif value < -0.2:
			cold.append("%s（%s）" % [other.formal_name(), HouseRelations.describe(value)])
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

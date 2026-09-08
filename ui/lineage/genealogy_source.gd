class_name GenealogySource
extends LineageSource

## The family tree. A child has two parents but is drawn once, under whichever
## parent the traversal reaches first — otherwise the same person would appear in
## two places and the tree would stop reading as a tree.

func roots() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		if p.is_founder_generation and p.father_id == &"" and p.mother_id == &"":
			out.append(id)
	# Founders who never had children clutter the view without adding lineage.
	var meaningful: Array[StringName] = []
	for id in out:
		var p: NotableIndividual = GameState.people[id]
		if not p.children_ids.is_empty() or p.ever_held_office():
			meaningful.append(id)
	return meaningful if not meaningful.is_empty() else out


func children(id: StringName) -> Array[StringName]:
	var p := GameState.get_person(id)
	if p == null:
		return []
	var out: Array[StringName] = []
	for child_id in p.children_ids:
		var child := GameState.get_person(child_id)
		if child == null:
			continue
		# Claim each child under one parent only — the father where he is known —
		# so a couple's children are drawn once, beneath the pair.
		if child.father_id != &"" and child.father_id != id \
				and GameState.get_person(child.father_id) != null:
			continue
		out.append(child_id)
	return out


func parents(id: StringName) -> Array[StringName]:
	var p := GameState.get_person(id)
	if p == null:
		return []
	var out: Array[StringName] = []
	if p.father_id != &"":
		out.append(p.father_id)
	if p.mother_id != &"":
		out.append(p.mother_id)
	return out


func spouses(id: StringName) -> Array[StringName]:
	var p := GameState.get_person(id)
	if p == null:
		return []
	var out: Array[StringName] = []
	for spouse_id in p.spouse_ids:
		if GameState.get_person(spouse_id) != null:
			out.append(spouse_id)
	return out


func label(id: StringName) -> String:
	var p := GameState.get_person(id)
	return p.full_name if p != null else String(id)


func sublabel(id: StringName) -> String:
	var p := GameState.get_person(id)
	if p == null:
		return ""
	var span := "%d年〜" % int(p.birth_tick / SimConfig.TICKS_PER_YEAR)
	if not p.is_alive():
		span += "%d年" % int(p.death_tick / SimConfig.TICKS_PER_YEAR)
	else:
		span += "存命"
	var tenure := p.current_tenure()
	if tenure != null:
		var org := GameState.get_organization(tenure.org_id)
		if org != null:
			return "%s・%s%s" % [span, org.display_name, tenure.title]
	return span


func colour(id: StringName) -> Color:
	var p := GameState.get_person(id)
	if p == null:
		return Palette.TEXT_MUTED
	var tenure := p.current_tenure()
	if tenure != null:
		var org := GameState.get_organization(tenure.org_id)
		if org != null:
			return Palette.for_kind(org.kind)
	# Anyone who ever held office is worth picking out from the rest of the family.
	return Palette.ACCENT if p.ever_held_office() else Palette.TEXT_MUTED


func is_faded(id: StringName) -> bool:
	var p := GameState.get_person(id)
	return p != null and not p.is_alive()


func exists(id: StringName) -> bool:
	return GameState.get_person(id) != null


func detail(id: StringName) -> String:
	var p := GameState.get_person(id)
	if p == null:
		return ""
	var lines: Array[String] = []
	var age := p.age_years(SimClock.current_tick)
	lines.append("[color=#9a9080]生没[/color]  %d年〜%s（%d歳%s）" % [
		int(p.birth_tick / SimConfig.TICKS_PER_YEAR),
		"存命" if p.is_alive() else "%d年" % int(p.death_tick / SimConfig.TICKS_PER_YEAR),
		age, "" if p.is_alive() else "没"])

	var father := GameState.get_person(p.father_id)
	var mother := GameState.get_person(p.mother_id)
	if father != null or mother != null:
		lines.append("[color=#9a9080]両親[/color]  %s ／ %s" % [
			father.full_name if father != null else "不明",
			mother.full_name if mother != null else "不明"])
	elif p.is_founder_generation:
		lines.append("[color=#9a9080]両親[/color]  始祖の世代")

	if not p.spouse_ids.is_empty():
		var spouses: Array[String] = []
		for sid in p.spouse_ids:
			var s := GameState.get_person(sid)
			if s != null:
				spouses.append(s.full_name)
		lines.append("[color=#9a9080]配偶者[/color]  %s" % "、".join(spouses))

	if not p.children_ids.is_empty():
		lines.append("[color=#9a9080]子[/color]  %d人" % p.children_ids.size())

	if not p.role_history.is_empty():
		var roles: Array[String] = []
		for t in p.role_history:
			var org := GameState.get_organization(t.org_id)
			if org == null:
				continue
			var years := "%d年〜%s" % [int(t.start_tick / SimConfig.TICKS_PER_YEAR),
				"現在" if t.is_current() else "%d年" % int(t.end_tick / SimConfig.TICKS_PER_YEAR)]
			roles.append("%s%s（%s）" % [org.display_name, t.title, years])
		lines.append("[color=#9a9080]履歴[/color]  %s" % "\n　　　".join(roles))

	if not p.personality_tags.is_empty():
		var traits: Array[String] = []
		for tag in p.personality_tags:
			traits.append(TRAIT_LABELS.get(tag, String(tag)))
		lines.append("[color=#9a9080]気質[/color]  %s" % "、".join(traits))

	var founder := GenealogyValidator.founder_of(id)
	if founder != null and founder.person_id != id:
		lines.append("[color=#9a9080]始祖[/color]  %s" % founder.full_name)
	return "\n".join(lines)


const TRAIT_LABELS := {
	&"ambitious": "野心的",
	&"pious": "敬虔",
	&"cautious": "慎重",
	&"martial": "武勇",
	&"scholarly": "学識",
	&"greedy": "強欲",
	&"just": "公正",
}


func search(query: String) -> Array[StringName]:
	var out: Array[StringName] = []
	var needle := query.strip_edges()
	if needle.is_empty():
		return out
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		if p.full_name.contains(needle):
			out.append(id)
	return out

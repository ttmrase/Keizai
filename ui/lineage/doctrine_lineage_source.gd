class_name DoctrineLineageSource
extends LineageSource

## 思想の系譜 as a tree: every doctrine hangs from the one it came out of, back to
## the first the world produced. The line into each is coloured by how it came
## out of its parent — carried on, split over, written against, revived, set
## down from a reign — a synthesis is also tied to its second parent, and a
## doctrine nobody holds any more is drawn faint.

const DERIVATION_COLOURS := {
	"development": Color(0.62, 0.58, 0.5),
	"schism": Color(0.83, 0.65, 0.28),
	"reaction": Color(0.78, 0.35, 0.29),
	"synthesis": Color(0.45, 0.66, 0.5),
	"revival": Color(0.85, 0.78, 0.45),
	"governance": Color(0.45, 0.58, 0.8),
}


func roots() -> Array[StringName]:
	var out: Array[StringName] = []
	for d in Doctrines.all():
		if d.parent_id == &"":
			out.append(d.doctrine_id)
	return out


func children(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for d in Doctrines.all():
		if d.parent_id == id:
			out.append(d.doctrine_id)
	return out


func parents(id: StringName) -> Array[StringName]:
	var d := Doctrines.get_doctrine(id)
	if d == null or d.parent_id == &"":
		return []
	return [d.parent_id]


func label(id: StringName) -> String:
	var d := Doctrines.get_doctrine(id)
	return d.name if d != null else String(id)


func sublabel(id: StringName) -> String:
	var d := Doctrines.get_doctrine(id)
	if d == null:
		return ""
	var held := d.adopted_by()
	var parts: Array[String] = ["%d年・%s" % [int(d.born_tick / SimConfig.TICKS_PER_YEAR),
		Doctrines.derivation_label(d.derivation)]]
	if not held.is_empty():
		parts.append("国是")
	elif d.state != "rising":
		parts.append(Doctrines.state_label(d.state))
	return "・".join(parts)


func colour(id: StringName) -> Color:
	var d := Doctrines.get_doctrine(id)
	if d == null:
		return Palette.TEXT_MUTED
	return DERIVATION_COLOURS.get(d.derivation, Palette.ACCENT)


func is_faded(id: StringName) -> bool:
	var d := Doctrines.get_doctrine(id)
	return d != null and not d.is_alive()


func badge(id: StringName) -> StringName:
	var d := Doctrines.get_doctrine(id)
	return &"crown" if d != null and not d.adopted_by().is_empty() else &""


func edge_colour(parent_id: StringName, child_id: StringName) -> Color:
	var d := Doctrines.get_doctrine(child_id)
	if d == null:
		return Palette.LINE
	return DERIVATION_COLOURS.get(d.derivation, Palette.LINE)


## A synthesis's second parent, drawn as a broken line beside the tree.
func extra_links() -> Array:
	var out: Array = []
	for d in Doctrines.all():
		if d.second_parent_id != &"":
			out.append([d.second_parent_id, d.doctrine_id, DERIVATION_COLOURS["synthesis"]])
	return out


func exists(id: StringName) -> bool:
	return Doctrines.get_doctrine(id) != null


func all_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for d in Doctrines.all():
		out.append(d.doctrine_id)
	return out


func search(query: String) -> Array[StringName]:
	var out: Array[StringName] = []
	var needle := query.strip_edges()
	if needle.is_empty():
		return out
	for d in Doctrines.all():
		if d.name.contains(needle):
			out.append(d.doctrine_id)
	return out


func detail(id: StringName) -> String:
	var d := Doctrines.get_doctrine(id)
	if d == null:
		return ""
	return detail_text(d)


static func detail_text(d: Doctrine) -> String:
	var lines: Array[String] = []
	var born := GameState.get_organization(d.born_polity_id)
	lines.append("[color=#9a9080]生まれ[/color]  %d年・%s・%s" % [
		int(d.born_tick / SimConfig.TICKS_PER_YEAR), born.formal_name() if born != null else "?",
		Doctrines.derivation_label(d.derivation)])
	var parent := Doctrines.get_doctrine(d.parent_id)
	if parent != null:
		var second := Doctrines.get_doctrine(d.second_parent_id)
		lines.append("[color=#9a9080]%s[/color]  %s%s" % [
			"反対した相手" if d.derivation == "reaction" else "親の思想", parent.name,
			"・%s" % second.name if second != null else ""])
	if d.model_ruler_id != &"":
		var ruler := GameState.get_person(d.model_ruler_id)
		var model := GameState.get_organization(d.model_polity_id)
		lines.append("[color=#9a9080]範とした治世[/color]  %s%s" % [
			model.formal_name() if model != null else "", "の" + ruler.full_name if ruler != null else ""])
	lines.append("[color=#9a9080]主張[/color]  %s" % Doctrines.claims_text(d))
	var thinkers: Array[String] = []
	for t in d.thinkers:
		var p := GameState.get_person(StringName(t.get("person", "")))
		var teacher := GameState.get_person(StringName(t.get("teacher", "")))
		thinkers.append("%d年 %s %s%s" % [int(int(t.get("tick", 0)) / SimConfig.TICKS_PER_YEAR),
			p.full_name if p != null else "?", String(t.get("work", "")),
			"（%sに学ぶ）" % teacher.short_name if teacher != null else ""])
	lines.append("[color=#9a9080]%s[/color]  %s" % ["祖と思想家" if thinkers.size() > 1 else "祖",
		"\n　　".join(thinkers)])
	var creeds: Array[String] = []
	for a in d.adoptions:
		var polity := GameState.get_organization(StringName(a.get("polity", "")))
		var end := int(a.get("end", -1))
		creeds.append("%s（%d年〜%s）" % [polity.formal_name() if polity != null else "?",
			int(int(a.get("start", 0)) / SimConfig.TICKS_PER_YEAR),
			"現在" if end < 0 else "%d年" % int(end / SimConfig.TICKS_PER_YEAR)])
	lines.append("[color=#9a9080]国是とした国[/color]  %s" % ("、".join(creeds) if not creeds.is_empty()
		else "まだない"))
	var banners: Array[String] = []
	for faction in GameState.organizations_of_kind(Organization.OrgKind.FACTION):
		if faction.doctrine_id == d.doctrine_id:
			banners.append(faction.formal_name())
	if not banners.is_empty():
		lines.append("[color=#9a9080]綱領に掲げる派閥[/color]  %s" % "、".join(banners))
	var stance: String = {"blessed": "信仰に祝福されている", "heresy": "信仰に異端とされている"}.get(d.faith_stance, "")
	lines.append("[color=#9a9080]盛衰[/color]  %s・声望%d%%・共感%d%%・完成度%d%%%s" % [
		Doctrines.state_label(d.state), int(d.prestige * 100.0), int(d.support * 100.0),
		int(d.maturity * 100.0), "・" + stance if stance != "" else ""])
	var heirs := Doctrines.children_of(d.doctrine_id)
	if not heirs.is_empty():
		var names: Array[String] = []
		for c in heirs:
			names.append("%s（%s）" % [c.name, Doctrines.derivation_label(c.derivation)])
		lines.append("[color=#9a9080]生まれた思想[/color]  %s" % "、".join(names))
	return "\n".join(lines)

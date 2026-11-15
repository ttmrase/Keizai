extends Node

## Lets the player name things.
##
## This is deliberately not part of GodPowerAPI. Naming a place or a house does
## not change a single number in the simulation — it does not make anyone
## stronger, or shift who inherits what — so it does not belong behind the same
## boundary as the environmental dials. What it does do is make the world the
## player's own, which is worth having in a game about watching one.
##
## Renaming a house renames every living member of it, because a surname is the
## house's name rather than the person's.

signal name_changed(subject_id: StringName)

const MAX_LENGTH := SimConfig.MAX_NAME_LENGTH


func rename_settlement(settlement_id: StringName, new_name: String) -> bool:
	var settlement: SettlementState = GameState.world.settlements.get(settlement_id)
	var clean := _sanitize(new_name)
	if settlement == null or clean.is_empty() or clean == settlement.display_name:
		return false

	var previous := settlement.display_name
	settlement.display_name = clean
	HistoryLog.emit_event(
		HistoryEvent.EventType.RENAMED,
		SimClock.current_tick,
		"%sは%sと呼ばれるようになった。" % [previous, clean],
		{"subject": String(settlement_id), "from": previous, "to": clean, "kind": "settlement"})
	name_changed.emit(settlement_id)
	return true


func rename_organization(org_id: StringName, new_name: String) -> bool:
	var org := GameState.get_organization(org_id)
	var clean := _sanitize(new_name)
	if org == null or clean.is_empty() or clean == org.display_name:
		return false

	var previous := org.display_name
	var previous_formal := org.formal_name()
	var previous_uji := HouseNaming.uji_label(org.org_id) \
		if HouseNaming.founded_uji(org) else ""
	# A house's name is its members' surname, so keep the suffix that marks it
	# as a house rather than letting the two conventions drift apart.
	if org.kind == Organization.OrgKind.HOUSE and not clean.ends_with(HouseNaming.HOUSE_SUFFIX):
		clean += HouseNaming.HOUSE_SUFFIX

	org.display_name = clean
	var restyled := 0
	if org.kind == Organization.OrgKind.HOUSE:
		restyled = HouseNaming.restyle_members(org_id)

	var text := "%sは%sと名を改めた。" % [previous_formal, org.formal_name()]
	if restyled > 0:
		text = "%sは%sと名を改め、%d名がその名を継いだ。" % [previous_formal,
			org.formal_name(), restyled]
	# The house a 氏 is named for takes the 氏 with it: every family of that
	# 氏 goes by the new name from now on.
	if previous_uji != "":
		var kin := HouseNaming.houses_of_uji(org.org_id, true).size() - 1
		if kin > 0:
			text += "%sの諸家%d家も、以後は%sを名乗る。" % [previous_uji, kin,
				HouseNaming.uji_label(org.org_id)]
	HistoryLog.emit_event(
		HistoryEvent.EventType.RENAMED,
		SimClock.current_tick,
		text,
		{"subject": String(org_id), "from": previous, "to": clean, "kind": org.kind_name()},
		org_id)
	name_changed.emit(org_id)
	return true


func _sanitize(raw: String) -> String:
	var clean := raw.strip_edges()
	# Naming slots are resolved with braces, so a name containing them would
	# confuse anything that later runs it through a template.
	clean = clean.replace("{", "").replace("}", "")
	if clean.length() > MAX_LENGTH:
		clean = clean.substr(0, MAX_LENGTH)
	return clean

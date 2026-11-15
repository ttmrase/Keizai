extends Control

## Who holds influence, and why. Tapping a bar opens the breakdown, which is the
## point: it names the world conditions the player created that put this
## organization where it is.
##
## Each row also says which way it is going — a line of the last decades and the
## change over the last ten years — because the question a reader brings to this
## screen is less "who is strongest" than "who is coming".

const KIND_GLYPHS := {
	Organization.OrgKind.POLITICAL_SYSTEM: &"crown",
	Organization.OrgKind.GUILD: &"coin",
	Organization.OrgKind.FACTION: &"banner",
	Organization.OrgKind.HOUSE: &"keep",
	Organization.OrgKind.RELIGION: &"altar",
}
## A change smaller than this over ten years reads as holding steady, and is
## left unmarked.
const STEADY := 3.0

const KIND_FILTERS := [
	{"label": "すべて", "kind": -1},
	{"label": "政体", "kind": Organization.OrgKind.POLITICAL_SYSTEM},
	{"label": "ギルド", "kind": Organization.OrgKind.GUILD},
	{"label": "派閥", "kind": Organization.OrgKind.FACTION},
	{"label": "家", "kind": Organization.OrgKind.HOUSE},
	{"label": "信仰", "kind": Organization.OrgKind.RELIGION},
	# Not a kind of organization: every family of one 氏, added up.
	{"label": "氏", "kind": UJI_FILTER},
]
const UJI_FILTER := -2

var _filter := -1
var _expanded: StringName = &""

@onready var _tabs: HBoxContainer = $Rows/Filters
@onready var _list: VBoxContainer = $Rows/Scroll/List


func _ready() -> void:
	for i in KIND_FILTERS.size():
		var button := Button.new()
		button.text = KIND_FILTERS[i]["label"]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 42)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 17)
		button.pressed.connect(_on_filter.bind(i))
		_tabs.add_child(button)

	EventBus.power_recalculated.connect(_on_power_recalculated)
	EventBus.game_loaded.connect(_rebuild)
	EventBus.world_reset.connect(_rebuild)
	_sync_tabs()
	_rebuild()


func on_shown() -> void:
	_rebuild()


func _on_power_recalculated(_tick: int) -> void:
	if is_visible_in_tree():
		_rebuild()


func _on_filter(index: int) -> void:
	_filter = KIND_FILTERS[index]["kind"]
	_sync_tabs()
	_rebuild()


func _sync_tabs() -> void:
	for i in _tabs.get_child_count():
		Palette.style_pill(_tabs.get_child(i), KIND_FILTERS[i]["kind"] == _filter)


func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()

	if _filter == UJI_FILTER:
		_build_uji_table()
		return

	var ranked := PowerCalculator.ranked(_filter)
	if ranked.is_empty():
		var empty := Label.new()
		empty.text = "該当する組織がない。"
		empty.add_theme_color_override("font_color", Palette.TEXT_DIM)
		_list.add_child(empty)
		return

	# The balance below is what produces the form of government above it, so the
	# two belong on the same screen.
	if _filter < 0:
		for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
			_list.add_child(_government_banner(polity))

	var strongest: float = maxf(1.0, ranked[0].power_score)
	for i in ranked.size():
		var org: Organization = ranked[i]
		_list.add_child(_row(org, strongest, i + 1))
		if org.org_id == _expanded:
			_list.add_child(_breakdown(org))


## The great offices of a state as text: one line a seat, then the heir houses.
static func office_lines(polity: Organization) -> String:
	var lines: Array[String] = []
	if Offices.is_regency_by_right(polity):
		var regent := GameState.get_organization(StringName(polity.hereditary_offices["regent"]))
		lines.append("摂関政治：実権は%sにある" % (regent.formal_name() if regent != null else "摂政家"))
	var keys := polity.offices.keys()
	keys.sort_custom(func(x, y): return float(Offices.WEIGHT.get(String(x), 0.0)) > float(Offices.WEIGHT.get(String(y), 0.0)))
	for key in keys:
		var entry: Dictionary = polity.offices[key]
		var person := GameState.get_person(StringName(entry.get("person", "")))
		var house := GameState.get_organization(StringName(entry.get("house", "")))
		var hereditary := StringName(polity.hereditary_offices.get(key, "")) == StringName(entry.get("house", ""))
		lines.append("%s　%s（%s・%d年〜%s）" % [Offices.label_of(String(key), polity),
			person.full_name if person != null else "?",
			house.formal_name() if house != null else "家なし",
			int(int(entry.get("since", 0)) / SimConfig.TICKS_PER_YEAR),
			"・家職" if hereditary else ""])
	if not polity.heir_houses.is_empty():
		var names: Array[String] = []
		for i in polity.heir_houses.size():
			var house := GameState.get_organization(polity.heir_houses[i])
			if house != null:
				names.append("%d.%s" % [i + 1, house.formal_name()])
		lines.append("跡目家　%s" % "　".join(names))
	return "\n".join(lines)


## The families added up by 氏: how much of the world each great house of the
## first day still stands behind, through every line that came out of it.
func _build_uji_table() -> void:
	var rows: Array = []
	for uji_id in HouseNaming.all_uji():
		var power := 0.0
		var living := 0
		var land := 0
		var seats := 0
		var strongest: Organization = null
		for house in HouseNaming.houses_of_uji(uji_id, true):
			living += 1
			power += house.power_score
			land += house.held_settlement_ids.size()
			seats += GameState.offices_of_house(house.org_id).size()
			if strongest == null or house.power_score > strongest.power_score:
				strongest = house
		rows.append({"uji": uji_id, "power": power, "living": living, "land": land,
			"seats": seats, "strongest": strongest})
	rows.sort_custom(func(a, b):
		if not is_equal_approx(float(a["power"]), float(b["power"])):
			return float(a["power"]) > float(b["power"])
		return String(a["uji"]) < String(b["uji"]))
	var top := 1.0
	for row in rows:
		top = maxf(top, float(row["power"]))
	for i in rows.size():
		_list.add_child(_uji_row(rows[i], top, i + 1))


func _uji_row(row: Dictionary, top: float, rank: int) -> Control:
	var uji_id: StringName = row["uji"]
	var founder := GameState.get_organization(uji_id)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.PANEL_RAISED if int(row["living"]) > 0 else Palette.PANEL
	style.border_color = Heraldry.of_org(founder) if founder != null else Palette.HOUSE
	style.border_width_left = 4
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	panel.add_child(line)
	var place := Label.new()
	place.text = str(rank)
	place.custom_minimum_size = Vector2(28, 0)
	place.add_theme_font_size_override("font_size", 18)
	place.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	line.add_child(place)
	line.add_child(CrestIcon.make(uji_id, 36))
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	line.add_child(words)
	var name := Label.new()
	name.text = HouseNaming.uji_label(uji_id)
	name.add_theme_font_size_override("font_size", 20)
	name.add_theme_color_override("font_color", Palette.TEXT if int(row["living"]) > 0 else Palette.TEXT_DIM)
	words.add_child(name)
	var sub := Label.new()
	var strongest: Organization = row["strongest"]
	sub.text = "現存%d家・所領%d・役%d%s" % [int(row["living"]), int(row["land"]), int(row["seats"]),
		"　筆頭 %s" % strongest.formal_name() if strongest != null else "　すべて絶えた"]
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	words.add_child(sub)
	var score := Label.new()
	score.text = str(int(row["power"]))
	score.add_theme_font_size_override("font_size", 22)
	score.add_theme_color_override("font_color", Palette.ACCENT if rank == 1 else Palette.TEXT)
	line.add_child(score)
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 4)
	panel.remove_child(line)
	holder.add_child(line)
	var track := Control.new()
	track.custom_minimum_size = Vector2(0, 3)
	track.draw.connect(func():
		track.draw_rect(Rect2(Vector2.ZERO, Vector2(track.size.x * float(row["power"]) / top, 3)),
			Color(style.border_color, 0.7)))
	holder.add_child(track)
	panel.add_child(holder)
	return panel


## What this country currently is, in its own words — read off the balance of
## power rather than set anywhere.
func _government_banner(polity: Organization) -> Control:
	var form := PolityFormEvaluator.form_of(polity)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.PANEL_RAISED
	style.border_color = Palette.POLITY
	style.border_width_left = 4
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	panel.add_child(rows)

	var heading := Label.new()
	heading.text = "%s　—　%s" % [polity.formal_name(),
		form.display_name if form != null else "統治のかたち不明"]
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_font_size_override("font_size", 21)
	heading.add_theme_color_override("font_color", Palette.ACCENT)
	rows.add_child(heading)

	if form != null:
		var blurb := Label.new()
		blurb.text = form.description
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.add_theme_font_size_override("font_size", 16)
		blurb.add_theme_color_override("font_color", Palette.TEXT_MUTED)
		rows.add_child(blurb)

	var ruler := GameState.get_current_leader(polity.org_id)
	var line := Label.new()
	line.text = "%s %s　／　%s　／　領地 %d" % [
		polity.leadership_title,
		ruler.full_name if ruler != null else "空位",
		form.council_label if form != null else "",
		polity.governs_settlement_ids.size()]
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_theme_font_size_override("font_size", 17)
	line.add_theme_color_override("font_color", Palette.TEXT)
	rows.add_child(line)

	# The seats beside the head: who holds them, from which family, since when,
	# and whether they have become that family's by right.
	var offices := office_lines(polity)
	if not offices.is_empty():
		var held := Label.new()
		held.text = offices
		held.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		held.add_theme_font_size_override("font_size", 15)
		held.add_theme_color_override("font_color", Palette.TEXT)
		rows.add_child(held)

	# The division of the chamber is what a faction amounts to under a regime that
	# has one, and it is also what the next upheaval will be decided on.
	var seated := SocialTies.seat_order(polity)
	if not seated.is_empty():
		var parts: Array[String] = []
		for faction in seated.slice(0, 4):
			parts.append("%s %d" % [faction.formal_name(),
				int(polity.faction_seats.get(faction.org_id, 0))])
		var seats := Label.new()
		seats.text = "%s（全%d議席）　%s" % [form.council_label if form != null else "議場",
			polity.seat_total, "　".join(parts)]
		seats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		seats.add_theme_font_size_override("font_size", 15)
		seats.add_theme_color_override("font_color", Palette.TEXT_MUTED)
		rows.add_child(seats)

	var challenge := RegimeShift.standing_challenge(polity)
	var pressure := Label.new()
	if challenge.is_empty():
		pressure.text = "正統性 %d%%　／　体制に挑む者なし" % int(polity.legitimacy * 100.0)
		pressure.add_theme_color_override("font_color", Palette.TEXT_DIM)
	else:
		pressure.text = "正統性 %d%%　／　%sを背に%sが迫っている（掌握 %d%%）" % [
			int(polity.legitimacy * 100.0), challenge.get("ground", ""),
			challenge["org"].formal_name(), int(float(challenge.get("hold", 0.0)) * 100.0)]
		pressure.add_theme_color_override("font_color", Palette.DANGER)
	pressure.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pressure.add_theme_font_size_override("font_size", 15)
	rows.add_child(pressure)
	return panel


func _row(org: Organization, strongest: float, rank: int) -> Control:
	var tint := Heraldry.of_org(org)
	var open := org.org_id == _expanded
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 66)
	button.focus_mode = Control.FOCUS_NONE
	button.flat = true
	button.pressed.connect(_on_row_pressed.bind(org.org_id))
	var back := StyleBoxFlat.new()
	back.bg_color = Palette.PANEL if open else Color(0, 0, 0, 0)
	back.corner_radius_top_left = 8
	back.corner_radius_top_right = 8
	if not open:
		back.corner_radius_bottom_left = 8
		back.corner_radius_bottom_right = 8
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(state, back)

	var bar := Panel.new()
	var bar_box := StyleBoxFlat.new()
	bar_box.bg_color = Color(tint, 0.2)
	bar_box.set_corner_radius_all(8)
	bar.add_theme_stylebox_override("panel", bar_box)
	bar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	bar.anchor_right = clampf(org.power_score / strongest, 0.04, 1.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(bar)

	var accent := ColorRect.new()
	accent.color = tint
	accent.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	accent.offset_top = 6.0
	accent.offset_bottom = -6.0
	accent.offset_right = 4.0
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(accent)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -10
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	var place := Label.new()
	place.text = "%d" % rank
	place.custom_minimum_size = Vector2(28, 0)
	place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	place.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	place.add_theme_font_size_override("font_size", 20 if rank <= 3 else 16)
	place.add_theme_color_override("font_color", Palette.ACCENT if rank <= 3 else Palette.TEXT_DIM)
	place.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(place)

	# A family is shown by its arms; everything else by what kind of body it is.
	var icon: Control
	if org.kind == Organization.OrgKind.HOUSE:
		icon = CrestIcon.make(org.org_id, 30)
	else:
		icon = GlyphIcon.make(KIND_GLYPHS.get(org.kind, &"seal"), tint, 26)
		icon.custom_minimum_size = Vector2(30, 26)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 0)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	var name_label := Label.new()
	name_label.text = org.formal_name()
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Palette.TEXT)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(name_label)
	var leader := GameState.get_current_leader(org.org_id)
	var sub := Label.new()
	sub.text = "%s・%d名　%s%s" % [_kind_note(org), org.member_count,
		leader.full_name if leader != null else "指導者不在", _house_note(org)]
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(sub)

	# Marked when a spoken prophecy is about it: the god is watching this one.
	if Oracle.is_foretold(org.org_id):
		var mark := GlyphIcon.make(&"sparkle", Palette.ACCENT, 18)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(mark)

	var line := Sparkline.new()
	line.values = PowerHistory.series(org.org_id)
	line.colour = tint
	line.custom_minimum_size = Vector2(70, 30)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line)

	var numbers := VBoxContainer.new()
	numbers.custom_minimum_size = Vector2(56, 0)
	numbers.alignment = BoxContainer.ALIGNMENT_CENTER
	numbers.add_theme_constant_override("separation", -4)
	numbers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(numbers)
	var score := Label.new()
	score.text = "%d" % int(org.power_score)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score.add_theme_font_size_override("font_size", 26)
	score.add_theme_color_override("font_color", Palette.ACCENT)
	score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	numbers.add_child(score)
	# Only a real move is marked; a column of arrows saying "about the same"
	# would hide the two rows that are actually going somewhere.
	var change := PowerHistory.change(org.org_id)
	if not is_nan(change) and absf(change) >= STEADY:
		var trend := Label.new()
		trend.text = "%s%d" % ["▲" if change > 0.0 else "▼", int(round(absf(change)))]
		trend.add_theme_color_override("font_color",
			Palette.GOOD if change > 0.0 else Palette.DANGER)
		trend.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		trend.add_theme_font_size_override("font_size", 13)
		trend.mouse_filter = Control.MOUSE_FILTER_IGNORE
		numbers.add_child(trend)
	return button


## What a family is: where it stands, what rank it holds if it holds one, and
## what kind of household it keeps.
func _house_note(org: Organization) -> String:
	if org.kind != Organization.OrgKind.HOUSE:
		return ""
	if org.standing != Organization.Standing.NOBLE:
		var liege := GameState.get_organization(org.liege_house_id)
		return "（%s・%s%s）" % [org.standing_label(),
			HouseCharacter.label(org.character_id),
			"／%s" % liege.formal_name() if liege != null else ""]
	return "（%s・%s）" % [HouseRank.tier_name(org.rank_tier),
		HouseCharacter.label(org.character_id)]


## What kind of body this is, and — for the ones that have offices to fill — how
## it fills them. A guild one family has taken over says so here.
func _kind_note(org: Organization) -> String:
	var base := Palette.kind_label(org.kind)
	if org.kind == Organization.OrgKind.HOUSE or org.kind == Organization.OrgKind.POLITICAL_SYSTEM:
		return base
	var patron := GameState.get_organization(org.patron_house_id)
	if patron != null:
		return "%s・%s(%s)" % [base, SocialTies.office_basis_label(org), patron.formal_name()]
	return "%s・%s" % [base, SocialTies.office_basis_label(org)]


## Names each world condition feeding this organization's influence, so a player
## can trace a rise back to the dial they turned.
func _breakdown(org: Organization) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.PANEL
	style.border_color = Color(Heraldry.of_org(org), 0.6)
	style.border_width_left = 4
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	panel.add_child(rows)

	var profile := ContentRegistry.get_power_profile(org.archetype_id)
	var labels := {}
	if profile != null:
		for d in profile.drivers:
			labels[d.world_var_path] = d.label if not d.label.is_empty() else String(d.world_var_path)
	labels[PowerCalculator.BASE_KEY] = "基礎"
	labels[PowerCalculator.MEMBERSHIP_KEY] = "規模"
	labels[PowerCalculator.LEADERSHIP_KEY] = "指導者の力量"
	labels[PowerCalculator.PEDIGREE_KEY] = "家格の重み"
	labels[PowerCalculator.CHARACTER_KEY] = "家風"
	labels[PowerCalculator.REALM_SUPPORT_KEY] = "諸家の支え"
	labels[PowerCalculator.WAR_KEY] = "戦の明暗"

	var entries: Array = []
	for key in org.power_drivers:
		entries.append([labels.get(key, String(key)), float(org.power_drivers[key])])
	entries.sort_custom(func(a, b): return absf(a[1]) > absf(b[1]))

	for entry in entries:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = entry[0]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 17)
		name_label.add_theme_color_override("font_color", Palette.TEXT_MUTED)
		row.add_child(name_label)

		var value := Label.new()
		value.text = "%+.1f" % entry[1]
		value.add_theme_font_size_override("font_size", 17)
		value.add_theme_color_override("font_color",
			Palette.GOOD if entry[1] >= 0.0 else Palette.DANGER)
		row.add_child(value)
		rows.add_child(row)

	if org.ideology != null:
		var ideology := Label.new()
		ideology.text = "思想：%s" % PoliticalSystemGenerator.ideology_summary(org.ideology)
		ideology.add_theme_font_size_override("font_size", 16)
		ideology.add_theme_color_override("font_color", Palette.TEXT_DIM)
		rows.add_child(ideology)

	# Who stands behind it. This is the part that makes a faction more than a
	# mood: it is backed by particular families and particular trades, and those
	# are the ones that lose if it falls.
	var backers := SocialTies.backers_of(org)
	if not backers.is_empty():
		var parts: Array[String] = []
		for backer in backers.slice(0, 5):
			parts.append("%s %d%%" % [backer.formal_name(),
				int(float(org.support_base.get(backer.org_id, 0.0)) * 100.0)])
		var support := Label.new()
		support.text = "支持基盤：%s" % "　".join(parts)
		support.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		support.add_theme_font_size_override("font_size", 16)
		support.add_theme_color_override("font_color", Palette.TEXT_DIM)
		rows.add_child(support)

	var roll := GameState.leader_roll(org.org_id)
	if roll.size() >= 2:
		var names: Array[String] = []
		for i in range(roll.size() - 1, maxi(-1, roll.size() - 6), -1):
			var t: RoleTenure = roll[i]["tenure"]
			names.append("%s(%d年〜)" % [roll[i]["person"].full_name,
				int(t.start_tick / SimConfig.TICKS_PER_YEAR)])
		var history := Label.new()
		history.text = "歴代の%s：%s%s" % [org.leadership_title, "　".join(names),
			"　…全%d代" % roll.size() if roll.size() > 5 else ""]
		history.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		history.add_theme_font_size_override("font_size", 16)
		history.add_theme_color_override("font_color", Palette.TEXT_DIM)
		rows.add_child(history)

	if org.kind == Organization.OrgKind.HOUSE:
		var land: Array[String] = []
		for settlement_id in org.held_settlement_ids:
			var s: SettlementState = GameState.world.settlements.get(settlement_id)
			if s != null:
				land.append(s.display_name)
		var standing := Label.new()
		standing.text = "家格：%s　／　所領：%s" % [HouseRank.tier_name(org.rank_tier),
			"、".join(land) if not land.is_empty() else "なし"]
		standing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		standing.add_theme_font_size_override("font_size", 16)
		standing.add_theme_color_override("font_color", Palette.TEXT_DIM)
		rows.add_child(standing)

		var served := Retainers.retainers_of(org.org_id)
		if not served.is_empty():
			var parts: Array[String] = []
			for r in served:
				parts.append("%s %s" % [r.formal_name(), Retainers.describe_loyalty(r.loyalty)])
			var vassals := Label.new()
			vassals.text = "側近家：%s" % "　".join(parts)
			vassals.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vassals.add_theme_font_size_override("font_size", 16)
			vassals.add_theme_color_override("font_color", Palette.TEXT_DIM)
			rows.add_child(vassals)

	if org.kind == Organization.OrgKind.RELIGION:
		var regions: Array[String] = []
		for id in GameState.world.settlements:
			var s: SettlementState = GameState.world.settlements[id]
			if s.religion_id == org.org_id:
				regions.append(s.display_name)
		var spread := Label.new()
		spread.text = "信じる地：%s" % ("、".join(regions) if not regions.is_empty() else "なし")
		spread.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		spread.add_theme_font_size_override("font_size", 16)
		spread.add_theme_color_override("font_color", Palette.TEXT_DIM)
		rows.add_child(spread)

	return panel


func _on_row_pressed(org_id: StringName) -> void:
	_expanded = &"" if _expanded == org_id else org_id
	_rebuild()

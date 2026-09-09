extends Control

## Who holds influence, and why. Tapping a bar opens the breakdown, which is the
## point: it names the world conditions the player created that put this
## organization where it is.

const KIND_FILTERS := [
	{"label": "すべて", "kind": -1},
	{"label": "政体", "kind": Organization.OrgKind.POLITICAL_SYSTEM},
	{"label": "ギルド", "kind": Organization.OrgKind.GUILD},
	{"label": "派閥", "kind": Organization.OrgKind.FACTION},
	{"label": "家", "kind": Organization.OrgKind.HOUSE},
	{"label": "信仰", "kind": Organization.OrgKind.RELIGION},
]

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
		button.custom_minimum_size = Vector2(0, 44)
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
		var button: Button = _tabs.get_child(i)
		var active: bool = KIND_FILTERS[i]["kind"] == _filter
		button.button_pressed = active
		button.add_theme_color_override("font_color",
			Palette.ACCENT if active else Palette.TEXT_MUTED)


func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()

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
	for org in ranked:
		_list.add_child(_row(org, strongest))
		if org.org_id == _expanded:
			_list.add_child(_breakdown(org))


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
	heading.text = "%s　—　%s" % [polity.display_name,
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

	# The division of the chamber is what a faction amounts to under a regime that
	# has one, and it is also what the next upheaval will be decided on.
	var seated := SocialTies.seat_order(polity)
	if not seated.is_empty():
		var parts: Array[String] = []
		for faction in seated.slice(0, 4):
			parts.append("%s %d" % [faction.display_name,
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
			challenge["org"].display_name, int(float(challenge.get("hold", 0.0)) * 100.0)]
		pressure.add_theme_color_override("font_color", Palette.DANGER)
	pressure.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pressure.add_theme_font_size_override("font_size", 15)
	rows.add_child(pressure)
	return panel


func _row(org: Organization, strongest: float) -> Control:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 62)
	button.focus_mode = Control.FOCUS_NONE
	button.flat = true
	button.pressed.connect(_on_row_pressed.bind(org.org_id))

	var bar := ColorRect.new()
	bar.color = Palette.for_kind(org.kind)
	bar.color.a = 0.22
	bar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	bar.anchor_right = clampf(org.power_score / strongest, 0.02, 1.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(bar)

	var accent := ColorRect.new()
	accent.color = Palette.for_kind(org.kind)
	accent.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	accent.offset_right = 4.0
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(accent)

	var name_label := Label.new()
	name_label.text = org.display_name
	name_label.position = Vector2(14, 8)
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Palette.TEXT)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(name_label)

	var leader := GameState.get_current_leader(org.org_id)
	var sub := Label.new()
	sub.text = "%s・%d名　%s%s" % [_kind_note(org), org.member_count,
		leader.full_name if leader != null else "指導者不在", _house_note(org)]
	sub.position = Vector2(14, 34)
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(sub)

	var score := Label.new()
	score.text = "%d" % int(org.power_score)
	score.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	score.position = Vector2(-64, 14)
	score.custom_minimum_size = Vector2(54, 0)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score.add_theme_font_size_override("font_size", 26)
	score.add_theme_color_override("font_color", Palette.ACCENT)
	score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(score)
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
			"／%s" % liege.display_name if liege != null else ""]
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
		return "%s・%s(%s)" % [base, SocialTies.office_basis_label(org), patron.display_name]
	return "%s・%s" % [base, SocialTies.office_basis_label(org)]


## Names each world condition feeding this organization's influence, so a player
## can trace a rise back to the dial they turned.
func _breakdown(org: Organization) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.PANEL
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
			parts.append("%s %d%%" % [backer.display_name,
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
				parts.append("%s %s" % [r.display_name, Retainers.describe_loyalty(r.loyalty)])
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

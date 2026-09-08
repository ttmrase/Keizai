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

	var strongest: float = maxf(1.0, ranked[0].power_score)
	for org in ranked:
		_list.add_child(_row(org, strongest))
		if org.org_id == _expanded:
			_list.add_child(_breakdown(org))


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
	sub.text = "%s・%d名　%s" % [Palette.kind_label(org.kind), org.member_count,
		leader.full_name if leader != null else "指導者不在"]
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

	return panel


func _on_row_pressed(org_id: StringName) -> void:
	_expanded = &"" if _expanded == org_id else org_id
	_rebuild()

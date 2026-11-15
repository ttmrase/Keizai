extends Control

## Hosts the three lineage views. They share one graph widget and differ only in
## the data source, so focus, search and the jump to the root behave identically
## in all of them.
##
## Families are on their own screen rather than beside the institutions: eight
## houses with three retainer families each, branching for four centuries, is
## most of the tree, and putting it next to the guilds and faiths leaves those
## squeezed into a corner of a chart that is mostly surnames.

enum Mode { INSTITUTIONS, HOUSES, PEOPLE, GREATS, DOCTRINES }

var _institution_source := OrganizationLineageSource.new()
var _house_source := OrganizationLineageSource.new()
var _people_source := GenealogySource.new()
## The same family chart narrowed to one house. Empty means the whole world.
var _house_tree_source := HouseGenealogySource.new()
## 思想 — the lineage of doctrines, apart from any organization.
var _doctrine_source := DoctrineLineageSource.new()
var _focus_house: StringName = &""
var _mode := Mode.INSTITUTIONS
## People view only: draw the heads of houses, without everyone who married in.
var _spine_only := true

@onready var _graph: LineageGraphView = $Graph
@onready var _org_button: Button = $Top/Modes/Orgs
@onready var _house_button: Button = $Top/Modes/Houses
@onready var _people_button: Button = $Top/Modes/People
@onready var _scope_button: Button = $Top/SearchRow/Scope
@onready var _search: LineEdit = $Top/SearchRow/Search
@onready var _root_button: Button = $Top/SearchRow/ToRoot
@onready var _results: PanelContainer = $Results
@onready var _results_list: VBoxContainer = $Results/Scroll/List
@onready var _detail: PanelContainer = $Detail
@onready var _detail_title: Label = $Detail/Margin/Rows/Title
@onready var _detail_body: RichTextLabel = $Detail/Margin/Rows/Scroll/Body
@onready var _focus_note: Label = $Top/NoteRow/FocusNote
@onready var _clear_house_button: Button = $Top/NoteRow/ClearHouse
@onready var _rename_button: Button = $Detail/Margin/Rows/Actions/Rename
@onready var _house_tree_button: Button = $Detail/Margin/Rows/Actions/HouseTree

var _rename_dialog: RenameDialog
## Families screen only: narrows the chart to one 氏.
var _uji_button: Button
## The fourth view: the hall of the people history keeps, shelf by field.
var _greats_button: Button
var _doctrine_button: Button
var _hall: ScrollContainer
var _hall_rows: VBoxContainer


func _ready() -> void:
	_house_source.root_kinds = [Organization.OrgKind.HOUSE]
	_greats_button = _people_button.duplicate()
	_greats_button.text = "偉人"
	_people_button.get_parent().add_child(_greats_button)
	_greats_button.pressed.connect(_show_greats)
	_doctrine_button = _people_button.duplicate()
	_doctrine_button.text = "思想"
	_people_button.get_parent().add_child(_doctrine_button)
	_doctrine_button.pressed.connect(_show_doctrines)
	_hall = ScrollContainer.new()
	_hall.visible = false
	_hall.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_hall.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hall.offset_top = 62.0
	_hall.offset_left = 12.0
	_hall.offset_right = -12.0
	add_child(_hall)
	move_child(_hall, $Top.get_index())
	_hall_rows = VBoxContainer.new()
	_hall_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hall_rows.add_theme_constant_override("separation", 10)
	_hall.add_child(_hall_rows)
	_uji_button = Button.new()
	_uji_button.custom_minimum_size = Vector2(80, 44)
	_uji_button.add_theme_font_size_override("font_size", 15)
	_uji_button.focus_mode = Control.FOCUS_NONE
	_uji_button.text = "氏"
	_uji_button.pressed.connect(_open_uji_picker)
	_scope_button.get_parent().add_child(_uji_button)
	_scope_button.get_parent().move_child(_uji_button, _scope_button.get_index())
	_org_button.pressed.connect(_show_institutions)
	_house_button.pressed.connect(_show_houses)
	_people_button.pressed.connect(_show_all_people)
	_scope_button.pressed.connect(_toggle_scope)
	_root_button.pressed.connect(_jump_to_root)
	_clear_house_button.pressed.connect(_show_all_people)
	_house_tree_button.pressed.connect(_open_house_tree)
	_search.text_submitted.connect(_run_search)
	_search.text_changed.connect(_on_search_changed)
	_graph.node_selected.connect(_on_node_selected)
	_graph.node_long_pressed.connect(_on_node_long_pressed)
	EventBus.game_loaded.connect(_rebuild)
	EventBus.world_reset.connect(_rebuild)

	_rename_dialog = RenameDialog.new()
	add_child(_rename_dialog)
	_rename_dialog.name_applied.connect(_on_renamed)
	_rename_button.pressed.connect(_on_rename_pressed)

	_detail.visible = false
	_results.visible = false
	_show_institutions()


## Only organizations carry a name of their own — a person's surname belongs to
## their house, so renaming the house is what renames them.
func _on_rename_pressed() -> void:
	if _mode == Mode.PEOPLE:
		return
	var org := GameState.get_organization(_graph.selected_id)
	if org != null:
		_rename_dialog.open_for_organization(org.org_id, org.display_name)


func _on_renamed(_subject_id: StringName) -> void:
	_graph.rebuild()
	if _graph.selected_id != &"":
		_show_detail(_graph.selected_id)


func on_shown() -> void:
	_rebuild()


func _show_greats() -> void:
	_mode = Mode.GREATS
	_sync_modes()
	_rebuild()


func _show_doctrines() -> void:
	_mode = Mode.DOCTRINES
	_graph.set_source(_doctrine_source)
	_graph.spine_mode = false
	_search.placeholder_text = "思想を探す"
	_sync_modes()
	_rebuild()


func _show_institutions() -> void:
	_mode = Mode.INSTITUTIONS
	_graph.set_source(_institution_source)
	_graph.spine_mode = false
	_search.placeholder_text = "組織を探す"
	_sync_modes()
	_rebuild()


func _show_houses() -> void:
	_mode = Mode.HOUSES
	_graph.set_source(_house_source)
	_graph.spine_mode = false
	_search.placeholder_text = "家を探す"
	_sync_modes()
	_rebuild()


## The 人物 tab always means the whole family, so reaching for it is also how a
## reader gets back out of one house's chart.
func _show_all_people() -> void:
	_focus_house = &""
	_show_people()


func _show_people() -> void:
	_mode = Mode.PEOPLE
	_house_tree_source.house_id = _focus_house
	_graph.set_source(_people_source if _focus_house == &"" else _house_tree_source)
	_graph.spine_mode = _spine_only
	_search.placeholder_text = "人物を探す"
	_sync_modes()
	_rebuild()


## Opens the selected house's own family chart: the people who carry its name,
## and the spouses who married into it. Reached from the house itself, because
## that is where a reader is when they want it.
func _open_house_tree() -> void:
	if _mode != Mode.HOUSES:
		return
	var house := GameState.get_organization(_graph.selected_id)
	if house == null or house.kind != Organization.OrgKind.HOUSE:
		return
	_focus_house = house.org_id
	_show_people()


## The whole record at once is a wall of boxes; the line of house heads is a
## chart. Both are one tap apart, and tapping anybody opens their own lineage in
## full either way. On the family screen the same button hides the households in
## service, which are three quarters of the families in the world.
func _toggle_scope() -> void:
	match _mode:
		Mode.HOUSES:
			_house_source.include_retainers = not _house_source.include_retainers
		Mode.PEOPLE:
			_spine_only = not _spine_only
			_graph.spine_mode = _spine_only
		_:
			return
	_graph.clear_focus()
	_sync_modes()
	_rebuild()


## Whoever currently holds the most influential seat — the natural way in.
func _most_notable_living() -> StringName:
	var best := &""
	var best_power := -1.0
	for org in GameState.active_organizations():
		var leader := GameState.get_current_leader(org.org_id)
		if leader == null or not leader.is_alive():
			continue
		if org.power_score > best_power:
			best_power = org.power_score
			best = leader.person_id
	return best


func _sync_modes() -> void:
	for entry in [[_org_button, Mode.INSTITUTIONS], [_house_button, Mode.HOUSES],
			[_people_button, Mode.PEOPLE], [_greats_button, Mode.GREATS],
			[_doctrine_button, Mode.DOCTRINES]]:
		Palette.style_pill(entry[0], _mode == entry[1])
	var hall := _mode == Mode.GREATS
	_hall.visible = hall
	_graph.visible = not hall
	$Top/SearchRow.visible = not hall
	$Top/NoteRow.visible = not hall
	if hall:
		_detail.visible = false
		_results.visible = false

	_scope_button.visible = _mode != Mode.INSTITUTIONS and _mode != Mode.DOCTRINES \
		and not (_mode == Mode.HOUSES and _house_source.uji_filter != &"")
	_uji_button.visible = _mode == Mode.HOUSES
	_uji_button.text = "氏" if _house_source.uji_filter == &"" \
		else "%s ✕" % HouseNaming.uji_label(_house_source.uji_filter)
	Palette.style_pill(_uji_button, _house_source.uji_filter != &"")
	_clear_house_button.visible = _mode == Mode.PEOPLE and _focus_house != &""
	match _mode:
		Mode.HOUSES:
			_scope_button.text = "側近家も" if not _house_source.include_retainers else "主家のみ"
		Mode.PEOPLE:
			_scope_button.text = "全員" if _spine_only else "当主のみ"


func _rebuild() -> void:
	if _mode == Mode.GREATS:
		_build_hall()
		return
	_graph.rebuild()
	if not _graph.is_focused():
		_graph.frame_all()
	_update_focus_note()
	if _graph.selected_id != &"":
		_show_detail(_graph.selected_id)
	else:
		# Switching views drops the selection, and a sheet describing whatever was
		# open in the last one is worse than no sheet at all.
		_detail.visible = false


func _update_focus_note() -> void:
	var focused: bool = _graph.is_focused()
	_root_button.text = "全体へ" if focused else "源流へ"
	_focus_note.visible = true
	if _graph.is_kin_focus():
		_focus_note.text = "個人の系図：源流までの直系と、その各代のきょうだいまでを表示しています"
	elif focused:
		_focus_note.text = "焦点表示中：選んだ相手とその前後の代だけを表示しています"
	elif _mode == Mode.PEOPLE and _focus_house != &"":
		var house := GameState.get_organization(_focus_house)
		_focus_note.text = "%sの家系図：嫁いできた配偶者を含み、他家へ出た人は除いています" \
			% (house.formal_name() if house != null else "この家")
	elif _mode == Mode.PEOPLE and _spine_only:
		_focus_note.text = "当主のみ表示中：長押しでその人の系図が開きます"
	elif _mode == Mode.PEOPLE:
		_focus_note.text = "長押しでその人の系図が開きます"
	elif _mode == Mode.HOUSES and _house_source.uji_filter != &"":
		_focus_note.text = "%s：宗家と、そこから出たすべての家（側近家を含む）" \
			% HouseNaming.uji_summary(_house_source.uji_filter)
	elif _mode == Mode.HOUSES and not _house_source.include_retainers:
		_focus_note.text = "主家のみ表示中：側近家は「側近家も」で開きます"
	elif _mode == Mode.DOCTRINES and Doctrines.all().is_empty():
		_focus_note.text = "まだ思想は生まれていない。ある程度自由な国か、優れた治世から生まれる"
	elif _mode == Mode.DOCTRINES:
		_focus_note.text = "線の色は生まれ方：灰=発展 橙=分派 赤=反動 緑=総合 金=復興 青=治世から。淡い札は廃れた思想"
	else:
		_focus_note.visible = false


func _current_source() -> LineageSource:
	match _mode:
		Mode.HOUSES:
			return _house_source
		Mode.PEOPLE:
			return _people_source if _focus_house == &"" else _house_tree_source
		Mode.DOCTRINES:
			return _doctrine_source
	return _institution_source


func _on_search_changed(text: String) -> void:
	if text.strip_edges().is_empty():
		_results.visible = false


func _run_search(query: String) -> void:
	for child in _results_list.get_children():
		child.queue_free()

	var hits := _current_source().search(query)
	if hits.is_empty():
		_results.visible = false
		return

	for id in hits.slice(0, 12):
		var button := Button.new()
		button.text = "%s　%s" % [_current_source().label(id), _current_source().sublabel(id)]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 48)
		button.add_theme_font_size_override("font_size", 17)
		button.pressed.connect(_on_result_chosen.bind(id))
		_results_list.add_child(button)
	_results.visible = true


func _on_result_chosen(id: StringName) -> void:
	_results.visible = false
	_search.text = ""
	_graph.focus_on(id)
	_update_focus_note()
	_show_detail(id)


## Opens whichever chart holds this person or organization, centred on them and
## with their record open. It is how the chronicle and the news point at whoever
## they are talking about, so the reader never has to go and search for them.
func reveal(id: StringName) -> void:
	_results.visible = false
	if Doctrines.get_doctrine(id) != null:
		_show_doctrines()
		_graph.focus_on(id)
	elif GameState.get_person(id) != null:
		_focus_house = &""
		_show_people()
		_graph.focus_on_kin(id)
	else:
		var org := GameState.get_organization(id)
		if org == null:
			return
		if org.kind == Organization.OrgKind.HOUSE:
			if _house_source.uji_filter != &"" and org.uji_id != _house_source.uji_filter:
				_house_source.uji_filter = &""
			if org.standing == Organization.Standing.RETAINER:
				_house_source.include_retainers = true
			_show_houses()
		else:
			_show_institutions()
		_graph.focus_on(id)
	_graph.selected_id = id
	_update_focus_note()
	_show_detail(id)


## The families screen narrowed to one 氏, or widened back out. Lists the 氏 in
## the same panel search results use, so it reads the same and closes the same.
func _open_uji_picker() -> void:
	if _house_source.uji_filter != &"":
		_set_uji_filter(&"")
		return
	for child in _results_list.get_children():
		child.queue_free()
	for uji_id in HouseNaming.all_uji():
		var button := Button.new()
		button.text = HouseNaming.uji_summary(uji_id)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 48)
		button.add_theme_font_size_override("font_size", 17)
		button.pressed.connect(_set_uji_filter.bind(uji_id))
		_results_list.add_child(button)
	_results.visible = true


func _set_uji_filter(uji_id: StringName) -> void:
	_results.visible = false
	_house_source.uji_filter = uji_id
	_graph.clear_focus()
	_graph.selected_id = &""
	_sync_modes()
	_rebuild()


# -------------------------------------------------------------- the hall

## 偉人 — the people later history keeps, shelf by field. A field nobody has yet
## earned shows, faintly, what it would take.
func _build_hall() -> void:
	for child in _hall_rows.get_children():
		child.queue_free()
	var total := Greatness.all().size()
	var head := Label.new()
	head.text = "後の世に名を残した者　%d人" % total if total > 0 \
		else "まだ誰も、歴史に名を刻んでいない"
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	_hall_rows.add_child(head)
	for field in Greatness.FIELDS:
		_hall_rows.add_child(_shelf_heading(field))
		var entries := Greatness.in_field(field)
		if entries.is_empty():
			var hint := Label.new()
			hint.text = "まだ誰もいない——%s" % Greatness.FIELD_HINTS[field]
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.add_theme_font_size_override("font_size", 14)
			hint.add_theme_color_override("font_color", Palette.TEXT_DIM)
			_hall_rows.add_child(hint)
			continue
		for entry in entries:
			_hall_rows.add_child(_great_card(entry))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	_hall_rows.add_child(gap)


func _shelf_heading(field: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	var box := VBoxContainer.new()
	box.add_child(gap)
	box.add_child(row)
	row.add_child(GlyphIcon.make(Greatness.FIELD_GLYPHS[field], Palette.ACCENT, 26))
	var label := Label.new()
	label.text = Greatness.field_label(field)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Palette.ACCENT)
	row.add_child(label)
	var count := Label.new()
	count.text = "%d人" % Greatness.in_field(field).size()
	count.add_theme_font_size_override("font_size", 15)
	count.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	row.add_child(count)
	var rule := ColorRect.new()
	rule.color = Color(Palette.ACCENT, 0.3)
	rule.custom_minimum_size = Vector2(0, 1)
	box.add_child(rule)
	return box


func _great_card(entry: Dictionary) -> Control:
	var person := GameState.get_person(StringName(entry["person_id"]))
	var card := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.PANEL_RAISED
	box.border_color = Color(Palette.ACCENT, 0.55)
	box.border_width_left = 3
	box.set_corner_radius_all(10)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var house_id := &""
	if person != null:
		house_id = person.house_org_id if person.house_org_id != &"" else person.birth_house_org_id
	var shield := CrestIcon.make(house_id, 44)
	shield.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(shield)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 1)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	var uji := HouseNaming.person_uji_line(person)
	if not uji.is_empty():
		var over := Label.new()
		over.text = uji
		over.add_theme_font_size_override("font_size", 13)
		over.add_theme_color_override("font_color", Palette.ACCENT_SOFT.lightened(0.2))
		words.add_child(over)
	var name := Label.new()
	name.text = "%s　「%s」" % [person.short_name if person != null else "?", entry["title"]]
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.add_theme_font_size_override("font_size", 19)
	name.add_theme_color_override("font_color", Palette.TEXT)
	words.add_child(name)
	if person != null:
		var life := Label.new()
		life.text = "%d年〜%s　・　%d年に列す" % [int(person.birth_tick / SimConfig.TICKS_PER_YEAR),
			"存命" if person.is_alive() else "%d年" % int(person.death_tick / SimConfig.TICKS_PER_YEAR),
			int(int(entry["tick"]) / SimConfig.TICKS_PER_YEAR)]
		life.add_theme_font_size_override("font_size", 13)
		life.add_theme_color_override("font_color", Palette.TEXT_MUTED)
		words.add_child(life)
	var text := Label.new()
	text.text = entry["text"]
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 15)
	text.add_theme_color_override("font_color", Palette.TEXT)
	words.add_child(text)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var id := StringName(entry["person_id"])
	card.gui_input.connect(func(event: InputEvent):
		if Touch.tapped(card, event) and GameState.get_person(id) != null:
			reveal(id))
	return card


## Walks up to where this lineage began — the point of the whole design, so it
## gets a permanent button rather than being buried.
func _jump_to_root() -> void:
	if _graph.is_focused():
		_graph.clear_focus()
		_update_focus_note()
		return

	var id := _graph.selected_id
	if id == &"":
		_graph.frame_all()
		return
	var root_id := &""
	if _mode == Mode.DOCTRINES:
		var walk := Doctrines.get_doctrine(id)
		while walk != null and walk.parent_id != &"":
			walk = Doctrines.get_doctrine(walk.parent_id)
		root_id = walk.doctrine_id if walk != null else &""
	elif _mode != Mode.PEOPLE:
		var root := GenealogyValidator.root_ancestor(id)
		if root != null:
			root_id = root.org_id
	elif _focus_house != &"":
		# Inside one house the source of the line is that house's own earliest
		# member; the world's founders are somebody else's chart.
		root_id = _earliest_of(_house_tree_source.roots())
	else:
		var founder := GenealogyValidator.founder_of(id)
		if founder != null:
			root_id = founder.person_id
	if root_id != &"":
		_graph.selected_id = root_id
		_graph.center_on_node(root_id)
		_show_detail(root_id)
		_graph.queue_redraw()


func _earliest_of(ids: Array[StringName]) -> StringName:
	var best := &""
	var best_tick := 1 << 62
	for id in ids:
		var p := GameState.get_person(id)
		if p != null and p.birth_tick < best_tick:
			best_tick = p.birth_tick
			best = id
	return best


## Holding a person opens their own chart rather than selecting them: the line
## they descend from, and everyone one step off it at every generation.
func _on_node_long_pressed(id: StringName) -> void:
	if id == &"":
		return
	if _mode == Mode.PEOPLE:
		_graph.focus_on_kin(id)
	else:
		_graph.focus_on(id)
	_update_focus_note()
	_show_detail(id)


func _on_node_selected(id: StringName) -> void:
	if id == &"":
		_detail.visible = false
		return
	_show_detail(id)


func _show_detail(id: StringName) -> void:
	var source := _current_source()
	if not source.exists(id):
		_detail.visible = false
		return
	var person := GameState.get_person(id)
	var org := GameState.get_organization(id)
	_detail_title.text = person.full_name if person != null \
		else (org.formal_name() if org != null else source.label(id))
	_detail_body.text = source.detail(id)
	_rename_button.visible = _mode != Mode.PEOPLE and _mode != Mode.DOCTRINES
	_house_tree_button.visible = _mode == Mode.HOUSES
	_detail.visible = true

extends Control

## Hosts the three lineage views. They share one graph widget and differ only in
## the data source, so focus, search and the jump to the root behave identically
## in all of them.
##
## Families are on their own screen rather than beside the institutions: eight
## houses with three retainer families each, branching for four centuries, is
## most of the tree, and putting it next to the guilds and faiths leaves those
## squeezed into a corner of a chart that is mostly surnames.

enum Mode { INSTITUTIONS, HOUSES, PEOPLE }

var _institution_source := OrganizationLineageSource.new()
var _house_source := OrganizationLineageSource.new()
var _people_source := GenealogySource.new()
## The same family chart narrowed to one house. Empty means the whole world.
var _house_tree_source := HouseGenealogySource.new()
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


func _ready() -> void:
	_house_source.root_kinds = [Organization.OrgKind.HOUSE]
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
			[_people_button, Mode.PEOPLE]]:
		var button: Button = entry[0]
		var active: bool = _mode == entry[1]
		button.button_pressed = active
		button.add_theme_color_override("font_color",
			Palette.ACCENT if active else Palette.TEXT_MUTED)

	_scope_button.visible = _mode != Mode.INSTITUTIONS
	_clear_house_button.visible = _mode == Mode.PEOPLE and _focus_house != &""
	match _mode:
		Mode.HOUSES:
			_scope_button.text = "側近家も" if not _house_source.include_retainers else "主家のみ"
		Mode.PEOPLE:
			_scope_button.text = "全員" if _spine_only else "当主のみ"


func _rebuild() -> void:
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
			% (house.display_name if house != null else "この家")
	elif _mode == Mode.PEOPLE and _spine_only:
		_focus_note.text = "当主のみ表示中：長押しでその人の系図が開きます"
	elif _mode == Mode.PEOPLE:
		_focus_note.text = "長押しでその人の系図が開きます"
	elif _mode == Mode.HOUSES and not _house_source.include_retainers:
		_focus_note.text = "主家のみ表示中：側近家は「側近家も」で開きます"
	else:
		_focus_note.visible = false


func _current_source() -> LineageSource:
	match _mode:
		Mode.HOUSES:
			return _house_source
		Mode.PEOPLE:
			return _people_source if _focus_house == &"" else _house_tree_source
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
	if _mode != Mode.PEOPLE:
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
	_detail_title.text = source.label(id)
	_detail_body.text = source.detail(id)
	_rename_button.visible = _mode != Mode.PEOPLE
	_house_tree_button.visible = _mode == Mode.HOUSES
	_detail.visible = true

extends Control

## Hosts both lineage trees. They share one graph widget and differ only in the
## data source, so focus, collapse and search behave identically in both.

var _org_source := OrganizationLineageSource.new()
var _people_source := GenealogySource.new()
var _showing_orgs := true

@onready var _graph: LineageGraphView = $Graph
@onready var _org_button: Button = $Top/Modes/Orgs
@onready var _people_button: Button = $Top/Modes/People
@onready var _search: LineEdit = $Top/SearchRow/Search
@onready var _root_button: Button = $Top/SearchRow/ToRoot
@onready var _results: PanelContainer = $Results
@onready var _results_list: VBoxContainer = $Results/Scroll/List
@onready var _detail: PanelContainer = $Detail
@onready var _detail_title: Label = $Detail/Margin/Rows/Title
@onready var _detail_body: RichTextLabel = $Detail/Margin/Rows/Scroll/Body
@onready var _focus_note: Label = $Top/FocusNote


func _ready() -> void:
	_org_button.pressed.connect(_show_orgs)
	_people_button.pressed.connect(_show_people)
	_root_button.pressed.connect(_jump_to_root)
	_search.text_submitted.connect(_run_search)
	_search.text_changed.connect(_on_search_changed)
	_graph.node_selected.connect(_on_node_selected)
	EventBus.game_loaded.connect(_rebuild)
	EventBus.world_reset.connect(_rebuild)

	_detail.visible = false
	_results.visible = false
	_show_orgs()


func on_shown() -> void:
	_rebuild()


func _show_orgs() -> void:
	_showing_orgs = true
	_graph.set_source(_org_source)
	_search.placeholder_text = "組織を探す"
	_sync_modes()
	_rebuild()


func _show_people() -> void:
	_showing_orgs = false
	_graph.set_source(_people_source)
	_search.placeholder_text = "人物を探す"
	_sync_modes()
	_rebuild()
	# Hundreds of people at once is a wall of boxes. Open on someone who matters
	# and let the player walk outward from there.
	var subject := _most_notable_living()
	if subject != &"":
		_graph.focus_on(subject)
		_update_focus_note()
		_show_detail(subject)


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
	_org_button.button_pressed = _showing_orgs
	_people_button.button_pressed = not _showing_orgs
	_org_button.add_theme_color_override("font_color",
		Palette.ACCENT if _showing_orgs else Palette.TEXT_MUTED)
	_people_button.add_theme_color_override("font_color",
		Palette.TEXT_MUTED if _showing_orgs else Palette.ACCENT)


func _rebuild() -> void:
	_graph.rebuild()
	if not _graph.is_focused():
		_graph.frame_all()
	_update_focus_note()
	if _graph.selected_id != &"":
		_show_detail(_graph.selected_id)


func _update_focus_note() -> void:
	var focused: bool = _graph.is_focused()
	_root_button.text = "全体へ" if focused else "源流へ"
	_focus_note.visible = focused
	if focused:
		_focus_note.text = "焦点表示中：選んだ相手とその前後の代だけを表示しています"


func _current_source() -> LineageSource:
	return _org_source if _showing_orgs else _people_source


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
	if _showing_orgs:
		var root := GenealogyValidator.root_ancestor(id)
		if root != null:
			root_id = root.org_id
	else:
		var founder := GenealogyValidator.founder_of(id)
		if founder != null:
			root_id = founder.person_id
	if root_id != &"":
		_graph.selected_id = root_id
		_graph.center_on_node(root_id)
		_show_detail(root_id)
		_graph.queue_redraw()


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
	_detail.visible = true

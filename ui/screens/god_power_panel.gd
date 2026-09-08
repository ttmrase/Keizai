extends Control

## Everything the player can actually do. Four dials that shape what the world
## provides, and a set of one-off calamities and blessings.
##
## Note what is not here: no way to name a ruler, back a faction, or force a
## split. Whatever the society does with any of this, it decides on its own.

const DIALS := [
	{"label": "鉱石", "get": "ore_supply_rate", "set": "set_ore_supply_rate", "max": 3.0,
		"hint": "採れる鉱石の量。職人と商人の力の源。"},
	{"label": "木材", "get": "wood_supply_rate", "set": "set_wood_supply_rate", "max": 3.0,
		"hint": "森の恵み。交易の元手になる。"},
	{"label": "収穫", "get": "harvest_rate_modifier", "set": "set_harvest_modifier", "max": 2.0,
		"hint": "実りの豊かさ。凶作は飢えと不満を招く。"},
	{"label": "魔物", "get": "monster_spawn_rate", "set": "set_monster_spawn_rate", "max": 3.0,
		"hint": "魔物の湧く勢い。脅威は武を尊ぶ者を押し上げる。"},
]

var _sliders: Array[HSlider] = []
var _values: Array[Label] = []

@onready var _dial_rows: VBoxContainer = $Scroll/Rows/Dials
@onready var _disaster_grid: GridContainer = $Scroll/Rows/Disasters
@onready var _confirm: ConfirmationDialog = $Confirm

var _pending_disaster: StringName = &""


func _ready() -> void:
	_build_dials()
	_build_disasters()
	_confirm.confirmed.connect(_on_confirmed)
	EventBus.game_loaded.connect(_sync_dials)
	EventBus.world_reset.connect(_sync_dials)
	_sync_dials()


func on_shown() -> void:
	_sync_dials()


func _build_dials() -> void:
	for i in DIALS.size():
		var dial: Dictionary = DIALS[i]
		var block := VBoxContainer.new()
		block.add_theme_constant_override("separation", 2)

		var header := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = dial["label"]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 21)
		name_label.add_theme_color_override("font_color", Palette.TEXT)
		header.add_child(name_label)

		var value := Label.new()
		value.add_theme_font_size_override("font_size", 19)
		value.add_theme_color_override("font_color", Palette.ACCENT)
		header.add_child(value)
		_values.append(value)
		block.add_child(header)

		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = dial["max"]
		slider.step = 0.05
		slider.custom_minimum_size = Vector2(0, 44)
		slider.value_changed.connect(_on_dial_changed.bind(i))
		block.add_child(slider)
		_sliders.append(slider)

		var hint := Label.new()
		hint.text = dial["hint"]
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_font_size_override("font_size", 15)
		hint.add_theme_color_override("font_color", Palette.TEXT_DIM)
		block.add_child(hint)

		_dial_rows.add_child(block)


func _build_disasters() -> void:
	for definition in GodPowerAPI.available_disasters():
		var button := Button.new()
		button.text = definition.display_name
		button.custom_minimum_size = Vector2(0, 56)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 18)
		button.add_theme_color_override("font_color",
			Palette.GOOD if definition.is_benevolent else Palette.DANGER)
		button.pressed.connect(_on_disaster_pressed.bind(definition))
		_disaster_grid.add_child(button)


func _on_dial_changed(value: float, index: int) -> void:
	GodPowerAPI.call(DIALS[index]["set"], value)
	_values[index].text = "%.2f" % value


func _sync_dials() -> void:
	for i in _sliders.size():
		var current: float = GodPowerAPI.get_dial(DIALS[i]["get"])
		_sliders[i].set_value_no_signal(current)
		_values[i].text = "%.2f" % current


func _on_disaster_pressed(definition: DisasterDefinition) -> void:
	_pending_disaster = definition.definition_id
	_confirm.title = definition.display_name
	_confirm.dialog_text = "%s\n\n%d季にわたり世界に及ぶ。よろしいか。" % [
		definition.chronicle_template.replace("{name}", definition.display_name)
			.replace("{place}", "世界"),
		definition.duration_ticks]
	_confirm.popup_centered()


func _on_confirmed() -> void:
	if _pending_disaster == &"":
		return
	GodPowerAPI.trigger_disaster(_pending_disaster, &"", 1.0)
	_pending_disaster = &""

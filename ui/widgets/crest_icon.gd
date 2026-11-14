class_name CrestIcon
extends Control

## A house's arms in a box, for putting a shield inside a container.

var house_id: StringName = &"":
	set(value):
		house_id = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var house := GameState.get_organization(house_id)
	if house != null:
		Crest.draw(self, house, size * 0.5, minf(size.x, size.y) * 0.96, not house.is_active())


static func make(id: StringName, side: float) -> CrestIcon:
	var icon := CrestIcon.new()
	icon.house_id = id
	icon.custom_minimum_size = Vector2(side, side)
	return icon

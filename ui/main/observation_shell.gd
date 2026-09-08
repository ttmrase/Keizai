extends Control

## Placeholder shell. Replaced by the real navigation shell and screens in the
## observation UI phase.

func _ready() -> void:
	var label := Label.new()
	label.text = "Keizai"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label)

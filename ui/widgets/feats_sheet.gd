class_name FeatsSheet
extends RefCounted

## 史録: everything this god has witnessed, across every world, and what is still
## waiting to be seen. The unseen ones are listed too — a list of what can
## happen is the best reason to go and make a world where it does.

static func open(host: Control) -> Sheet:
	var total := Feats.ALL.size()
	var seen := Oracle.unlocked_count()
	var sheet := Sheet.open(host, "史録　%d / %d" % [seen, total],
		"どの世界で見届けたものも、ここに残る。")
	for feat in Feats.ALL:
		sheet.body.add_child(_row(feat))
	return sheet


static func _row(feat: Dictionary) -> Control:
	var unlocked := Oracle.is_unlocked(feat["id"])
	var colour := Palette.ACCENT if unlocked else Palette.TEXT_DIM
	var card := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.PANEL_RAISED if unlocked else Palette.PANEL
	box.border_color = Color(colour, 0.6 if unlocked else 0.2)
	box.border_width_left = 3
	box.set_corner_radius_all(10)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var icon := GlyphIcon.make(feat["glyph"], colour, 30)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	row.add_child(words)
	var title := Label.new()
	title.text = feat["title"]
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Palette.TEXT if unlocked else Palette.TEXT_MUTED)
	words.add_child(title)
	var text := Label.new()
	text.text = feat["text"]
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 13)
	text.add_theme_color_override("font_color", Palette.TEXT_MUTED if unlocked else Palette.TEXT_DIM)
	words.add_child(text)
	if unlocked:
		var when: Dictionary = Oracle.unlocked_on(feat["id"])
		var stamp := Label.new()
		stamp.text = "%d年に見届けた" % int(when.get("year", 0))
		stamp.add_theme_font_size_override("font_size", 13)
		stamp.add_theme_color_override("font_color", Palette.ACCENT_SOFT)
		row.add_child(stamp)
	return card

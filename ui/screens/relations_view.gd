extends Control

## Who stands with whom.
##
## The lineage screens answer where a family came from; this one answers where it
## stands now. Great houses are placed on the ground they hold, the families in
## service orbit the house they serve, and the lines between them are the two
## relationships the world actually runs on: what the great families think of
## each other, and how far the households below them can be trusted.
##
## Everything drawn here is already computed elsewhere — HouseRelations for the
## web between the nobility, Retainers for loyalty, HouseRank for precedence.
## This is a reading of it, not a second copy.

const FIELD := Vector2(1000.0, 1450.0)
## How far a family in service sits from the one it serves.
const ORBIT := 132.0
## Relations weaker than this are not worth a line.
const RELATION_FLOOR := 0.2
## How far back everything unconnected to the chosen family is pushed. Pushed
## back rather than hidden: a relations chart that drops the rest of the world
## stops being a map of it, and the shape of the field is half the reading.
const UNLIT := 0.15
## And how far forward the ties that were chosen come.
const LIT_WIDTH := 1.8

@onready var _canvas: PannableCanvas = $Canvas
@onready var _detail: PanelContainer = $Detail
@onready var _detail_title: Label = $Detail/Margin/Rows/Title
@onready var _detail_body: RichTextLabel = $Detail/Margin/Rows/Body

var _selected_id: StringName = &""
## house id -> where it is drawn, settled once per refresh.
var _spots: Dictionary = {}
## Whoever the selected family is directly tied to, plus the family itself.
## Settled when the selection changes, because it is asked once per line drawn.
var _lit: Dictionary = {}


func _ready() -> void:
	_canvas.draw.connect(_draw_field)
	_canvas.canvas_tapped.connect(_on_tapped)
	EventBus.power_recalculated.connect(_on_recalculated)
	EventBus.game_loaded.connect(_refresh)
	EventBus.world_reset.connect(_refresh)
	_detail.visible = false
	await get_tree().process_frame
	_frame()


func on_shown() -> void:
	_refresh()
	_frame()


func _on_recalculated(_tick: int) -> void:
	if is_visible_in_tree():
		_refresh()


func _refresh() -> void:
	_settle_spots()
	_settle_lit()
	_canvas.queue_redraw()
	if _selected_id != &"":
		_show_detail(_selected_id)


func _frame() -> void:
	if _canvas.size.x < 1.0:
		return
	var fit: float = minf(_canvas.size.x / FIELD.x, _canvas.size.y / FIELD.y) * 0.92
	_canvas.view_zoom = clampf(fit, _canvas.min_zoom, _canvas.max_zoom)
	_canvas.center_on(FIELD * 0.5)


# ------------------------------------------------------------------- layout

## Great houses sit on the ground they hold; the families serving them ring the
## seat. Two houses holding the same place are nudged apart so neither is hidden
## under the other.
func _settle_spots() -> void:
	_spots.clear()
	var nobles: Array[Organization] = []
	var retainers: Array[Organization] = []
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing == Organization.Standing.NOBLE:
			nobles.append(house)
		else:
			retainers.append(house)

	var crowding := {}
	for house in nobles:
		var seat: SettlementState = GameState.world.settlements.get(_seat_of(house))
		var base: Vector2 = seat.position * FIELD if seat != null else FIELD * 0.5
		var taken: int = int(crowding.get(_seat_of(house), 0))
		crowding[_seat_of(house)] = taken + 1
		if taken > 0:
			var turn := TAU * float(taken) / 5.0
			base += Vector2(cos(turn), sin(turn)) * 74.0
		_spots[house.org_id] = base

	# Count first, then place: a house with eight families in service needs the
	# ring divided eight ways, not five, or half of them are drawn on top of each
	# other with their names in a heap.
	var household_size := {}
	for house in retainers:
		household_size[house.liege_house_id] = int(household_size.get(house.liege_house_id, 0)) + 1

	var served := {}
	for house in retainers:
		var anchor: Vector2 = _spots.get(house.liege_house_id, Vector2.ZERO)
		if anchor == Vector2.ZERO:
			var seat: SettlementState = GameState.world.settlements.get(_seat_of(house))
			anchor = seat.position * FIELD if seat != null else FIELD * 0.5
		var index: int = int(served.get(house.liege_house_id, 0))
		served[house.liege_house_id] = index + 1
		var total: int = maxi(3, int(household_size.get(house.liege_house_id, 1)))
		var angle := TAU * float(index) / float(total) - PI / 2.0
		# A crowded ring is pushed out and staggered, so the names have room.
		var reach := ORBIT + float(total) * 9.0 + (26.0 if index % 2 == 1 else 0.0)
		_spots[house.org_id] = anchor + Vector2(cos(angle), sin(angle)) * reach


## Everyone the chosen family answers to, is answered by, or has an opinion of.
func _settle_lit() -> void:
	_lit.clear()
	if _selected_id == &"":
		return
	_lit[_selected_id] = true
	var house := GameState.get_organization(_selected_id)
	if house == null:
		return
	if house.standing == Organization.Standing.RETAINER:
		if house.liege_house_id != &"":
			_lit[house.liege_house_id] = true
		return
	for retainer in Retainers.retainers_of(_selected_id):
		_lit[retainer.org_id] = true
	for id in _spots:
		var other := GameState.get_organization(id)
		if other == null or other.org_id == _selected_id:
			continue
		if other.standing != Organization.Standing.NOBLE:
			continue
		var value := (HouseRelations.relation(_selected_id, id)
			+ HouseRelations.relation(id, _selected_id)) * 0.5
		if absf(value) >= RELATION_FLOOR:
			_lit[id] = true


## A line is only worth its full weight when it is one of the chosen family's.
func _tie_is_lit(a: StringName, b: StringName) -> bool:
	return _selected_id == &"" or a == _selected_id or b == _selected_id


func _seat_of(house: Organization) -> StringName:
	if house.dynasty_seat_settlement_id != &"":
		return house.dynasty_seat_settlement_id
	return house.held_settlement_ids[0] if not house.held_settlement_ids.is_empty() else &""


func _radius_of(house: Organization) -> float:
	var base: float = 16.0 if house.standing == Organization.Standing.NOBLE else 9.0
	return base + 22.0 * clampf(house.power_score / 70.0, 0.0, 1.0)


# ------------------------------------------------------------------ drawing

func _draw_field() -> void:
	var font := _canvas.get_theme_default_font()
	# Twice over: everything the chosen family is not part of first, then its own
	# ties on top, so a lit line is never crossed out by a dim one drawn later.
	_draw_relations(false)
	_draw_allegiances(false)
	_draw_relations(true)
	_draw_allegiances(true)
	for id in _spots:
		_draw_house(GameState.get_organization(id), font)


## What the great families think of each other. Only ties strong enough to have a
## name are drawn, or the field is a ball of string.
func _draw_relations(lit_pass: bool) -> void:
	var nobles: Array[Organization] = []
	for id in _spots:
		var house := GameState.get_organization(id)
		if house != null and house.standing == Organization.Standing.NOBLE:
			nobles.append(house)

	for i in nobles.size():
		for j in range(i + 1, nobles.size()):
			var a := nobles[i]
			var b := nobles[j]
			var value := (HouseRelations.relation(a.org_id, b.org_id)
				+ HouseRelations.relation(b.org_id, a.org_id)) * 0.5
			if absf(value) < RELATION_FLOOR:
				continue
			var lit := _tie_is_lit(a.org_id, b.org_id)
			if lit != lit_pass:
				continue
			var colour: Color = Palette.GOOD if value > 0.0 else Palette.DANGER
			colour.a = clampf(absf(value), 0.25, 0.9) * (1.0 if lit else UNLIT)
			var weight := absf(value) * 5.0 * (LIT_WIDTH if lit else 1.0)
			_canvas.draw_line(_canvas.to_screen(_spots[a.org_id]),
				_canvas.to_screen(_spots[b.org_id]), colour,
				maxf(1.0, weight * _canvas.view_zoom))


## And how far the households below them can be trusted.
func _draw_allegiances(lit_pass: bool) -> void:
	for id in _spots:
		var house := GameState.get_organization(id)
		if house == null or house.standing != Organization.Standing.RETAINER:
			continue
		if not _spots.has(house.liege_house_id):
			continue
		var lit := _tie_is_lit(id, house.liege_house_id)
		if lit != lit_pass:
			continue
		var colour := Palette.severity(1.0 - house.loyalty)
		colour.a = 0.75 * (1.0 if lit else UNLIT)
		_canvas.draw_line(_canvas.to_screen(_spots[id]),
			_canvas.to_screen(_spots[house.liege_house_id]), colour,
			maxf(1.0, (2.0 * (LIT_WIDTH if lit else 1.0)) * _canvas.view_zoom))


func _draw_house(house: Organization, font: Font) -> void:
	if house == null:
		return
	var centre := _canvas.to_screen(_spots[house.org_id])
	var radius := _radius_of(house) * _canvas.view_zoom
	var noble := house.standing == Organization.Standing.NOBLE
	var fill: Color = Palette.HOUSE if noble else Palette.HOUSE.darkened(0.45)
	# A family with no part in the chosen one's affairs stays on the field, but
	# recedes into it.
	var dim: float = 1.0 if _selected_id == &"" or _lit.has(house.org_id) else 0.34

	_canvas.draw_circle(centre, radius, _shade(fill.darkened(0.4), dim))
	_canvas.draw_arc(centre, radius, 0, TAU, 28, _shade(fill, dim),
		maxf(1.0, 2.0 * _canvas.view_zoom))
	if _wears_a_crown(house):
		_canvas.draw_arc(centre, radius + 7.0 * _canvas.view_zoom, 0, TAU, 32,
			_shade(Palette.ACCENT, dim), maxf(1.0, 2.5 * _canvas.view_zoom))
	if house.org_id == _selected_id:
		_canvas.draw_arc(centre, radius + 13.0 * _canvas.view_zoom, 0, TAU, 32,
			Palette.TEXT, 2.0)

	var size := maxi(11, int((16 if noble else 12) * _canvas.view_zoom))
	var label := "%s　%s" % [house.display_name, HouseRank.title_of_house(house)] if noble \
		else house.display_name
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_canvas.draw_string(font, centre + Vector2(-width * 0.5, radius + 20.0 * _canvas.view_zoom),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
		_shade(Palette.TEXT if noble else Palette.TEXT_MUTED, dim))


## The same colour, further away.
func _shade(colour: Color, amount: float) -> Color:
	if is_equal_approx(amount, 1.0):
		return colour
	var out := colour
	out.a *= amount
	return out


func _wears_a_crown(house: Organization) -> bool:
	for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		var ruler := GameState.get_person(polity.leader_person_id)
		if ruler != null and ruler.house_org_id == house.org_id:
			return true
	return false


# ------------------------------------------------------------------ tapping

func _on_tapped(world_position: Vector2) -> void:
	var closest := &""
	var closest_distance := INF
	for id in _spots:
		var d: float = (_spots[id] as Vector2).distance_to(world_position)
		if d < closest_distance:
			closest_distance = d
			closest = id
	if closest_distance > 90.0:
		_selected_id = &""
		_settle_lit()
		_detail.visible = false
		_canvas.queue_redraw()
		return
	_selected_id = closest
	_settle_lit()
	_show_detail(closest)
	_canvas.queue_redraw()


func _show_detail(id: StringName) -> void:
	var house := GameState.get_organization(id)
	if house == null:
		_detail.visible = false
		return
	var head := GameState.get_current_leader(id)
	var lines: Array[String] = []
	lines.append("[color=#9a9080]%s[/color]  %s　%s" % [house.standing_label(),
		HouseRank.title_of_house(house), HouseCharacter.label(house.character_id)])
	lines.append("[color=#9a9080]当主[/color]  %s"
		% (head.full_name if head != null else "不在"))

	var land: Array[String] = []
	for settlement_id in house.held_settlement_ids:
		var s: SettlementState = GameState.world.settlements.get(settlement_id)
		if s != null:
			land.append(s.display_name)
	lines.append("[color=#9a9080]所領[/color]  %s"
		% ("、".join(land) if not land.is_empty() else "なし"))

	var faith := GameState.get_organization(house.faith_id)
	if faith != null:
		lines.append("[color=#9a9080]信仰[/color]  %s" % faith.display_name)

	if house.standing == Organization.Standing.RETAINER:
		var liege := GameState.get_organization(house.liege_house_id)
		lines.append("[color=#9a9080]仕える先[/color]  %s（%s・忠誠%d%%）" % [
			liege.display_name if liege != null else "なし",
			Retainers.describe_loyalty(house.loyalty), int(house.loyalty * 100.0)])
	else:
		var served := Retainers.retainers_of(id)
		if served.is_empty():
			lines.append("[color=#9a9080]側近家[/color]  なし")
		else:
			var parts: Array[String] = []
			for r in served:
				parts.append("%s（%s %d%%）" % [r.display_name,
					Retainers.describe_loyalty(r.loyalty), int(r.loyalty * 100.0)])
			lines.append("[color=#9a9080]側近家[/color]  %s" % "、".join(parts))

		var standings: Array[String] = []
		for other in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
			if other.org_id == id or other.standing != Organization.Standing.NOBLE:
				continue
			var value := HouseRelations.relation(id, other.org_id)
			if absf(value) < RELATION_FLOOR:
				continue
			standings.append("%s:%s" % [other.display_name, HouseRelations.describe(value)])
		if not standings.is_empty():
			lines.append("[color=#9a9080]他家との関係[/color]  %s" % "　".join(standings))

	_detail_title.text = house.display_name
	_detail_body.text = "\n".join(lines)
	_detail.visible = true

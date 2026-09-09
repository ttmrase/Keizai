class_name LineageGraphView
extends PannableCanvas

## Draws a lineage, either as a tidy layered tree or — for a family, which is a
## graph rather than a forest — as one chart laid out by generation.
##
## Written by hand rather than with GraphEdit: the touch handling, focus mode and
## collapsing all need to work on a phone screen, which GraphEdit's
## editor-flavoured nodes do not, and neither layout is anything GraphEdit does.

signal node_selected(id: StringName)

## Wide enough for a generated regime name — "ヴァル峠の守旧的な世襲専制" and the
## like — to fit without clipping at reading zoom.
const NODE_SIZE := Vector2(330.0, 62.0)
const H_GAP := 26.0
## Spouses sit shoulder to shoulder, close enough to read as one household.
const SPOUSE_GAP := 10.0
const ROW_HEIGHT := 116.0
const CHEVRON_WIDTH := 46.0

var source: LineageSource
var selected_id: StringName = &""

## When set, only these ids are laid out — focus mode.
var _visible_ids: Dictionary = {}
var _focus_active := false
## Draw only the line of house heads, without the people who married in. The
## whole record at once is a thousand boxes wide; this is the readable form of
## it, and any of those boxes opens the rest.
var spine_mode := false
## Whatever is being laid out this pass, for quick membership tests.
var _scope: Dictionary = {}
var _collapsed: Dictionary = {}

var _positions: Dictionary = {}      # id -> Vector2 (top-left, world space)
var _edges: Array = []               # [parent_id, child_id]
var _spouse_edges: Array = []        # [id, partner_id]
var _partner_of: Dictionary = {}     # id -> the spouse drawn beside them
## Where a node's children hang from: the midpoint of the couple, if there is one.
var _child_anchor: Dictionary = {}
var _hidden_counts: Dictionary = {}  # id -> descendants folded away
var _cursor_x := 0.0
var _bounds := Rect2()
var _row_base := 0
var _deepest_row := 0


var _needs_framing := true


func _ready() -> void:
	min_zoom = 0.18
	max_zoom = 1.8
	canvas_tapped.connect(_on_tapped)
	draw.connect(_draw_tree)
	resized.connect(_on_resized)


## The first layout happens before the control has been given a size, so framing
## it then would divide by nothing. Re-frame once a real size arrives.
func _on_resized() -> void:
	if _needs_framing and not _focus_active:
		frame_all()


func set_source(new_source: LineageSource) -> void:
	source = new_source
	_collapsed.clear()
	selected_id = &""
	clear_focus()


func rebuild() -> void:
	if source == null:
		return
	_positions.clear()
	_edges.clear()
	_spouse_edges.clear()
	_partner_of.clear()
	_child_anchor.clear()
	_hidden_counts.clear()
	_cursor_x = 0.0

	if source.is_generational():
		_layout_generational()
		_settle_bounds()
		return

	var visited := {}
	var row_roots := _layout_roots()
	# Outside focus mode the roots are four unrelated trees — one per kind of
	# institution — so they stack down the screen instead of running off the side
	# of it. In focus mode the roots are all ancestors of one subject and belong
	# on the same row.
	var stack_vertically := not _focus_active and row_roots.size() > 1
	_row_base = 0
	for root_id in row_roots:
		if stack_vertically:
			_cursor_x = 0.0
		_deepest_row = _row_base
		_place(root_id, _row_base, visited)
		if stack_vertically:
			_row_base = _deepest_row + 2

	_settle_bounds()


func _settle_bounds() -> void:
	_bounds = Rect2()
	var first := true
	for id in _positions:
		var rect := Rect2(_positions[id], NODE_SIZE)
		_bounds = rect if first else _bounds.merge(rect)
		first = false
	queue_redraw()


# ------------------------------------------------------- generational layout

## Horizontal room between two households on the same row.
const GEN_H_GAP := 34.0
## Sweeps spent reducing crossings, and then straightening descent lines. Both
## are heuristics; a couple of passes buys most of the legibility.
const ORDER_SWEEPS := 4
const PLACE_PASSES := 4
## Guard against a record where somebody is their own remote in-law, which would
## otherwise keep pushing rows down forever.
const MAX_ROW_PASSES := 16


## Lays the whole family out by generation, as one chart.
##
## The old layout drew a tree per founding couple, and a person who married into
## another house appeared twice — once beside their partner and once at the head
## of their own line — so the marriage that joined the two families read as a
## coincidence of names. Here each person belongs to exactly one household, each
## household sits on the row of its latest-born member, and the marriage lines
## are what hold the houses together.
func _layout_generational() -> void:
	var ids := _generational_ids()
	if ids.is_empty():
		return

	var unit_of := {}          # person id -> index of the household they are in
	var units: Array = []      # each entry is one or two person ids
	for id in ids:
		if unit_of.has(id):
			continue
		var members: Array[StringName] = [id]
		unit_of[id] = units.size()
		# The spine is the line of heads. The people who married into it are
		# exactly the ones it leaves out, so there is no partner to draw beside
		# anybody — which is most of what makes it readable.
		if not _spine_only():
			for spouse_id in source.spouses(id):
				if unit_of.has(spouse_id) or not _in_scope(spouse_id):
					continue
				members.append(spouse_id)
				unit_of[spouse_id] = units.size()
				break          # one partner per household keeps the row honest
		units.append(members)

	# Who each person hangs from. Usually a parent, but when the parent is not
	# being drawn — the spine skips everyone who never held a house, and focus
	# mode skips everyone outside it — the line runs to the nearest ancestor who
	# is, so the chain stays connected instead of falling apart into fragments.
	var link_parent := {}
	for id in ids:
		var anchor := _nearest_drawn_ancestor(id)
		if anchor != &"":
			link_parent[id] = anchor

	var rows := _unit_rows(units, unit_of, link_parent)
	var parents_of := {}
	var children_of := {}
	_unit_links(unit_of, link_parent, parents_of, children_of)

	var by_row := {}
	for i in units.size():
		var list: Array = by_row.get(rows[i], [])
		list.append(i)
		by_row[rows[i]] = list
	var row_keys: Array = by_row.keys()
	row_keys.sort()

	var order := _order_rows(by_row, row_keys, parents_of, children_of)
	var widths: Array[float] = []
	for i in units.size():
		widths.append(NODE_SIZE.x * units[i].size() + SPOUSE_GAP * (units[i].size() - 1))
	var x := _place_rows(by_row, row_keys, parents_of, children_of, widths)

	_commit_units(units, unit_of, rows, x, widths, ids, link_parent)


## True while the reduced view is the one being drawn. Settled once per layout in
## _generational_ids(), because it is asked once per person after that.
var _spine_active := false


func _spine_only() -> bool:
	return _spine_active


func _generational_ids() -> Array[StringName]:
	_scope.clear()
	_spine_active = false
	var out: Array[StringName] = []
	if _focus_active:
		for id in _visible_ids:
			if source.exists(id):
				out.append(id)
	elif spine_mode:
		for id in source.spine_ids():
			if source.exists(id):
				out.append(id)
		_spine_active = not out.is_empty()
	if out.is_empty():
		for id in source.all_ids():
			if source.exists(id):
				out.append(id)
	for id in out:
		_scope[id] = true
	return out


func _in_scope(id: StringName) -> bool:
	return _scope.has(id)


## The closest person above this one who is actually being drawn. In the full
## chart that is simply a parent; in the spine it may be a great-grandparent,
## because the generations in between never held anything.
const ANCESTOR_SEARCH_DEPTH := 10


func _nearest_drawn_ancestor(id: StringName) -> StringName:
	var frontier: Array = [[id, 0]]
	var seen := {}
	while not frontier.is_empty():
		var entry: Array = frontier.pop_front()
		var current: StringName = entry[0]
		var depth: int = entry[1]
		if depth > ANCESTOR_SEARCH_DEPTH or seen.has(current):
			continue
		seen[current] = true
		if depth > 0 and _in_scope(current):
			return current
		for parent_id in source.parents(current):
			frontier.append([parent_id, depth + 1])
	return &""


## A household sits one row below the household of its parents. That is not the
## same as the generation of the people in it: marrying someone a generation
## older puts the pair on one row, and their children have to clear both.
func _unit_rows(units: Array, unit_of: Dictionary, link_parent: Dictionary) -> Array[int]:
	var rows: Array[int] = []
	for members in units:
		var deepest := 0
		for member in members:
			deepest = maxi(deepest, source.generation(member))
		rows.append(deepest)

	for pass_index in MAX_ROW_PASSES:
		var moved := false
		for child_id in link_parent:
			var j: int = unit_of.get(child_id, -1)
			var i: int = unit_of.get(link_parent[child_id], -1)
			if i < 0 or j < 0 or i == j:
				continue
			if rows[j] <= rows[i]:
				rows[j] = rows[i] + 1
				moved = true
		if not moved:
			break

	var earliest := 0
	for r in rows:
		earliest = mini(earliest, r)
	if earliest != 0:
		for i in rows.size():
			rows[i] -= earliest
	return rows


func _unit_links(unit_of: Dictionary, link_parent: Dictionary, parents_of: Dictionary,
		children_of: Dictionary) -> void:
	for child_id in link_parent:
		var j: int = unit_of.get(child_id, -1)
		var i: int = unit_of.get(link_parent[child_id], -1)
		if i < 0 or j < 0 or i == j:
			continue
		var kids: Array = children_of.get(i, [])
		if not kids.has(j):
			kids.append(j)
			children_of[i] = kids
		var folks: Array = parents_of.get(j, [])
		if not folks.has(i):
			folks.append(i)
			parents_of[j] = folks


## Orders each row so lines cross as little as they cheaply can: repeatedly sort
## every row by the average position of what it connects to on the row above,
## then on the row below.
func _order_rows(by_row: Dictionary, row_keys: Array, parents_of: Dictionary,
		children_of: Dictionary) -> Dictionary:
	var order := {}
	for key in row_keys:
		var list: Array = by_row[key]
		for k in list.size():
			order[list[k]] = k

	for sweep in ORDER_SWEEPS:
		var downward := sweep % 2 == 0
		var keys: Array = row_keys.duplicate()
		if not downward:
			keys.reverse()
		var neighbours: Dictionary = parents_of if downward else children_of
		for key in keys:
			var list: Array = by_row[key]
			list.sort_custom(func(a, b):
				return _barycentre(a, neighbours, order) < _barycentre(b, neighbours, order))
			for k in list.size():
				order[list[k]] = k
			by_row[key] = list
	return order


func _barycentre(unit: int, neighbours: Dictionary, order: Dictionary) -> float:
	var linked: Array = neighbours.get(unit, [])
	if linked.is_empty():
		return float(order.get(unit, 0))
	var total := 0.0
	for other in linked:
		total += float(order.get(other, 0))
	return total / float(linked.size())


## Places each row left to right, pulling every household toward the middle of
## what it is joined to without ever letting it overtake its neighbour.
func _place_rows(by_row: Dictionary, row_keys: Array, parents_of: Dictionary,
		children_of: Dictionary, widths: Array[float]) -> Dictionary:
	var x := {}
	for key in row_keys:
		var cursor := 0.0
		for i in by_row[key]:
			x[i] = cursor
			cursor += widths[i] + GEN_H_GAP

	for pass_index in PLACE_PASSES:
		var downward := pass_index % 2 == 0
		var keys: Array = row_keys.duplicate()
		if not downward:
			keys.reverse()
		var neighbours: Dictionary = parents_of if downward else children_of
		for key in keys:
			var cursor := -INF
			var wanted := 0.0
			var placed := 0.0
			var list: Array = by_row[key]
			for i in list:
				var desired: float = _desired_x(i, neighbours, x, widths)
				var left: float = maxf(desired, cursor)
				x[i] = left
				cursor = left + widths[i] + GEN_H_GAP
				wanted += desired
				placed += left
			# Overlaps are resolved by pushing right, which on its own walks the
			# whole row further right every sweep and stretches the chart to
			# nothing. Sliding the row back onto its own centre of gravity keeps
			# the spacing that was just resolved and drops the drift.
			if not list.is_empty():
				var drift: float = (placed - wanted) / float(list.size())
				if not is_zero_approx(drift):
					for i in list:
						x[i] -= drift
	return x


func _desired_x(unit: int, neighbours: Dictionary, x: Dictionary,
		widths: Array[float]) -> float:
	var linked: Array = neighbours.get(unit, [])
	if linked.is_empty():
		return float(x.get(unit, 0.0))
	var total := 0.0
	for other in linked:
		total += float(x.get(other, 0.0)) + widths[other] * 0.5
	return total / float(linked.size()) - widths[unit] * 0.5


func _commit_units(units: Array, unit_of: Dictionary, rows: Array[int], x: Dictionary,
		widths: Array[float], ids: Array[StringName], link_parent: Dictionary) -> void:
	var leftmost := INF
	for i in units.size():
		leftmost = minf(leftmost, float(x.get(i, 0.0)))
	if leftmost == INF:
		leftmost = 0.0

	for i in units.size():
		var members: Array = units[i]
		var left: float = float(x.get(i, 0.0)) - leftmost
		var y: float = rows[i] * ROW_HEIGHT
		for k in members.size():
			_positions[members[k]] = Vector2(left + k * (NODE_SIZE.x + SPOUSE_GAP), y)
		var centre: float = left + widths[i] * 0.5
		for member in members:
			_child_anchor[member] = centre
		if members.size() == 2:
			_spouse_edges.append([members[0], members[1]])
			_partner_of[members[0]] = members[1]

	# One descent line per person, hung from the middle of the household above.
	for id in ids:
		if not unit_of.has(id) or not link_parent.has(id):
			continue
		var anchor: StringName = link_parent[id]
		if unit_of.get(anchor, -1) == unit_of[id]:
			continue
		_edges.append([anchor, id])


## In focus mode the tree is rooted at the highest visible ancestor rather than
## at the world's founders, so the subject sits in a readable amount of context.
func _layout_roots() -> Array[StringName]:
	if not _focus_active:
		return source.roots()
	var out: Array[StringName] = []
	for id in _visible_ids:
		var has_visible_parent := false
		for parent_id in source.parents(id):
			if _visible_ids.has(parent_id):
				has_visible_parent = true
				break
		if not has_visible_parent:
			out.append(id)
	return out


func _place(id: StringName, depth: int, visited: Dictionary) -> float:
	if visited.has(id) or not source.exists(id):
		return -1.0
	if _focus_active and not _visible_ids.has(id):
		return -1.0
	visited[id] = true
	_deepest_row = maxi(_deepest_row, depth)

	# A married pair is laid out as one unit, with their children hanging from
	# between them — which is what makes the tree read as a family rather than as
	# two unrelated lines that happen to produce the same child.
	var partner := _partner_to_draw(id, visited)
	if partner != &"":
		visited[partner] = true
		_partner_of[id] = partner
		_spouse_edges.append([id, partner])

	var unit_width: float = NODE_SIZE.x if partner == &"" \
		else NODE_SIZE.x * 2.0 + SPOUSE_GAP

	var child_centres: Array[float] = []
	if not _collapsed.has(id):
		for child_id in source.children(id):
			var cx := _place(child_id, depth + 1, visited)
			if cx >= 0.0:
				child_centres.append(cx)
				_edges.append([id, child_id])
	else:
		_hidden_counts[id] = _count_descendants(id)

	var centre_x: float
	if child_centres.is_empty():
		centre_x = _cursor_x + unit_width * 0.5
		_cursor_x += unit_width + H_GAP
	else:
		centre_x = (child_centres[0] + child_centres[child_centres.size() - 1]) * 0.5
		# A parent narrower than its children must not overlap the row beside it.
		_cursor_x = maxf(_cursor_x, centre_x + unit_width * 0.5 + H_GAP)

	var left := centre_x - unit_width * 0.5
	_positions[id] = Vector2(left, depth * ROW_HEIGHT)
	if partner != &"":
		_positions[partner] = Vector2(left + NODE_SIZE.x + SPOUSE_GAP, depth * ROW_HEIGHT)
	_child_anchor[id] = centre_x
	return centre_x


## The spouse to draw beside this person: one that exists, is not already placed
## elsewhere in the tree, and is visible under the current focus.
func _partner_to_draw(id: StringName, visited: Dictionary) -> StringName:
	for spouse_id in source.spouses(id):
		if visited.has(spouse_id) or not source.exists(spouse_id):
			continue
		if _focus_active and not _visible_ids.has(spouse_id):
			continue
		# Somebody with descendants of their own belongs at the head of their own
		# line rather than tucked beside a partner.
		if not source.children(spouse_id).is_empty():
			continue
		return spouse_id
	return &""


func _count_descendants(id: StringName) -> int:
	var total := 0
	var frontier: Array[StringName] = source.children(id)
	var seen := {}
	while not frontier.is_empty():
		var current: StringName = frontier.pop_back()
		if seen.has(current) or not source.exists(current):
			continue
		seen[current] = true
		total += 1
		frontier.append_array(source.children(current))
	return total


# -------------------------------------------------------------- focus mode

## Shows one subject with their ancestry and a bounded number of generations of
## descendants, instead of every branch in the world at once.
func focus_on(id: StringName, ancestor_depth: int = 12, descendant_depth: int = 3) -> void:
	if not source.exists(id):
		return
	_visible_ids.clear()
	_visible_ids[id] = true

	var up: Array = [[id, 0]]
	while not up.is_empty():
		var entry: Array = up.pop_front()
		if entry[1] >= ancestor_depth:
			continue
		for parent_id in source.parents(entry[0]):
			if not _visible_ids.has(parent_id) and source.exists(parent_id):
				_visible_ids[parent_id] = true
				up.append([parent_id, entry[1] + 1])

	var down: Array = [[id, 0]]
	while not down.is_empty():
		var entry: Array = down.pop_front()
		if entry[1] >= descendant_depth:
			continue
		for child_id in source.children(entry[0]):
			if not _visible_ids.has(child_id) and source.exists(child_id):
				_visible_ids[child_id] = true
				down.append([child_id, entry[1] + 1])

	# Siblings give a focused subject somewhere to sit; without them a lone
	# descendant line reads as though nobody else ever existed.
	for parent_id in source.parents(id):
		for sibling_id in source.children(parent_id):
			if source.exists(sibling_id):
				_visible_ids[sibling_id] = true

	# Nobody visible should be shown without the person they married — and with
	# their partner comes the partner's parents, because in a world where houses
	# only meet by marriage that line is the join between two families and the
	# reason the subject exists at all.
	for visible_id in _visible_ids.keys():
		for spouse_id in source.spouses(visible_id):
			if not source.exists(spouse_id):
				continue
			_visible_ids[spouse_id] = true
			for in_law_id in source.parents(spouse_id):
				if source.exists(in_law_id):
					_visible_ids[in_law_id] = true

	_focus_active = true
	selected_id = id
	rebuild()
	# Focus mode exists to be legible, so it opens at reading zoom rather than
	# inheriting however far out the whole-tree view happened to be.
	view_zoom = clampf(1.0, min_zoom, max_zoom)
	center_on_node(id)


func clear_focus() -> void:
	_focus_active = false
	_visible_ids.clear()
	rebuild()
	frame_all()


func is_focused() -> bool:
	return _focus_active


## Puts a node in the upper part of the view rather than the exact middle: the
## detail sheet covers the bottom, and a focused person's children are drawn
## below them, so dead-centring hides the half worth looking at.
const FOCUS_VERTICAL_ANCHOR := 0.30


func center_on_node(id: StringName) -> void:
	if not _positions.has(id):
		return
	# Centre the household, not one of its two halves.
	var anchor_x: float = _child_anchor.get(id, _positions[id].x + NODE_SIZE.x * 0.5)
	var target := Vector2(anchor_x, _positions[id].y + NODE_SIZE.y * 0.5)
	view_offset = Vector2(size.x * 0.5, size.y * FOCUS_VERTICAL_ANCHOR) - target * view_zoom
	queue_redraw()


## Fits the tree, but never shrinks it past the point where the names can be
## read — a tree small enough to fit a hundred boxes on a phone is a diagram of
## nothing. Anything wider than that starts at the top-left and is panned.
const READABLE_ZOOM := 0.62


func frame_all() -> void:
	if _bounds.size == Vector2.ZERO or size.x < 1.0 or size.y < 1.0:
		return
	var fit: float = minf(size.x / maxf(1.0, _bounds.size.x + 60.0),
		size.y / maxf(1.0, _bounds.size.y + 60.0))
	view_zoom = clampf(fit, READABLE_ZOOM, max_zoom)

	var scaled := _bounds.size * view_zoom
	# Trees grow downward from their origin, so pin the top rather than centring
	# vertically and leaving the roots floating in the middle of the screen.
	# Horizontally the opposite: a family four centuries wide does not fit at any
	# readable zoom, and its left edge is usually an empty corner, so open in the
	# middle of it and let the player pan.
	var x: float = (size.x - scaled.x) * 0.5
	if scaled.x >= size.x:
		x = size.x * 0.5 - _bounds.size.x * 0.5 * view_zoom
	view_offset = Vector2(x, 28.0) - _bounds.position * view_zoom
	_needs_framing = false
	queue_redraw()


func toggle_collapse(id: StringName) -> void:
	if _collapsed.has(id):
		_collapsed.erase(id)
	else:
		_collapsed[id] = true
	rebuild()


# ------------------------------------------------------------------ drawing

func _draw_tree() -> void:
	if source == null:
		return
	# Marriages first, so descent lines cross over them rather than under.
	for pair in _spouse_edges:
		if not _positions.has(pair[0]) or not _positions.has(pair[1]):
			continue
		var a: Vector2 = _positions[pair[0]]
		var b: Vector2 = _positions[pair[1]]
		var left := to_screen(a + Vector2(NODE_SIZE.x, NODE_SIZE.y * 0.5))
		var right := to_screen(b + Vector2(0, NODE_SIZE.y * 0.5))
		draw_line(left, right, Palette.ACCENT, maxf(1.5, 3.0 * view_zoom))

	for edge in _edges:
		var from_pos: Vector2 = _positions.get(edge[0], Vector2.ZERO)
		var to_pos: Vector2 = _positions.get(edge[1], Vector2.ZERO)
		if not _positions.has(edge[0]) or not _positions.has(edge[1]):
			continue
		# Children descend from between their parents, not from one of them.
		var anchor_x: float = _child_anchor.get(edge[0], from_pos.x + NODE_SIZE.x * 0.5)
		var start := to_screen(Vector2(anchor_x, from_pos.y + NODE_SIZE.y))
		var end := to_screen(to_pos + Vector2(NODE_SIZE.x * 0.5, 0))
		var mid_y := (start.y + end.y) * 0.5
		draw_polyline([start, Vector2(start.x, mid_y), Vector2(end.x, mid_y), end],
			Palette.LINE, maxf(1.0, 2.0 * view_zoom))

	for id in _positions:
		_draw_node(id)


func _draw_node(id: StringName) -> void:
	var rect := Rect2(to_screen(_positions[id]), NODE_SIZE * view_zoom)
	var accent: Color = source.colour(id)
	var faded: bool = source.is_faded(id)
	if faded:
		accent = accent.darkened(0.45)

	draw_rect(rect, Palette.PANEL_RAISED if not faded else Palette.PANEL, true)
	draw_rect(rect, Palette.ACCENT if id == selected_id else accent, false,
		maxf(1.0, (3.0 if id == selected_id else 1.5) * view_zoom))
	# A colour bar on the leading edge survives zooming out further than text does.
	draw_rect(Rect2(rect.position, Vector2(5.0 * view_zoom, rect.size.y)), accent, true)

	if view_zoom < 0.34:
		return

	var font := get_theme_default_font()
	var name_size := maxi(9, int(19 * view_zoom))
	var sub_size := maxi(8, int(15 * view_zoom))
	var pad := 12.0 * view_zoom

	draw_string(font, rect.position + Vector2(pad, 24.0 * view_zoom), source.label(id),
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - pad * 2.0 - CHEVRON_WIDTH * view_zoom,
		name_size, Palette.TEXT_DIM if faded else Palette.TEXT)
	draw_string(font, rect.position + Vector2(pad, 46.0 * view_zoom), source.sublabel(id),
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - pad * 2.0, sub_size, Palette.TEXT_MUTED)

	# Folding a subtree only means something in a tree. In the family chart a
	# person's descendants are also somebody else's, so there is nothing to fold
	# them into; focus mode and search are what make that view readable.
	var child_count := 0 if source.is_generational() else source.children(id).size()
	if child_count > 0:
		var chevron_centre := rect.position + Vector2(
			rect.size.x - CHEVRON_WIDTH * view_zoom * 0.5, rect.size.y * 0.5)
		if _collapsed.has(id):
			draw_string(font, chevron_centre - Vector2(14.0 * view_zoom, -6.0 * view_zoom),
				"+%d" % int(_hidden_counts.get(id, child_count)),
				HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(9, int(15 * view_zoom)), Palette.ACCENT)
		else:
			draw_string(font, chevron_centre - Vector2(6.0 * view_zoom, -6.0 * view_zoom),
				"−", HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(9, int(18 * view_zoom)),
				Palette.TEXT_MUTED)


func _on_tapped(world_position: Vector2) -> void:
	for id in _positions:
		var rect := Rect2(_positions[id], NODE_SIZE)
		if not rect.has_point(world_position):
			continue
		var in_chevron: bool = not source.is_generational() \
			and world_position.x > rect.position.x + NODE_SIZE.x - CHEVRON_WIDTH
		if in_chevron and not source.children(id).is_empty():
			toggle_collapse(id)
		else:
			selected_id = id
			node_selected.emit(id)
			queue_redraw()
		return
	selected_id = &""
	node_selected.emit(&"")
	queue_redraw()

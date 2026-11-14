class_name Crest
extends RefCounted

## A coat of arms for every house: a shield in the family's colour, charged with
## the device of the line it springs from.
##
## Colour alone told families apart on the map and left them anonymous. A shield
## gives each a face — and says something true about it: a cadet house keeps the
## device of the house it left and changes only the colour, so on any screen two
## shields with the same chevron are kin, whatever they are called now and
## however long ago they parted. The founding houses each have their own.
##
## Drawn, not stored: the shape is a handful of polygons in a unit box, clipped
## to the shield once and reused at whatever size is asked for.

enum Device { PALE, FESS, BEND, CHEVRON, CROSS, SALTIRE, CHIEF, BORDURE }

const METALS: Array[Color] = [Color("e2c36a"), Color("d9d5c8")]

## The shield, on a box from -1 to 1.
const SHIELD: Array[Vector2] = [
	Vector2(-0.8, -0.92), Vector2(0.8, -0.92), Vector2(0.8, 0.05), Vector2(0.74, 0.38),
	Vector2(0.55, 0.66), Vector2(0.3, 0.84), Vector2(0.0, 0.96), Vector2(-0.3, 0.84),
	Vector2(-0.55, 0.66), Vector2(-0.74, 0.38), Vector2(-0.8, 0.05),
]

## What each device is made of before it is cut to the shield.
const BANDS := {
	Device.PALE: [[Vector2(-0.24, -1.1), Vector2(0.24, -1.1), Vector2(0.24, 1.1), Vector2(-0.24, 1.1)]],
	Device.FESS: [[Vector2(-1.1, -0.34), Vector2(1.1, -0.34), Vector2(1.1, 0.12), Vector2(-1.1, 0.12)]],
	Device.BEND: [[Vector2(-1.0, -1.33), Vector2(1.0, 0.77), Vector2(1.0, 1.27), Vector2(-1.0, -0.83)]],
	Device.CHEVRON: [[Vector2(-0.98, 0.42), Vector2(0.0, -0.4), Vector2(0.98, 0.42),
		Vector2(0.98, 0.86), Vector2(0.0, 0.04), Vector2(-0.98, 0.86)]],
	Device.CROSS: [
		[Vector2(-0.17, -1.1), Vector2(0.17, -1.1), Vector2(0.17, 1.1), Vector2(-0.17, 1.1)],
		[Vector2(-1.1, -0.36), Vector2(1.1, -0.36), Vector2(1.1, -0.02), Vector2(-1.1, -0.02)]],
	Device.SALTIRE: [
		[Vector2(-1.0, -1.22), Vector2(1.0, 0.82), Vector2(1.0, 1.16), Vector2(-1.0, -0.88)],
		[Vector2(1.0, -1.22), Vector2(1.0, -0.88), Vector2(-1.0, 1.16), Vector2(-1.0, 0.82)]],
	Device.CHIEF: [[Vector2(-1.1, -1.1), Vector2(1.1, -1.1), Vector2(1.1, -0.44), Vector2(-1.1, -0.44)]],
}

static var _cut: Dictionary = {}


## Draws a house's arms centred on a point, `size` tall.
static func draw(ci: CanvasItem, house: Organization, centre: Vector2, size: float,
		faded: bool = false) -> void:
	if house == null:
		return
	var r := size * 0.5
	var field := Heraldry.of_org(house)
	var metal := metal_of(house)
	if faded:
		field = field.darkened(0.45)
		metal = metal.darkened(0.45)
	var device := device_of(house)
	var outline := _scaled(SHIELD, centre, r)

	if device == Device.BORDURE:
		ci.draw_colored_polygon(outline, metal)
		ci.draw_colored_polygon(_scaled(SHIELD, centre + Vector2(0, -0.02 * r), r * 0.7), field)
	else:
		ci.draw_colored_polygon(outline, field)
		for piece in _pieces(device):
			ci.draw_colored_polygon(_scaled(piece, centre, r), metal)
	# A dark rim so the shield reads on any ground, and a light one inside it.
	var rim := outline.duplicate()
	rim.append(outline[0])
	ci.draw_polyline(rim, Color(0.06, 0.05, 0.04, 0.95), maxf(1.5, size * 0.07), true)


## The device a house bears: that of the line it springs from.
static func device_of(house: Organization) -> int:
	return _number(stem_of(house)) % Device.size()


static func metal_of(house: Organization) -> Color:
	return METALS[(_number(stem_of(house)) / Device.size()) % METALS.size()]


## The house a family's arms come from: itself, if it stood at the founding, or
## else the founding house at the head of the line of cadets it descends by.
static func stem_of(house: Organization) -> Organization:
	var walk := house
	var guard := 0
	while walk.founding_tick > 0 and walk.parent_org_id != &"" and guard < 64:
		var parent := GameState.get_organization(walk.parent_org_id)
		if parent == null or parent.kind != Organization.OrgKind.HOUSE:
			break
		walk = parent
		guard += 1
	return walk


## Whether two houses bear the same device — that is, are of one line.
static func are_kin(a: Organization, b: Organization) -> bool:
	return a != null and b != null and stem_of(a).org_id == stem_of(b).org_id


## Organizations are numbered as they are founded, so the founding houses get
## devices in turn rather than by the luck of a hash — and a different world
## deals them from a different place in the pack.
static func _number(org: Organization) -> int:
	var digits := String(org.org_id).trim_prefix("org_")
	var turn := absi(int(digits)) if digits.is_valid_int() else absi(hash(org.org_id))
	var deal: int = absi(GameState.world.seed) % 16 if GameState.world != null else 0
	return turn + deal


static func _pieces(device: int) -> Array:
	if _cut.has(device):
		return _cut[device]
	var pieces: Array = []
	var shield := PackedVector2Array(SHIELD)
	for band in BANDS.get(device, []):
		for piece in Geometry2D.intersect_polygons(PackedVector2Array(band), shield):
			if piece.size() >= 3:
				pieces.append(piece)
	_cut[device] = pieces
	return pieces


static func _scaled(points, centre: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(centre + p * r)
	return out

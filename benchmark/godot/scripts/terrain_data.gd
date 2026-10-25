class_name TerrainData
extends RefCounted
## Terrain grid from scene_layout.json plus height / walkability queries.

const CELL := 1.6
const LAYER := 0.8
const YOFF := 0.02
const OUTER_Y := -2.0 * LAYER

const ROAD := 1
const DIRT := 2
const WATER := 4
const BRIDGE := 8
const RAMP := 16

var ox := 0
var oz := 0
var w := 0
var h := 0
var biome := PackedInt32Array()
var level := PackedInt32Array()
var overlay := PackedInt32Array()


func setup(t: Dictionary) -> void:
	ox = int(t["origin_cell"][0])
	oz = int(t["origin_cell"][1])
	w = int(t["size"][0])
	h = int(t["size"][1])
	biome.resize(w * h)
	level.resize(w * h)
	overlay.resize(w * h)
	var rows: Array = t["rows_north_to_south"]
	for z in h:
		for x in w:
			var c: Dictionary = rows[z][x]
			biome[z * w + x] = int(c["biome"])
			level[z * w + x] = int(c["level"])
			overlay[z * w + x] = int(c["overlay"])


func inside(cx: int, cz: int) -> bool:
	return cx >= ox and cz >= oz and cx < ox + w and cz < oz + h


func _i(cx: int, cz: int) -> int:
	return (cz - oz) * w + (cx - ox)


func lvl(cx: int, cz: int) -> int:
	return level[_i(cx, cz)] if inside(cx, cz) else -2


func ov(cx: int, cz: int) -> int:
	return overlay[_i(cx, cz)] if inside(cx, cz) else 0


func bio(cx: int, cz: int) -> int:
	return biome[_i(cx, cz)] if inside(cx, cz) else 3


func is_water(cx: int, cz: int) -> bool:
	return (ov(cx, cz) & WATER) != 0


func is_bridge(cx: int, cz: int) -> bool:
	return (ov(cx, cz) & BRIDGE) != 0


func is_ramp(cx: int, cz: int) -> bool:
	return (ov(cx, cz) & RAMP) != 0


static func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(roundi(x / CELL), roundi(z / CELL))


static func center_of(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL, c.y * CELL)


## Direction (dx, dz) a ramp rises toward: the 4-neighbour exactly one level higher.
func ramp_dir(cx: int, cz: int) -> Vector2i:
	var l := lvl(cx, cz)
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var n: Vector2i = Vector2i(cx, cz) + d
		if inside(n.x, n.y) and lvl(n.x, n.y) == l + 1 and not is_water(n.x, n.y):
			return d
	return Vector2i(0, -1)


## Height of a cell's top surface (riverbed for water) at a local offset in cell units (-0.5..0.5).
func top_at(cx: int, cz: int, lx: float, lz: float) -> float:
	if not inside(cx, cz):
		return OUTER_Y
	var l := lvl(cx, cz)
	if is_ramp(cx, cz):
		var d := ramp_dir(cx, cz)
		var t := clampf(lx * d.x + lz * d.y + 0.5, 0.0, 1.0)
		return (l + t) * LAYER + YOFF
	return l * LAYER + YOFF


func water_surface(cx: int, cz: int) -> float:
	return (lvl(cx, cz) + 0.6) * LAYER + YOFF


func bridge_top(cx: int, cz: int) -> float:
	return (lvl(cx, cz) + 1) * LAYER + YOFF


## Bridges run toward the two ends that are not water.
func bridge_along_x(cx: int, cz: int) -> bool:
	return not is_water(cx - 1, cz) and not is_water(cx + 1, cz)


## Visual ground height at a world point (water -> water surface, bridge -> deck).
func surface_height(x: float, z: float) -> float:
	var c := cell_of(x, z)
	if not inside(c.x, c.y):
		return OUTER_Y
	var lx := x / CELL - c.x
	var lz := z / CELL - c.y
	if is_water(c.x, c.y):
		if is_bridge(c.x, c.y):
			var across := lz if bridge_along_x(c.x, c.y) else lx
			if absf(across * CELL) <= 0.65:
				return bridge_top(c.x, c.y)
		return water_surface(c.x, c.y)
	return top_at(c.x, c.y, lx, lz)


## Walkable ground height, or NAN when the point is water / off the map.
func walk_height(x: float, z: float) -> float:
	var c := cell_of(x, z)
	if not inside(c.x, c.y):
		return NAN
	var lx := x / CELL - c.x
	var lz := z / CELL - c.y
	if is_water(c.x, c.y):
		if is_bridge(c.x, c.y):
			var across := lz if bridge_along_x(c.x, c.y) else lx
			if absf(across * CELL) <= 0.6:
				return bridge_top(c.x, c.y)
		return NAN
	return top_at(c.x, c.y, lx, lz)


## Effective path flags used by the dual-grid (bridges continue the path they carry).
func path_flags(cx: int, cz: int) -> int:
	var o := ov(cx, cz)
	var f := 0
	if (o & ROAD) != 0:
		f |= 1
	if (o & DIRT) != 0:
		f |= 2
	if (o & BRIDGE) != 0:
		var a := Vector2i(1, 0) if bridge_along_x(cx, cz) else Vector2i(0, 1)
		if (ov(cx - a.x, cz - a.y) & DIRT) != 0 and (ov(cx + a.x, cz + a.y) & DIRT) != 0:
			f |= 2
	return f


func make_data_image() -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for z in h:
		for x in w:
			var cx := x + ox
			var cz := z + oz
			img.set_pixel(x, z, Color8(bio(cx, cz), lvl(cx, cz) + 4, ov(cx, cz), path_flags(cx, cz)))
	return img

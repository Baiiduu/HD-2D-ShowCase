extends Node3D
## Grid-terrain character controller: walks ramps and bridges, blocked by cliffs, water and buildings.

const RADIUS := 0.22
const STEP := 0.3
const HEAD := 1.4

var td: TerrainData
var obstacles: Array
var speed := 4.0
var ground_y := 0.0
var _bob_t := 0.0
var _visual: Node3D
var _facing_left := false


func setup(_main: Node, terrain: TerrainData, obs: Array, spd: float) -> void:
	td = terrain
	obstacles = obs
	speed = spd


func _ready() -> void:
	_visual = get_node_or_null("Visual")


## Teleport (used by spawn and screenshot mode). Height follows the terrain at that point.
func place(xz: Vector2) -> void:
	var h := _support_height(xz, 99.0)
	if is_nan(h):
		h = td.surface_height(xz.x, xz.y)
	ground_y = h
	position = Vector3(xz.x, h, xz.y)


func _process(delta: float) -> void:
	var inp := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if inp.length() > 0.01:
		var step := inp.normalized() * speed * delta
		var cur := Vector2(position.x, position.z)
		var moved := false
		for attempt in [step, Vector2(step.x, 0), Vector2(0, step.y)]:
			if attempt.length() < 1e-5:
				continue
			var nxt: Vector2 = cur + attempt
			var h := _can_stand(nxt)
			if not is_nan(h):
				cur = nxt
				ground_y = h
				moved = true
				break
		position.x = cur.x
		position.z = cur.y
		if absf(inp.x) > 0.1:
			_facing_left = inp.x < 0
		if moved:
			_bob_t += delta * 9.0
	else:
		_bob_t = 0.0
	position.y = lerpf(position.y, ground_y, clampf(delta * 18.0, 0.0, 1.0))
	if _visual:
		var spr := _visual.get_node("Sprite") as MeshInstance3D
		var hop := absf(sin(_bob_t)) * 0.035 if _bob_t > 0.0 else 0.0
		spr.position.y = 0.75 - 3.0 / 64.0 * 1.5 + hop
		spr.material_override.set_shader_parameter("flip_h", _facing_left)


## Highest walkable surface under a point that is reachable from `from_y`.
func _support_height(p: Vector2, reach: float) -> float:
	var h := td.walk_height(p.x, p.y)
	for o in obstacles:
		if not o["walk"]:
			continue
		if p.x >= o["min"].x and p.x <= o["max"].x and p.y >= o["min"].y and p.y <= o["max"].y:
			if o["top"] <= reach:
				h = maxf(h, o["top"]) if not is_nan(h) else o["top"]
	return h


## Returns the new ground height if the player may stand at p, otherwise NAN.
func _can_stand(p: Vector2) -> float:
	var reach := ground_y + STEP
	var center := _support_height(p, reach)
	if is_nan(center) or absf(center - ground_y) > STEP:
		return NAN
	# sample the footprint so cliffs/water edges block with some clearance
	for i in 8:
		var a := TAU * i / 8.0
		var q := p + Vector2(cos(a), sin(a)) * RADIUS
		var h := _support_height(q, center + STEP)
		if is_nan(h) or absf(h - center) > STEP + 0.05:
			return NAN
	# solid obstacles (buildings, pillars, posts, rails)
	for o in obstacles:
		if o["walk"] and o["top"] <= center + STEP:
			continue
		if o["bottom"] > center + HEAD or o["top"] <= center + STEP:
			continue
		var cx := clampf(p.x, o["min"].x, o["max"].x)
		var cz := clampf(p.y, o["min"].y, o["max"].y)
		if Vector2(cx, cz).distance_to(p) < RADIUS:
			return NAN
	return center

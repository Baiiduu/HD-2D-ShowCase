extends SceneTree
## Headless sanity test of the player controller: run with
##   Godot --headless --path . --script res://tests/walk_test.gd

func walk(p, from: Vector2, dir: Vector2, secs: float) -> Vector3:
	p.place(from)
	p.position.y = p.ground_y
	var dt := 1.0 / 60.0
	for i in int(secs / dt):
		var step: Vector2 = dir.normalized() * p.speed * dt
		var cur := Vector2(p.position.x, p.position.z)
		var h: float = p._can_stand(cur + step)
		if not is_nan(h):
			p.position.x += step.x
			p.position.z += step.y
			p.ground_y = h
			p.position.y = h
	return p.position


func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var p = main.player
	p.set_process(false)
	var cases := [
		["north up ramp (10,-1) onto highland", Vector2(16.0, 0.0), Vector2(0, -1), 3.0],
		["north from road into level-1 cliff (blocked)", Vector2(19.2, 0.0), Vector2(0, -1), 3.0],
		["east along road across lower bridge", Vector2(19.0, 0.0), Vector2(1, 0), 1.5],
		["south from road into stream (blocked)", Vector2(22.4, 0.0), Vector2(0, 1), 2.0],
		["up ramp (18,-3) to tableland", Vector2(28.8, -4.8), Vector2(0, -1), 2.0],
		["west across upper bridge", Vector2(25.0, -4.8), Vector2(-1, 0), 1.5],
		["north into city building (blocked)", Vector2(-8.5, -3.0), Vector2(0, -1), 2.0],
		["up temple steps", Vector2(-6.8, 7.5), Vector2(0, -1), 2.0],
		["walk off map west (blocked)", Vector2(-10.5, 0.0), Vector2(-1, 0), 2.0],
	]
	for c in cases:
		var r: Vector3 = walk(p, c[1], c[2], c[3])
		print("%-48s start %s -> end (%.2f, %.2f, %.2f)" % [c[0], c[1], r.x, r.y, r.z])
	quit()

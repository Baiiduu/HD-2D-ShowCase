extends Node3D
## Procedural distant landscape: lowland meadow around the map block, rolling hills,
## forest silhouettes, far mountain ridges and a few village lights. Purely scenery.

const SH_OUTER := preload("res://shaders/outer_ground.gdshader")
const SH_TREE := preload("res://shaders/tree.gdshader")
const SH_BEACON := preload("res://shaders/beacon.gdshader")

const MAP_MIN := Vector2(-12.0, -10.4)
const MAP_MAX := Vector2(36.0, 10.4)

var noise := FastNoiseLite.new()
var ridge := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()


func build(tex: Dictionary, _td: TerrainData) -> void:
	rng.seed = 4242
	noise.seed = 7
	noise.frequency = 0.018
	noise.fractal_octaves = 4
	ridge.seed = 21
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ridge.frequency = 0.006
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 4
	_build_ground(tex)
	_build_trees()
	_build_beacons()
	_build_mist()


func _build_mist() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 900)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/mist_layer.gdshader")
	var mi := MeshInstance3D.new()
	mi.name = "GroundMist"
	mi.mesh = pm
	mi.material_override = m
	mi.position = Vector3(12, -0.75, -60)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)


func map_dist(x: float, z: float) -> float:
	var c := (MAP_MIN + MAP_MAX) * 0.5
	var hs := (MAP_MAX - MAP_MIN) * 0.5
	var d := (Vector2(x, z) - c).abs() - hs
	return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length()


func height(x: float, z: float) -> float:
	var d := map_dist(x, z)
	var base := TerrainData.OUTER_Y - 0.02
	var n := noise.get_noise_2d(x, z) * 0.5 + 0.5
	var swell := noise.get_noise_2d(x * 3.0, z * 3.0) * 0.35 * smoothstep(3.0, 12.0, d)
	var hills := smoothstep(30.0, 110.0, d) * (0.5 + 4.5 * n)
	var r := ridge.get_noise_2d(x, z) * 0.5 + 0.5
	var mount := smoothstep(120.0, 260.0, d) * (3.0 + 16.0 * r * r)
	# keep the view south of the map open (camera side)
	if z > MAP_MAX.y:
		var south := smoothstep(MAP_MAX.y, MAP_MAX.y + 40.0, z)
		hills *= 1.0 - south * 0.7
	return base + swell + hills + mount


func _build_ground(tex: Dictionary) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# non-uniform grid: fine near the map, coarse far away
	var xs := _axis(-340.0, 380.0, MAP_MIN.x, MAP_MAX.x)
	var zs := _axis(-400.0, 260.0, MAP_MIN.y, MAP_MAX.y)
	var hgt := []
	for z in zs:
		var row := PackedFloat32Array()
		for x in xs:
			row.append(height(x, z))
		hgt.append(row)
	for j in zs.size() - 1:
		for i in xs.size() - 1:
			var p00 := Vector3(xs[i], hgt[j][i], zs[j])
			var p10 := Vector3(xs[i + 1], hgt[j][i + 1], zs[j])
			var p01 := Vector3(xs[i], hgt[j + 1][i], zs[j + 1])
			var p11 := Vector3(xs[i + 1], hgt[j + 1][i + 1], zs[j + 1])
			for tri in [[p00, p10, p11], [p00, p11, p01]]:
				var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
				if n.y < 0:
					n = -n
					tri = [tri[0], tri[2], tri[1]]
				for v in tri:
					st.set_normal(n)
					st.add_vertex(v)
	var m := ShaderMaterial.new()
	m.shader = SH_OUTER
	m.set_shader_parameter("tex_grass", tex["grass"])
	m.set_shader_parameter("tex_rock", tex["cliff"])
	var mi := MeshInstance3D.new()
	mi.name = "Lowland"
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _axis(a: float, b: float, m0: float, m1: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var v := a
	while v < b:
		out.append(v)
		var d := 0.0
		if v < m0:
			d = m0 - v
		elif v > m1:
			d = v - m1
		v += clampf(1.5 + d * 0.12, 1.5, 14.0)
	out.append(b)
	return out


func _pine_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := Color(0.2, 0.14, 0.1)
	var seg := 7
	# trunk
	_cone(st, 0.0, 0.9, 0.12, 0.08, seg, trunk)
	var tiers := [[0.6, 2.0, 1.0], [1.4, 2.7, 0.78], [2.2, 3.4, 0.55], [2.9, 4.1, 0.32]]
	for t in tiers:
		var g := Color(0.06, 0.1, 0.075).lerp(Color(0.1, 0.13, 0.085), t[0] / 3.0)
		_cone(st, t[0], t[1], t[2], 0.0, seg, g)
	return st.commit()


func _cone(st: SurfaceTool, y0: float, y1: float, r0: float, r1: float, seg: int, c: Color) -> void:
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var b0 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var b1 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var t0 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
		var t1 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		var n := Vector3(cos((a0 + a1) / 2), (r0 - r1) / (y1 - y0), sin((a0 + a1) / 2)).normalized()
		for v in [b0, b1, t1, b0, t1, t0]:
			st.set_color(c)
			st.set_normal(n)
			st.add_vertex(v)
		# underside
		for v in [b0, Vector3(0, y0, 0), b1]:
			st.set_color(c * 0.5)
			st.set_normal(Vector3.DOWN)
			st.add_vertex(v)


func _build_trees() -> void:
	var mesh := _pine_mesh()
	var near_x: Array = []
	var far_x: Array = []
	var tries := 0
	while near_x.size() + far_x.size() < 1500 and tries < 40000:
		tries += 1
		var x := rng.randf_range(-150.0, 190.0)
		var z := rng.randf_range(-200.0, 60.0)
		var d := map_dist(x, z)
		if d < 7.0 or d > 160.0:
			continue
		# keep the camera corridor south of the map clear
		if z > MAP_MAX.y - 2.0 and x > MAP_MIN.x - 18.0 and x < MAP_MAX.x + 18.0:
			continue
		if z > MAP_MAX.y + 30.0:
			continue
		var cluster := noise.get_noise_2d(x * 2.0 + 100.0, z * 2.0) * 0.5 + 0.5
		var dens := smoothstep(0.35, 0.65, cluster) * (0.12 + 0.88 * smoothstep(10.0, 45.0, d))
		if rng.randf() > dens:
			continue
		var s := rng.randf_range(0.7, 1.5) * (1.0 + smoothstep(20.0, 120.0, d) * 0.6)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.25), s)),
			Vector3(x, height(x, z) - 0.1, z))
		if d < 22.0:
			near_x.append(xf)
		else:
			far_x.append(xf)
	_mm(mesh, near_x, true)
	_mm(mesh, far_x, false)


func _mm(mesh: Mesh, xforms: Array, shadows: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 0))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Trees"
	mi.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = SH_TREE
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_beacons() -> void:
	# distant farmsteads / shrines: little warm points on the far hills
	var pts: Array = []
	var villages := [Vector2(-40, -120), Vector2(30, -150), Vector2(85, -105), Vector2(-90, -70), Vector2(120, -60)]
	for v in villages:
		var count := rng.randi_range(4, 9)
		for i in count:
			var p: Vector2 = v + Vector2(rng.randf_range(-12, 12), rng.randf_range(-8, 8))
			pts.append(Vector3(p.x, height(p.x, p.y) + rng.randf_range(0.6, 2.0), p.y))
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.6)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = pts.size()
	for i in pts.size():
		mm.set_instance_transform(i, Transform3D(Basis(), pts[i]))
		var warm := Color(1.0, 0.85, 0.7) if rng.randf() < 0.8 else Color(0.8, 0.9, 1.0)
		mm.set_instance_color(i, warm)
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), 0, 0))
	var mi := MultiMeshInstance3D.new()
	mi.name = "FarLights"
	mi.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = SH_BEACON
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

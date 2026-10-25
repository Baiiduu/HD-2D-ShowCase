extends Node3D
## Builds the whole "Four Realms" scene from assets/layout/scene_layout.json at runtime.

const ASSET := "res://assets/"
const SH_TERRAIN := preload("res://shaders/terrain.gdshader")
const SH_CLIFF := preload("res://shaders/cliff.gdshader")
const SH_WATER := preload("res://shaders/water.gdshader")
const SH_FALL := preload("res://shaders/waterfall.gdshader")
const SH_PROP := preload("res://shaders/prop.gdshader")
const SH_SPRITE := preload("res://shaders/sprite.gdshader")
const SH_BLOB := preload("res://shaders/blob.gdshader")
const SH_HALO := preload("res://shaders/halo.gdshader")
const SH_FIREFLY := preload("res://shaders/firefly.gdshader")
const SH_MIST := preload("res://shaders/mist.gdshader")
const SH_SKY := preload("res://shaders/sky.gdshader")
const SH_POST := preload("res://shaders/post.gdshader")

const PlayerScript := preload("res://scripts/player.gd")
const CameraRig := preload("res://scripts/camera_rig.gd")
const Backdrop := preload("res://scripts/backdrop.gd")

var layout: Dictionary
var td := TerrainData.new()
var tex := {}
var tex_avg := {}
var data_tex: ImageTexture
var spill_pos: Array = []
var spill_col: Array = []
var ao_rects: Array = []
var ao_rect_h: Array = []
var obstacles: Array = []        # {min: Vector2, max: Vector2, bottom: float, top: float, walk: bool}
var spill_materials: Array = []

var world: Node3D
var player: Node3D
var rig: Node3D
var env: Environment


func _ready() -> void:
	var f := FileAccess.open(ASSET + "layout/scene_layout.json", FileAccess.READ)
	layout = JSON.parse_string(f.get_as_text())
	td.setup(layout["terrain"])
	_load_textures()
	data_tex = ImageTexture.create_from_image(td.make_data_image())

	world = Node3D.new()
	world.name = "World"
	add_child(world)

	_collect_emitters()
	_build_terrain()
	_build_water()
	_build_bridges()
	_build_layout_meshes()
	_build_lights()
	_build_fog_volumes()
	_build_particles()
	_build_sprites()
	_build_environment()
	var bd := Backdrop.new()
	bd.name = "Backdrop"
	world.add_child(bd)
	bd.build(tex, td)

	for m in spill_materials:
		m.set_shader_parameter("spill_pos", spill_pos)
		m.set_shader_parameter("spill_col", spill_col)
		m.set_shader_parameter("spill_count", spill_pos.size())

	_build_player_and_camera()
	_build_post()

	var shots := ScreenshotRunner.wanted()
	if not shots.is_empty():
		var runner := ScreenshotRunner.new()
		add_child(runner)
		runner.run(self, shots)


# ---------------------------------------------------------------- textures

func _load_textures() -> void:
	var files := {
		"city": "textures/ground_city_cobblestone.png",
		"cyber": "textures/ground_cyber_metal_panel.png",
		"slate": "textures/ground_cultivation_slate.png",
		"grass": "textures/ground_wild_grass.png",
		"cliff": "textures/cliff_rock_strata.png",
		"water": "textures/water_shallow.png",
		"wood": "textures/wood_planks.png",
		"road": "tilesets/road_cobblestone_dualgrid.png",
		"dirt": "tilesets/dirt_dualgrid.png",
	}
	for k in files:
		tex[k] = _load_png(files[k], k == "road" or k == "dirt")
	for c in layout["sprites"]:
		var p: String = c["texture"]
		if not tex.has(p):
			tex[p] = _load_png(p, true)


func _load_png(rel: String, bleed: bool) -> ImageTexture:
	var img := Image.load_from_file(ProjectSettings.globalize_path(ASSET + rel))
	img.convert(Image.FORMAT_RGBA8)
	var avg := Color(0, 0, 0)
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				avg += Color(c.r, c.g, c.b) * 1.0
				n += 1
	avg = avg / maxf(n, 1)
	tex_avg[rel] = Vector3(pow(avg.r, 2.2), pow(avg.g, 2.2), pow(avg.b, 2.2))
	if bleed:
		_bleed_alpha(img)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Spread colour into transparent texels so mipmaps don't pick up dark fringes.
func _bleed_alpha(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for _pass in 4:
		var src: Image = img.duplicate()
		for y in h:
			for x in w:
				if src.get_pixel(x, y).a > 0.01:
					continue
				var acc := Color(0, 0, 0, 0)
				var cnt := 0
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = Vector2i(x, y) + d
					if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
						continue
					var c := src.get_pixel(q.x, q.y)
					if c.a > 0.01 or (c.r + c.g + c.b) > 0.0:
						acc += Color(c.r, c.g, c.b, 0)
						cnt += 1
				if cnt > 0:
					img.set_pixel(x, y, Color(acc.r / cnt, acc.g / cnt, acc.b / cnt, 0.0))


func _avg(rel: String) -> Vector3:
	return tex_avg.get(rel, Vector3(0.5, 0.5, 0.5))


# ---------------------------------------------------------------- helpers

static func _v3(a) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func _col(a) -> Color:
	return Color(a[0], a[1], a[2])


func _xform(t: Dictionary) -> Transform3D:
	return Transform3D(Basis(_v3(t["basis_x"]), _v3(t["basis_y"]), _v3(t["basis_z"])), _v3(t["origin"]))


func _mesh_by_name(n: String) -> Dictionary:
	for m in layout["meshes"]:
		if m["name"] == n:
			return m
	return {}


func _spill_mat(sh: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	spill_materials.append(m)
	return m


## Emissive surfaces that tint nearby ground/walls (fake one-bounce GI).
func _collect_emitters() -> void:
	for m in layout["meshes"]:
		var n: String = m["name"]
		var mat: Dictionary = m["material"]
		if mat["emission"] == null:
			continue
		var o := _v3(m["transform"]["origin"])
		var c := _col(mat["emission"])
		var strength := 0.0
		var radius := 2.0
		if n.contains("Window"):
			o += Vector3(0, -0.2, 0.45)
			strength = 0.32
			radius = 2.4
		elif n.contains("Strip") or n.contains("Edge"):
			o += Vector3(0, 0, 0.5)
			strength = 0.22
			radius = 2.6
		elif n.contains("RedLantern"):
			c = Color(1.0, 0.45, 0.25)
			strength = 0.25
			radius = 2.2
		if strength > 0.0 and spill_pos.size() < 24:
			spill_pos.append(Vector4(o.x, o.y, o.z, radius))
			spill_col.append(Vector4(c.r * strength, c.g * strength, c.b * strength, 0.0))


# ---------------------------------------------------------------- terrain

## Adds a quad (a,b,c,d in order around the face) whose front faces `n`.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, uv2s := [], col := Color(1, 1, 1)) -> void:
	var pts := [a, b, c, d]
	var idx := [0, 1, 2, 0, 2, 3]
	if (b - a).cross(c - a).dot(n) > 0.0:
		idx = [0, 2, 1, 0, 3, 2]
	for i in idx:
		st.set_normal(n)
		st.set_color(col)
		if uv2s.size() == 4:
			st.set_uv2(uv2s[i])
		st.add_vertex(pts[i])


func _build_terrain() -> void:
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	const C := TerrainData.CELL
	for cz in range(td.oz, td.oz + td.h):
		for cx in range(td.ox, td.ox + td.w):
			var cen := Vector3(cx * C, 0, cz * C)
			if not td.is_water(cx, cz):
				var nw := cen + Vector3(-C / 2, td.top_at(cx, cz, -0.5, -0.5), -C / 2)
				var ne := cen + Vector3(C / 2, td.top_at(cx, cz, 0.5, -0.5), -C / 2)
				var se := cen + Vector3(C / 2, td.top_at(cx, cz, 0.5, 0.5), C / 2)
				var sw := cen + Vector3(-C / 2, td.top_at(cx, cz, -0.5, 0.5), C / 2)
				var n := (se - nw).cross(ne - sw).normalized()
				if n.y < 0:
					n = -n
				_quad(top, nw, ne, se, sw, n)
			# vertical faces toward each lower neighbour
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var p := Vector2(-d.y, d.x)
				var nb: Vector2i = Vector2i(cx, cz) + d
				var a0 := Vector2(d) * 0.5 + p * 0.5
				var a1 := Vector2(d) * 0.5 - p * 0.5
				var ha0 := td.top_at(cx, cz, a0.x, a0.y)
				var ha1 := td.top_at(cx, cz, a1.x, a1.y)
				var hb0 := td.top_at(nb.x, nb.y, a0.x - d.x, a0.y - d.y)
				var hb1 := td.top_at(nb.x, nb.y, a1.x - d.x, a1.y - d.y)
				if ha0 < hb0 - 1e-4 or ha1 < hb1 - 1e-4:
					continue
				if ha0 - hb0 < 1e-3 and ha1 - hb1 < 1e-3:
					continue
				var w0 := Vector3((cx + a0.x) * C, 0, (cz + a0.y) * C)
				var w1 := Vector3((cx + a1.x) * C, 0, (cz + a1.y) * C)
				var nrm := Vector3(d.x, 0, d.y)
				var water_b := td.inside(nb.x, nb.y) and td.is_water(nb.x, nb.y)
				var wy := td.water_surface(nb.x, nb.y) if water_b else -2.0
				var grass_top := td.bio(cx, cz) == 3 and not td.is_water(cx, cz) and (td.ov(cx, cz) & 3) == 0
				var col := Color(1.0 if water_b else 0.0, (wy + 2.0) / 4.0, 1.0 if grass_top else 0.0)
				_quad(walls,
					w0 + Vector3(0, ha0, 0), w1 + Vector3(0, ha1, 0),
					w1 + Vector3(0, hb1, 0), w0 + Vector3(0, hb0, 0), nrm,
					[Vector2(ha0, hb0), Vector2(ha1, hb1), Vector2(ha1, hb1), Vector2(ha0, hb0)], col)

	var tm := _spill_mat(SH_TERRAIN)
	tm.set_shader_parameter("data_tex", data_tex)
	tm.set_shader_parameter("map_origin", Vector2i(td.ox, td.oz))
	tm.set_shader_parameter("map_size", Vector2i(td.w, td.h))
	tm.set_shader_parameter("tex_city", tex["city"])
	tm.set_shader_parameter("tex_cyber", tex["cyber"])
	tm.set_shader_parameter("tex_slate", tex["slate"])
	tm.set_shader_parameter("tex_grass", tex["grass"])
	tm.set_shader_parameter("atlas_road", tex["road"])
	tm.set_shader_parameter("atlas_dirt", tex["dirt"])
	for m in layout["meshes"]:
		var n: String = m["name"]
		if m["mesh"] == "BoxMesh" and (n.contains("Building") or n.contains("Tower") or n.contains("TempleBase")):
			var o := _v3(m["transform"]["origin"])
			var s := _v3(m["size"])
			ao_rects.append(Vector4(o.x - s.x / 2, o.z - s.z / 2, o.x + s.x / 2, o.z + s.z / 2))
			ao_rect_h.append(o.y + s.y / 2)
	tm.set_shader_parameter("ao_rects", ao_rects)
	tm.set_shader_parameter("ao_rect_h", ao_rect_h)
	tm.set_shader_parameter("ao_rect_count", ao_rects.size())
	var mi := MeshInstance3D.new()
	mi.name = "TerrainTop"
	mi.mesh = top.commit()
	mi.material_override = tm
	world.add_child(mi)

	var cm := _spill_mat(SH_CLIFF)
	cm.set_shader_parameter("tex_cliff", tex["cliff"])
	cm.set_shader_parameter("tex_grass", tex["grass"])
	cm.set_shader_parameter("tex_lip", tex["city"])
	var wi := MeshInstance3D.new()
	wi.name = "TerrainCliffs"
	wi.mesh = walls.commit()
	wi.material_override = cm
	world.add_child(wi)


# ---------------------------------------------------------------- water

func _build_water() -> void:
	const C := TerrainData.CELL
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var falls: Array = []   # [x0, x1, z, along_x, y_top, y_bottom, dir]
	for cz in range(td.oz, td.oz + td.h):
		for cx in range(td.ox, td.ox + td.w):
			if not td.is_water(cx, cz):
				continue
			var y := td.water_surface(cx, cz)
			var cen := Vector3(cx * C, y, cz * C)
			_quad(st, cen + Vector3(-C / 2, 0, -C / 2), cen + Vector3(C / 2, 0, -C / 2),
				cen + Vector3(C / 2, 0, C / 2), cen + Vector3(-C / 2, 0, C / 2), Vector3.UP)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb: Vector2i = Vector2i(cx, cz) + d
				var lower := -100.0
				if not td.inside(nb.x, nb.y):
					lower = TerrainData.OUTER_Y
				elif td.is_water(nb.x, nb.y) and td.lvl(nb.x, nb.y) < td.lvl(cx, cz):
					lower = td.water_surface(nb.x, nb.y)
				if lower > -50.0:
					falls.append({"cell": Vector2i(cx, cz), "dir": d, "top": y, "bottom": lower,
						"main": td.inside(nb.x, nb.y)})
	var wm := _spill_mat(SH_WATER)
	wm.set_shader_parameter("data_tex", data_tex)
	wm.set_shader_parameter("map_origin", Vector2i(td.ox, td.oz))
	wm.set_shader_parameter("map_size", Vector2i(td.w, td.h))
	wm.set_shader_parameter("tex_water", tex["water"])
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = st.commit()
	mi.material_override = wm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)

	var fm := ShaderMaterial.new()
	fm.shader = SH_FALL
	fm.set_shader_parameter("tex_water", tex["water"])
	for f in falls:
		_build_fall(f, fm)


## Waterfall sheet curling over the lip and dropping to the lower pool.
func _build_fall(f: Dictionary, mat: ShaderMaterial) -> void:
	const C := TerrainData.CELL
	var c: Vector2i = f["cell"]
	var d: Vector2i = f["dir"]
	var dv := Vector3(d.x, 0, d.y)
	var side := Vector3(-d.y, 0, d.x)
	var edge := Vector3(c.x * C, 0, c.y * C) + dv * (C / 2)
	var top: float = f["top"]
	var bot: float = f["bottom"]
	var drop := top - bot
	# profile: (outward offset, y)
	var prof: Array = []
	var rows := 10
	for i in rows + 1:
		var t := float(i) / rows
		var out := -0.12 + 0.2 * sqrt(t) + 0.04 * t
		var y := top + 0.02 - drop * (t * t * 0.55 + t * 0.45) - (0.04 if i == rows else 0.0)
		prof.append(Vector2(out, y))
	var lengths: Array = [0.0]
	for i in range(1, prof.size()):
		lengths.append(lengths[i - 1] + (prof[i] - prof[i - 1]).length())
	var total: float = lengths[-1]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 8
	var half := C / 2 - 0.02
	for i in rows:
		for j in cols:
			var s0 := -half + 2.0 * half * j / cols
			var s1 := -half + 2.0 * half * (j + 1) / cols
			var quad := []
			for k in [[i, s0], [i, s1], [i + 1, s1], [i + 1, s0]]:
				var pr: Vector2 = prof[k[0]]
				var pos: Vector3 = edge + dv * pr.x + side * float(k[1]) + Vector3(0, pr.y, 0)
				quad.append({"p": pos, "uv": Vector2((pos.x + pos.z) / C, lengths[k[0]]),
					"uv2": Vector2(total, (float(k[1]) + half) / (2.0 * half))})
			var n := dv + Vector3(0, 0.3, 0)
			for vi in [0, 1, 2, 0, 2, 3]:
				st.set_normal(n.normalized())
				st.set_uv(quad[vi]["uv"])
				st.set_uv2(quad[vi]["uv2"])
				st.add_vertex(quad[vi]["p"])
	var mi := MeshInstance3D.new()
	mi.name = "Waterfall"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)


# ---------------------------------------------------------------- bridges

func _wood_mat(albedo: Color, swap := false) -> ShaderMaterial:
	var m := _spill_mat(SH_PROP)
	m.set_shader_parameter("mode", 1)
	m.set_shader_parameter("albedo", albedo)
	m.set_shader_parameter("roughness", 0.75)
	m.set_shader_parameter("tex", tex["wood"])
	m.set_shader_parameter("tex_avg", _avg("textures/wood_planks.png"))
	m.set_shader_parameter("swap_top_uv", swap)
	m.set_shader_parameter("ground_y", -5.0)
	m.set_shader_parameter("bump_strength", 2.5)
	return m


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, nm := "Box") -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _build_bridges() -> void:
	const C := TerrainData.CELL
	var deck_mat := _wood_mat(Color(0.62, 0.42, 0.27), false)
	var rail_mat := _wood_mat(Color(0.45, 0.3, 0.19))
	for cz in range(td.oz, td.oz + td.h):
		for cx in range(td.ox, td.ox + td.w):
			if not td.is_bridge(cx, cz):
				continue
			var root := Node3D.new()
			root.name = "Bridge_%d_%d" % [cx, cz]
			root.position = Vector3(cx * C, 0, cz * C)
			if not td.bridge_along_x(cx, cz):
				root.rotation.y = PI / 2
			world.add_child(root)
			var top := td.bridge_top(cx, cz)
			var length := C + 0.5
			_add_box(root, Vector3(length, 0.1, 1.3), Vector3(0, top - 0.05, 0), deck_mat, "Deck")
			for s in [-1.0, 1.0]:
				_add_box(root, Vector3(length, 0.16, 0.12), Vector3(0, top - 0.17, s * 0.5), rail_mat, "Stringer")
				for a in [-0.85, 0.0, 0.85]:
					_add_box(root, Vector3(0.08, 0.6, 0.08), Vector3(a, top + 0.25, s * 0.62), rail_mat, "Post")
				_add_box(root, Vector3(length - 0.3, 0.06, 0.07), Vector3(0, top + 0.52, s * 0.62), rail_mat, "Rail")
				_add_box(root, Vector3(length - 0.3, 0.04, 0.05), Vector3(0, top + 0.27, s * 0.62), rail_mat, "MidRail")
			# piers down into the stream bed
			var bed := td.lvl(cx, cz) * TerrainData.LAYER + TerrainData.YOFF
			for a in [-0.55, 0.55]:
				for s in [-0.45, 0.45]:
					var hgt := top - 0.2 - bed
					_add_box(root, Vector3(0.1, hgt, 0.1), Vector3(a, bed + hgt / 2, s), rail_mat, "Pier")
			for o in [-0.6, 0.6]:
				obstacles.append({"min": Vector2(cx * C - 0.9, cz * C + o - 0.06) if td.bridge_along_x(cx, cz) else Vector2(cx * C + o - 0.06, cz * C - 0.9),
					"max": Vector2(cx * C + 0.9, cz * C + o + 0.06) if td.bridge_along_x(cx, cz) else Vector2(cx * C + o + 0.06, cz * C + 0.9),
					"bottom": top, "top": top + 0.55, "walk": false})


# ---------------------------------------------------------------- layout meshes

func _build_layout_meshes() -> void:
	var root := Node3D.new()
	root.name = "Props"
	world.add_child(root)
	var i := 0
	for m in layout["meshes"]:
		i += 1
		var n: String = m["name"]
		var mesh: Mesh
		var half := Vector3(0.5, 0.5, 0.5)
		match m["mesh"]:
			"BoxMesh":
				var b := BoxMesh.new()
				b.size = _v3(m["size"])
				half = b.size / 2
				mesh = b
			"CylinderMesh":
				var c := CylinderMesh.new()
				c.height = m["height"]
				c.top_radius = m["top_radius"]
				c.bottom_radius = m["bottom_radius"]
				c.radial_segments = 20
				c.rings = 1
				half = Vector3(c.top_radius, c.height / 2, c.top_radius)
				mesh = c
			"PrismMesh":
				var p := PrismMesh.new()
				p.size = _v3(m["size"])
				p.left_to_right = m.get("left_to_right", 0.5)
				half = p.size / 2
				mesh = p
		var xf := _xform(m["transform"])
		var mi := MeshInstance3D.new()
		mi.name = n.replace("/", "_")
		mi.mesh = mesh
		mi.transform = xf
		mi.material_override = _material_for(n, m["material"], half, i, xf.origin.y - half.y)
		root.add_child(mi)
		# light housings must not swallow the light placed inside them
		var is_housing := n.ends_with("/Lamp") or n.contains("City/Lantern") or n.contains("RedLantern")
		if is_housing or n.contains("Window") or n.contains("Strip") or n.contains("Edge"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# collision footprint
		var bottom := xf.origin.y - half.y
		var top := xf.origin.y + half.y
		if bottom < 2.0 and not (n.contains("Window") or n.contains("Strip") or n.contains("Edge") or n.contains("Door")):
			var ext := Vector2(absf(xf.basis.x.x) * half.x + absf(xf.basis.z.x) * half.z,
				absf(xf.basis.x.z) * half.x + absf(xf.basis.z.z) * half.z)
			if m["mesh"] == "CylinderMesh":
				ext = Vector2(half.x, half.z)
			var walk := n.contains("TempleBase") or n.contains("Step")
			obstacles.append({"min": Vector2(xf.origin.x, xf.origin.z) - ext, "max": Vector2(xf.origin.x, xf.origin.z) + ext,
				"bottom": bottom, "top": top, "walk": walk})


func _material_for(n: String, mat: Dictionary, half: Vector3, idx: int, bottom: float) -> ShaderMaterial:
	var m := _spill_mat(SH_PROP)
	var alb := _col(mat["albedo"])
	m.set_shader_parameter("albedo", alb)
	m.set_shader_parameter("roughness", mat["roughness"])
	m.set_shader_parameter("metallic", mat["metallic"])
	m.set_shader_parameter("box_half", half)
	m.set_shader_parameter("seed", float(idx) * 1.37)
	m.set_shader_parameter("ground_y", bottom)
	if mat["emission"] != null:
		m.set_shader_parameter("emission_color", _col(mat["emission"]))
		m.set_shader_parameter("emission_energy", mat["emission_energy"])
	var mode := 0
	if n.contains("Window"):
		mode = 4
	elif n.contains("Strip") or n.contains("Edge"):
		mode = 6
	elif n.contains("RedLantern"):
		mode = 9
	elif n.ends_with("/Lamp") or n.contains("City/Lantern"):
		mode = 5
	elif n.contains("Building"):
		mode = 2
	elif n.contains("City/Roof"):
		mode = 3
	elif n.contains("Tower"):
		mode = 7
		m.set_shader_parameter("tex", tex["cyber"])
		m.set_shader_parameter("tex_avg", _avg("textures/ground_cyber_metal_panel.png"))
		m.set_shader_parameter("bump_strength", 1.2)
	elif n.contains("TempleRoof") or n.contains("RoofEaves"):
		mode = 8
	elif n.contains("TempleBase") or n.contains("Step"):
		mode = 1
		m.set_shader_parameter("tex", tex["slate"])
		m.set_shader_parameter("tex_avg", _avg("textures/ground_cultivation_slate.png"))
	elif n.contains("Pillar") or n.contains("Post") or n.contains("Cap") or n.contains("Door"):
		mode = 1
		m.set_shader_parameter("tex", tex["wood"])
		m.set_shader_parameter("tex_avg", _avg("textures/wood_planks.png"))
		if n.contains("Pillar"):
			m.set_shader_parameter("use_mesh_uv", true)
			m.set_shader_parameter("mesh_uv_scale", Vector2(0.5, 1.4))
	elif n.contains("Lamppost"):
		mode = 0
		m.set_shader_parameter("roughness", 0.45)
		m.set_shader_parameter("metallic", 0.5)
	m.set_shader_parameter("mode", mode)
	return m


# ---------------------------------------------------------------- lights

func _build_lights() -> void:
	var moon: Dictionary = layout["moon"]
	var dl := DirectionalLight3D.new()
	dl.name = "Moon"
	dl.light_color = _col(moon["color"])
	dl.light_energy = moon["energy"]
	dl.basis = Basis.looking_at(_v3(moon["direction_light_travels"]).normalized(), Vector3.UP)
	dl.shadow_enabled = true
	dl.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	dl.directional_shadow_max_distance = 48.0
	dl.directional_shadow_split_1 = 0.35
	dl.light_angular_distance = 1.6
	dl.shadow_blur = 1.4
	dl.shadow_bias = 0.04
	dl.shadow_normal_bias = 1.2
	dl.light_volumetric_fog_energy = 0.35
	dl.light_indirect_energy = 1.0
	world.add_child(dl)

	for L in layout["lights"]:
		var n: String = L["name"]
		var light: Light3D
		if L["type"] == "SpotLight3D":
			var sp := SpotLight3D.new()
			sp.spot_angle = L["angle_deg"]
			sp.spot_range = L["range"]
			sp.spot_angle_attenuation = 0.8
			sp.rotation_degrees = Vector3(-90, 0, 0)
			sp.light_volumetric_fog_energy = 1.6
			light = sp
		else:
			var om := OmniLight3D.new()
			om.omni_range = L["range"]
			om.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
			om.light_volumetric_fog_energy = 1.2 if not n.contains("Wash") else 0.7
			light = om
		light.name = n.replace("/", "_")
		light.position = _v3(L["position"])
		light.light_color = _col(L["color"])
		light.light_energy = L["energy"]
		light.shadow_enabled = L["shadows"]
		light.light_size = 0.06
		light.shadow_blur = 1.2
		light.shadow_bias = 0.06
		light.shadow_normal_bias = 1.5
		light.light_specular = 0.8
		world.add_child(light)

	# visible glow around every light source
	for m in layout["meshes"]:
		var n: String = m["name"]
		var o := _v3(m["transform"]["origin"])
		if n.ends_with("/Lamp"):
			_add_halo(o, Color(1.0, 0.68, 0.38), 1.3, 0.55)
		elif n.contains("City/Lantern"):
			_add_halo(o, Color(1.0, 0.76, 0.48), 1.9, 0.6)
		elif n.contains("RedLantern"):
			_add_halo(o, Color(1.0, 0.42, 0.22), 1.6, 0.55)
		elif n.contains("Window"):
			_add_halo(o + Vector3(0, 0, 0.05), Color(1.0, 0.75, 0.45), 1.3, 0.12, 0.05)
		elif n.contains("Strip"):
			var c := _col(m["material"]["emission"])
			_add_halo(o + Vector3(0, 0, 0.05), c, 1.4, 0.07, 0.05)
	for L in layout["lights"]:
		var n: String = L["name"]
		var p := _v3(L["position"])
		if n.contains("SpiritLight"):
			_add_halo(p, _col(L["color"]), 0.9, 0.3)
			_add_halo(p, Color(0.8, 1.0, 0.9), 0.22, 0.6)
		elif n.contains("Wash"):
			_add_halo(p, _col(L["color"]), 3.0, 0.08)
		elif n.contains("ForestGlade"):
			_add_halo(p, _col(L["color"]), 3.0, 0.06)


func _add_halo(pos: Vector3, c: Color, size: float, intensity: float, pull := 0.3) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := ShaderMaterial.new()
	m.shader = SH_HALO
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("pull", pull)
	var mi := MeshInstance3D.new()
	mi.name = "Halo"
	mi.mesh = q
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.custom_aabb = AABB(Vector3(-size, -size, -size), Vector3(size, size, size) * 2)
	world.add_child(mi)


func _build_fog_volumes() -> void:
	for fv in layout["fog_volumes"]:
		var v := FogVolume.new()
		v.name = String(fv["name"]).replace("/", "_")
		v.position = _v3(fv["center"])
		v.size = _v3(fv["size"])
		v.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
		var m := FogMaterial.new()
		if String(fv["name"]).contains("Waterfall"):
			m.density = 0.55
			m.albedo = Color(0.85, 0.9, 0.92)
			m.edge_fade = 0.6
		else:
			m.density = 0.07
			m.albedo = Color(1.0, 0.92, 0.82)
			m.edge_fade = 0.7
		v.material = m
		world.add_child(v)


# ---------------------------------------------------------------- particles

func _build_particles() -> void:
	for p in layout["particles"]:
		var c := _v3(p["center"])
		var ext := Vector3(4.5, 0.6, 3.2)
		if String(p["name"]).contains("Highland"):
			ext = Vector3(6.0, 0.5, 2.6)
		elif String(p["name"]).contains("Lowland"):
			ext = Vector3(6.0, 0.6, 3.4)
		_fireflies(c, int(p["amount"]), ext, String(p["name"]).replace("/", "_"))
	# waterfall spray
	for fv in layout["fog_volumes"]:
		if String(fv["name"]).contains("Waterfall"):
			_mist(_v3(fv["center"]) + Vector3(0, -0.1, 0))
	# spirit wisps around the jade light
	for L in layout["lights"]:
		if String(L["name"]).contains("SpiritLight"):
			_wisps(_v3(L["position"]), _col(L["color"]))


func _fireflies(center: Vector3, amount: int, ext: Vector3, nm: String) -> void:
	var gp := GPUParticles3D.new()
	gp.name = nm
	gp.position = center
	gp.amount = amount
	gp.lifetime = 8.0
	gp.preprocess = 8.0
	gp.randomness = 0.6
	gp.fixed_fps = 0
	gp.visibility_aabb = AABB(-ext - Vector3(2, 2, 2), (ext + Vector3(2, 2, 2)) * 2)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = ext
	pm.gravity = Vector3.ZERO
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.0
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_noise_speed_random = 0.4
	pm.turbulence_influence_min = 0.04
	pm.turbulence_influence_max = 0.12
	pm.damping_min = 0.1
	pm.damping_max = 0.3
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.15, Color(1, 1, 1, 1))
	g.add_point(0.85, Color(1, 1, 1, 1))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.2, 0.2)
	var m := ShaderMaterial.new()
	m.shader = SH_FIREFLY
	q.material = m
	gp.draw_pass_1 = q
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(gp)


func _mist(pos: Vector3) -> void:
	var gp := GPUParticles3D.new()
	gp.name = "WaterfallSpray"
	gp.position = pos
	gp.amount = 60
	gp.lifetime = 3.2
	gp.preprocess = 3.0
	gp.visibility_aabb = AABB(Vector3(-3, -2, -3), Vector3(6, 5, 6))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.65, 0.05, 0.25)
	pm.direction = Vector3(0, 0.6, 1)
	pm.spread = 50.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0, 0.22, 0)
	pm.damping_min = 0.3
	pm.damping_max = 0.5
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 1.4))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.2, Color(1, 1, 1, 1))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	var m := ShaderMaterial.new()
	m.shader = SH_MIST
	m.set_shader_parameter("opacity", 0.3)
	q.material = m
	gp.draw_pass_1 = q
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(gp)


func _wisps(pos: Vector3, c: Color) -> void:
	var gp := GPUParticles3D.new()
	gp.name = "SpiritWisps"
	gp.position = pos
	gp.amount = 14
	gp.lifetime = 4.0
	gp.preprocess = 4.0
	gp.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.25
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.1
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.3, Color(1, 1, 1, 1))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.1, 0.1)
	var m := ShaderMaterial.new()
	m.shader = SH_FIREFLY
	m.set_shader_parameter("color", c.lightened(0.3))
	m.set_shader_parameter("intensity", 1.2)
	q.material = m
	gp.draw_pass_1 = q
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(gp)


# ---------------------------------------------------------------- sprites

const FEET_PAD := 3.0 / 64.0 * 1.5   # transparent rows below the feet in the 64x64 art

func make_sprite(texture_path: String) -> Node3D:
	var root := Node3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.5, 1.5)
	var m := ShaderMaterial.new()
	m.shader = SH_SPRITE
	m.set_shader_parameter("tex", tex[texture_path])
	var mi := MeshInstance3D.new()
	mi.name = "Sprite"
	mi.mesh = q
	mi.material_override = m
	mi.position = Vector3(0, 0.75 - FEET_PAD, 0)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mi)
	var b := QuadMesh.new()
	b.size = Vector2(0.8, 0.45)
	b.orientation = PlaneMesh.FACE_Y
	var bm := ShaderMaterial.new()
	bm.shader = SH_BLOB
	var bi := MeshInstance3D.new()
	bi.name = "Blob"
	bi.mesh = b
	bi.material_override = bm
	bi.position = Vector3(0, 0.015, 0)
	bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bi)
	return root


func _build_sprites() -> void:
	for s in layout["sprites"]:
		if String(s["name"]).begins_with("Player"):
			continue
		var c := _v3(s["center_position"])
		var sp := make_sprite(s["texture"])
		sp.name = String(s["name"]).replace("/", "_")
		sp.position = Vector3(c.x, td.surface_height(c.x, c.z), c.z)
		world.add_child(sp)
		(sp.get_node("Sprite") as MeshInstance3D).material_override.set_shader_parameter("flip_h", s["flip_h"])


# ---------------------------------------------------------------- environment

func _build_environment() -> void:
	env = Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = SH_SKY
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.33, 0.36)
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.15
	env.tonemap_white = 6.0

	env.ssr_enabled = true
	env.ssr_max_steps = 96
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 1.5
	env.ssr_depth_tolerance = 0.25

	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15

	env.ssil_enabled = true
	env.ssil_radius = 3.0
	env.ssil_intensity = 1.2

	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_read_sky_light = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.12
	env.sdfgi_energy = 1.2
	env.sdfgi_bounce_feedback = 0.4
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT

	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 0.9
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.set("glow_levels/1", 0.0)
	env.set("glow_levels/2", 0.6)
	env.set("glow_levels/3", 1.0)
	env.set("glow_levels/4", 0.8)
	env.set("glow_levels/5", 0.5)
	env.set("glow_levels/6", 0.2)

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.15, 0.15, 0.22)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.05
	env.fog_density = 0.016
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.25
	env.fog_height = -1.2
	env.fog_height_density = 0.18

	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.007
	env.volumetric_fog_albedo = Color(0.92, 0.88, 0.84)
	env.volumetric_fog_emission = Color(0.012, 0.012, 0.018)
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_length = 40.0
	env.volumetric_fog_detail_spread = 1.6
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_ambient_inject = 0.12
	env.volumetric_fog_sky_affect = 0.2
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.85

	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.02
	env.adjustment_saturation = 1.05

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_player_and_camera() -> void:
	var pl: Dictionary = layout["player"]
	player = PlayerScript.new()
	player.name = "Player"
	player.setup(self, td, obstacles, float(pl["speed"]))
	var spr := make_sprite("characters/char_00_modern_youth.png")
	spr.name = "Visual"
	player.add_child(spr)
	add_child(player)
	var sp := _v3(pl["spawn"])
	player.place(Vector2(sp.x, sp.z))

	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	var cam_cfg: Dictionary = layout["camera"]
	rig.setup(player, 25.0, float(cam_cfg["pitch_deg"]), float(cam_cfg["distance"]))
	rig.snap()


func _build_post() -> void:
	var cl := CanvasLayer.new()
	cl.name = "Post"
	cl.layer = 10
	var cr := ColorRect.new()
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = SH_POST
	cr.material = m
	cl.add_child(cr)
	add_child(cl)

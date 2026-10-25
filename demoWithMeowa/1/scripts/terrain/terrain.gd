@tool
class_name Terrain
extends Node3D

const WATER_LIGHT_LAYER := 1 << 16 # Layer 17; beam accents use 18, mirrors use 19/20.

## 根据 TerrainData 生成分层地形：平台顶面、崖壁、坡道、水面、瀑布、桥与碰撞体。
## 生成的子节点不写入场景文件，每次加载时重新生成。

@export var data: TerrainData:
	set(value):
		if data and data.changed.is_connected(_queue_rebuild):
			data.changed.disconnect(_queue_rebuild)
		data = value
		if data:
			data.changed.connect(_queue_rebuild)
		_queue_rebuild()

@export var top_material: ShaderMaterial
@export var wall_material: Material
@export var water_material: Material
@export var waterfall_material: Material
@export var bridge_material: Material
## 地图外缘崖壁向下延伸到的层级
@export var skirt_level := -2

@export_group("草地与崖壁材质衔接")
## 关闭后恢复原来的草沿和阴影线，不改变地形几何。
@export var grass_transition_enabled := true:
	set(value): grass_transition_enabled = value; _queue_transition_apply()
## 草地纹理向崖面延伸的厚度（纹理像素）。
@export_range(0.0, 8.0, 0.5) var grass_lip_pixels := 3.0:
	set(value): grass_lip_pixels = value; _queue_transition_apply()
## 草沿厚度的固定斑驳变化，0 表示整齐边缘。
@export_range(0.0, 4.0, 0.5) var grass_edge_variation := 2.0:
	set(value): grass_edge_variation = value; _queue_transition_apply()
## 草沿下方逐渐融入岩壁的距离（米）。
@export_range(0.0, 0.4, 0.01) var grass_transition_height := 0.16:
	set(value): grass_transition_height = value; _queue_transition_apply()
## 岩壁上下接缝处使用现有草地纹理的覆盖强度。
@export_range(0.0, 1.0, 0.05) var grass_moss_strength := 0.4:
	set(value): grass_moss_strength = value; _queue_transition_apply()
## 草沿下的柔和阴影强度。
@export_range(0.0, 0.5, 0.01) var grass_lip_shadow := 0.16:
	set(value): grass_lip_shadow = value; _queue_transition_apply()
## 崖脚与下层草地衔接的距离（米），0 关闭。
@export_range(0.0, 0.4, 0.01) var grass_base_blend_height := 0.16:
	set(value): grass_base_blend_height = value; _queue_transition_apply()

## 崖顶草沿 / 石沿的颜色，按区域类型索引
const LIP_COLORS: Array[Color] = [
	Color(0.55, 0.53, 0.5), Color(0.3, 0.34, 0.42), Color(0.45, 0.62, 0.5), Color(0.36, 0.6, 0.26)]
const DIRECTIONS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const BRIDGE_WIDTH := 1.3
const BRIDGE_THICKNESS := 0.12
const RAIL_HEIGHT := 0.55

var _map_texture: ImageTexture
var _rebuild_queued := false
var _generated: Node3D
var _transition_apply_queued := false

func _ready() -> void:
	_rebuild()

func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	_rebuild.call_deferred()

func _queue_transition_apply() -> void:
	if _transition_apply_queued or not is_inside_tree():
		return
	_transition_apply_queued = true
	_apply_grass_transition.call_deferred()

func _apply_grass_transition() -> void:
	_transition_apply_queued = false
	var wall := wall_material as ShaderMaterial
	if not wall or not top_material:
		return
	wall.set_shader_parameter("transition_enabled", grass_transition_enabled)
	wall.set_shader_parameter("grass_texture", top_material.get_shader_parameter("wild_texture"))
	wall.set_shader_parameter("grass_tint", top_material.get_shader_parameter("wild_tint"))
	wall.set_shader_parameter("grass_lip_pixels", grass_lip_pixels)
	wall.set_shader_parameter("edge_variation_pixels", grass_edge_variation)
	wall.set_shader_parameter("transition_height", grass_transition_height)
	wall.set_shader_parameter("moss_strength", grass_moss_strength)
	wall.set_shader_parameter("lip_shadow_strength", grass_lip_shadow)
	wall.set_shader_parameter("base_blend_height", grass_base_blend_height)

func _rebuild() -> void:
	_rebuild_queued = false
	if _generated:
		_generated.free()
		_generated = null
	if not data or data.size.x <= 0 or data.size.y <= 0:
		return
	_generated = Node3D.new()
	_generated.name = "Generated"
	add_child(_generated)

	var collision_faces := PackedVector3Array()
	var top := _build_tops(collision_faces)
	var walls := _build_walls(collision_faces)
	var water := _build_water()
	var waterfalls := _build_waterfalls()
	var bridges := _build_bridges(collision_faces)
	_add_mesh("Top", top, top_material)
	_add_mesh("Walls", walls, wall_material)
	_add_mesh("Water", water, water_material, false)
	_add_mesh("Waterfalls", waterfalls, waterfall_material, false)
	_add_mesh("Bridges", bridges, bridge_material)
	_build_collision(collision_faces)
	_upload_map()

# ---------- 格子高度 ----------

func _level(cell: Vector2i) -> int:
	return data.get_level(cell) if data.has_cell(cell) else skirt_level

func _is(cell: Vector2i, flag: int) -> bool:
	return data.has_overlay(cell, flag)

## 坡道朝向：返回比它高一层的相邻方向，没有则为 ZERO
func _ramp_direction(cell: Vector2i) -> Vector2i:
	if not _is(cell, TerrainData.OVERLAY_RAMP):
		return Vector2i.ZERO
	var level := _level(cell)
	for direction in DIRECTIONS:
		var neighbor := cell + direction
		if data.has_cell(neighbor) and _level(neighbor) == level + 1 and not _is(neighbor, TerrainData.OVERLAY_RAMP):
			return direction
	return Vector2i.ZERO

## 格子四角的高度（米），顺序：西北、东北、东南、西南
func _corner_heights(cell: Vector2i) -> PackedFloat32Array:
	var y := _level(cell) * data.layer_height
	var corners := PackedFloat32Array([y, y, y, y])
	var up := _ramp_direction(cell)
	if up != Vector2i.ZERO:
		var raised := y + data.layer_height
		if up.y < 0:
			corners[0] = raised
			corners[1] = raised
		elif up.x > 0:
			corners[1] = raised
			corners[2] = raised
		elif up.y > 0:
			corners[2] = raised
			corners[3] = raised
		else:
			corners[3] = raised
			corners[0] = raised
	return corners

## 格子四角的水平坐标，顺序同上
func _corner_points(cell: Vector2i) -> Array[Vector2]:
	var half := data.cell_size * 0.5
	var center := Vector2(cell) * data.cell_size
	return [center + Vector2(-half, -half), center + Vector2(half, -half),
		center + Vector2(half, half), center + Vector2(-half, half)]

# ---------- 顶面 ----------

func _build_tops(collision_faces: PackedVector3Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in data.size.y:
		for x in data.size.x:
			var cell := data.origin + Vector2i(x, z)
			var heights := _corner_heights(cell)
			var points := _corner_points(cell)
			var quad: Array[Vector3] = []
			for i in 4:
				quad.append(Vector3(points[i].x, heights[i], points[i].y))
			_add_quad(st, quad, collision_faces)
	st.generate_normals()
	return st.commit()

# ---------- 崖壁 ----------

func _build_walls(collision_faces: PackedVector3Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 每个方向对应的边：两个角的索引（从外侧看从左到右），以及邻格上对应的两个角
	var edges := [[1, 0, 2, 3], [2, 1, 3, 0], [3, 2, 0, 1], [0, 3, 1, 2]]
	for z in data.size.y:
		for x in data.size.x:
			var cell := data.origin + Vector2i(x, z)
			var own := _corner_heights(cell)
			var points := _corner_points(cell)
			var lip := LIP_COLORS[clampi(data.get_biome(cell), 0, LIP_COLORS.size() - 1)]
			for d in 4:
				var neighbor := cell + DIRECTIONS[d]
				var other := _corner_heights(neighbor) if data.has_cell(neighbor) else PackedFloat32Array([skirt_level * data.layer_height, skirt_level * data.layer_height, skirt_level * data.layer_height, skirt_level * data.layer_height])
				var a: int = edges[d][0]
				var b: int = edges[d][1]
				var top_a := own[a]
				var top_b := own[b]
				var bottom_a := minf(other[edges[d][2]], top_a)
				var bottom_b := minf(other[edges[d][3]], top_b)
				if top_a - bottom_a < 0.001 and top_b - bottom_b < 0.001:
					continue
				_add_wall(st, points[a], points[b], top_a, top_b, bottom_a, bottom_b, DIRECTIONS[d], lip, collision_faces)
	return st.commit()

func _add_wall(st: SurfaceTool, from: Vector2, to: Vector2, top_from: float, top_to: float,
		bottom_from: float, bottom_to: float, direction: Vector2i, lip: Color, collision_faces: PackedVector3Array) -> void:
	var normal := Vector3(direction.x, 0, direction.y)
	# 水平纹理坐标沿墙面方向连续，竖直方向按世界高度，保证像素格对齐
	var u_from := (from.x if direction.y != 0 else from.y) / data.cell_size
	var u_to := (to.x if direction.y != 0 else to.y) / data.cell_size
	var corners := [
		[Vector3(from.x, top_from, from.y), u_from, top_from, bottom_from],
		[Vector3(to.x, top_to, to.y), u_to, top_to, bottom_to],
		[Vector3(to.x, bottom_to, to.y), u_to, top_to, bottom_to],
		[Vector3(from.x, bottom_from, from.y), u_from, top_from, bottom_from]]
	for index in [0, 1, 2, 0, 2, 3]:
		var corner: Array = corners[index]
		var position: Vector3 = corner[0]
		st.set_normal(normal)
		st.set_color(lip)
		st.set_uv(Vector2(corner[1], -position.y / data.cell_size))
		# UV2 = (墙顶高度, 墙底高度)，用于崖顶草沿与崖底接触阴影
		st.set_uv2(Vector2(corner[2], corner[3]))
		st.add_vertex(position)
		collision_faces.append(position)

# ---------- 水面与瀑布 ----------

func _water_height(cell: Vector2i) -> float:
	return (_level(cell) + TerrainData.WATER_SURFACE) * data.layer_height

func _build_water() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in data.size.y:
		for x in data.size.x:
			var cell := data.origin + Vector2i(x, z)
			if not _is(cell, TerrainData.OVERLAY_WATER):
				continue
			var y := _water_height(cell)
			var points := _corner_points(cell)
			var quad: Array[Vector3] = []
			for point in points:
				quad.append(Vector3(point.x, y, point.y))
			_add_quad(st, quad, null)
	st.generate_normals()
	return st.commit()

## 相邻两个水格高度不同时，在交界处生成一道瀑布
func _build_waterfalls() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edges := [[1, 0], [2, 1], [3, 2], [0, 3]]
	for z in data.size.y:
		for x in data.size.x:
			var cell := data.origin + Vector2i(x, z)
			if not _is(cell, TerrainData.OVERLAY_WATER):
				continue
			var points := _corner_points(cell)
			for d in 4:
				var neighbor := cell + DIRECTIONS[d]
				if not _is(neighbor, TerrainData.OVERLAY_WATER) or _level(neighbor) >= _level(cell):
					continue
				# 稍微向下游方向偏移，避免和崖壁重叠闪烁
				var offset := Vector3(DIRECTIONS[d].x, 0, DIRECTIONS[d].y) * 0.03
				var from: Vector2 = points[edges[d][0]]
				var to: Vector2 = points[edges[d][1]]
				var top := _water_height(cell)
				var bottom := _water_height(neighbor)
				var direction := Vector3(DIRECTIONS[d].x, 0, DIRECTIONS[d].y)
				var across := Vector2i(roundi((to.x - from.x) / data.cell_size), roundi((to.y - from.y) / data.cell_size))
				var left_edge := 0.0 if _same_waterfall(cell - across, d, cell, neighbor) else 1.0
				var right_edge := 0.0 if _same_waterfall(cell + across, d, cell, neighbor) else 1.0
				# 分段水帘供 shader 弯曲；同一条瀑布的格子接缝不做透明衰减。
				for row in 12:
					var start := float(row) / 12.0
					var end := float(row + 1) / 12.0
					var quad: Array[Vector3] = [
						Vector3(from.x, lerpf(top, bottom, start), from.y) + offset,
						Vector3(to.x, lerpf(top, bottom, start), to.y) + offset,
						Vector3(to.x, lerpf(top, bottom, end), to.y) + offset,
						Vector3(from.x, lerpf(top, bottom, end), from.y) + offset]
					_add_fall_quad(st, quad, [Vector2(0, start), Vector2(1, start), Vector2(1, end), Vector2(0, end)],
						direction, Vector2(top, bottom), Color(0, left_edge, right_edge, 1))
				# 底部白沫仅覆盖落水点附近；长度由 shader 调节。
				var foot: Array[Vector3] = [
					Vector3(from.x, bottom + 0.018, from.y) + offset,
					Vector3(to.x, bottom + 0.018, to.y) + offset,
					Vector3(to.x, bottom + 0.018, to.y) + offset + direction,
					Vector3(from.x, bottom + 0.018, from.y) + offset + direction]
				_add_fall_quad(st, foot, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)],
					direction, Vector2(top, bottom), Color(0.5, left_edge, right_edge, 1))
				# 固定种子的少量水滴，位移在 shader 中按抛物线计算。
				for drop in 18:
					var t := (float(drop) + 0.5) / 18.0
					var center := Vector3(lerpf(from.x, to.x, t), bottom + 0.03, lerpf(from.y, to.y, t)) + offset
					# UV 在 shader 中展开成面向相机的小水滴。
					var spray: Array[Vector3] = [center, center, center, center]
					_add_fall_quad(st, spray, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)],
						direction, Vector2(top, bottom), Color(1, t, float(posmod(cell.x * 17 + cell.y * 31, 97)) / 97.0, 1))
	return st.commit()

func _same_waterfall(side: Vector2i, d: int, upper: Vector2i, lower: Vector2i) -> bool:
	var down := side + DIRECTIONS[d]
	return _is(side, TerrainData.OVERLAY_WATER) and _is(down, TerrainData.OVERLAY_WATER) \
		and _level(side) == _level(upper) and _level(down) == _level(lower)

func _add_fall_quad(st: SurfaceTool, quad: Array[Vector3], uvs: Array, normal: Vector3, span: Vector2, zone: Color) -> void:
	for index in [0, 1, 2, 0, 2, 3]:
		st.set_normal(normal)
		st.set_uv(uvs[index])
		st.set_uv2(span)
		st.set_color(zone)
		st.add_vertex(quad[index])

# ---------- 桥 ----------

func _build_bridges(collision_faces: PackedVector3Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in data.size.y:
		for x in data.size.x:
			var cell := data.origin + Vector2i(x, z)
			if not _is(cell, TerrainData.OVERLAY_BRIDGE) or not _is(cell, TerrainData.OVERLAY_WATER):
				continue
			# 两端不是水（或也是桥）的方向即为桥的走向
			var along_z := _bridge_end(cell + Vector2i(0, -1)) and _bridge_end(cell + Vector2i(0, 1))
			var deck_top := (_level(cell) + 1) * data.layer_height + 0.03
			var center := Vector3(cell.x * data.cell_size, deck_top - BRIDGE_THICKNESS * 0.5, cell.y * data.cell_size)
			var length := data.cell_size
			var deck := Vector3(BRIDGE_WIDTH, BRIDGE_THICKNESS, length) if along_z else Vector3(length, BRIDGE_THICKNESS, BRIDGE_WIDTH)
			_add_box(st, center, deck, collision_faces)
			for side in [-1.0, 1.0]:
				var offset: float = (BRIDGE_WIDTH * 0.5 - 0.05) * side
				var rail_center := center + (Vector3(offset, 0, 0) if along_z else Vector3(0, 0, offset))
				rail_center.y = deck_top + RAIL_HEIGHT - 0.04
				var rail := Vector3(0.08, 0.08, length) if along_z else Vector3(length, 0.08, 0.08)
				_add_box(st, rail_center, rail, collision_faces)
				for post in [-0.4, 0.4]:
					var post_center := rail_center + (Vector3(0, 0, post * length) if along_z else Vector3(post * length, 0, 0))
					post_center.y = deck_top + RAIL_HEIGHT * 0.5
					_add_box(st, post_center, Vector3(0.1, RAIL_HEIGHT, 0.1), collision_faces)
	st.generate_normals()
	return st.commit()

func _bridge_end(cell: Vector2i) -> bool:
	return not _is(cell, TerrainData.OVERLAY_WATER) or _is(cell, TerrainData.OVERLAY_BRIDGE)

# ---------- 碰撞 ----------

func _build_collision(collision_faces: PackedVector3Array) -> void:
	var body := StaticBody3D.new()
	body.name = "Body"
	_generated.add_child(body)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(collision_faces)
	var node := CollisionShape3D.new()
	node.shape = shape
	body.add_child(node)
	# 水格（桥除外）放一个不可见的挡块，人物不会掉进河道
	for z in data.size.y:
		for x in data.size.x:
			var cell := data.origin + Vector2i(x, z)
			if not _is(cell, TerrainData.OVERLAY_WATER) or _is(cell, TerrainData.OVERLAY_BRIDGE):
				continue
			var bottom := _level(cell) * data.layer_height
			var height := data.layer_height * 4.0
			var blocker := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(data.cell_size, height, data.cell_size)
			blocker.shape = box
			blocker.position = Vector3(cell.x * data.cell_size, bottom + height * 0.5, cell.y * data.cell_size)
			body.add_child(blocker)

# ---------- 数据纹理 ----------

func _upload_map() -> void:
	# 直接写到 RenderingServer，避免数据纹理被序列化进场景文件
	var image := data.to_image()
	if _map_texture and _map_texture.get_size() == Vector2(image.get_size()):
		_map_texture.update(image)
	else:
		_map_texture = ImageTexture.create_from_image(image)
	if top_material:
		RenderingServer.material_set_param(top_material.get_rid(), "terrain_map", _map_texture.get_rid())
		RenderingServer.material_set_param(top_material.get_rid(), "map_origin", data.origin)
		RenderingServer.material_set_param(top_material.get_rid(), "cell_size", data.cell_size)
	if wall_material is ShaderMaterial:
		var wall := wall_material as ShaderMaterial
		RenderingServer.material_set_param(wall.get_rid(), "terrain_map", _map_texture.get_rid())
		wall.set_shader_parameter("map_origin", data.origin)
		wall.set_shader_parameter("cell_size", data.cell_size)
		_apply_grass_transition()
	if water_material is ShaderMaterial:
		var water := water_material as ShaderMaterial
		# Generated data stays in the rendering server, rather than being saved into .tscn.
		RenderingServer.material_set_param(water.get_rid(), "terrain_map", _map_texture.get_rid())
		water.set_shader_parameter("map_origin", data.origin)
		water.set_shader_parameter("cell_size", data.cell_size)

# ---------- 工具函数 ----------

func _add_mesh(mesh_name: String, mesh: ArrayMesh, material: Material, cast_shadows := true) -> void:
	if mesh.get_surface_count() == 0:
		return
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.material_override = material
	if mesh_name == "Water":
		instance.layers |= WATER_LIGHT_LAYER
	if not cast_shadows:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_generated.add_child(instance)

## 四个点按 西北、东北、东南、西南 顺序给出（从上方看顺时针）
func _add_quad(st: SurfaceTool, quad: Array[Vector3], collision_faces) -> void:
	for index in [0, 1, 2, 0, 2, 3]:
		st.set_uv(Vector2(quad[index].x, quad[index].z) / data.cell_size)
		st.add_vertex(quad[index])
		if collision_faces != null:
			collision_faces.append(quad[index])

func _add_box(st: SurfaceTool, center: Vector3, box_size: Vector3, collision_faces: PackedVector3Array) -> void:
	var h := box_size * 0.5
	var faces := [
		[Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)],
		[Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z)],
		[Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z)],
		[Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z)],
		[Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z)],
		[Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z)]]
	for face in faces:
		var quad: Array[Vector3] = []
		for point in face:
			quad.append(center + point)
		_add_quad(st, quad, collision_faces)

func get_world_rect() -> Rect2:
	var rect := data.get_world_rect() if data else Rect2()
	rect.position += Vector2(global_position.x, global_position.z)
	return rect

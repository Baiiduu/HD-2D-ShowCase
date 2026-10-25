class_name PlanarWaterReflection
extends Node3D

## Two water heights share the scene's lights, with one view per visible height.
## Layers 19/20 are reserved for mirrors; clipped static meshes are built once.
@export var terrain: Terrain
@export var source_camera: Camera3D
@export var world_environment: WorldEnvironment
@export var enabled := true
@export_range(0.25, 1.0, 0.05) var resolution_scale := 0.5
@export_range(0.0, 1.5, 0.05) var strength := 0.85
@export_range(0.0, 0.3, 0.01) var wave_strength := 0.08

const MIRROR_BITS := [1 << 18, 1 << 19]
const SPRITE_SHADER = preload("res://shaders/reflection_sprite.gdshader")
const CHARACTER_SHADER = preload("res://shaders/character_lighting.gdshader")
var views: Array[Dictionary] = []
var sprites: Array[Dictionary] = []
var water: ShaderMaterial
var active_view_count := 0
var _last_size := Vector2i.ZERO

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_priority = 100 # FollowCamera has already moved for this frame.
	water = terrain.water_material as ShaderMaterial
	if not water or not terrain.data or not source_camera:
		set_process(false)
		return
	source_camera.cull_mask &= ~(MIRROR_BITS[0] | MIRROR_BITS[1])
	var cells_by_height: Dictionary = {}
	var data := terrain.data
	for z in data.size.y:
		for x in data.size.x:
			var cell := data.origin + Vector2i(x, z)
			if not data.has_overlay(cell, TerrainData.OVERLAY_WATER):
				continue
			var height := (data.get_level(cell) + TerrainData.WATER_SURFACE) * data.layer_height + terrain.global_position.y
			if not cells_by_height.has(height):
				cells_by_height[height] = []
			var center := terrain.to_global(Vector3(cell.x * data.cell_size, height - terrain.global_position.y, cell.y * data.cell_size))
			cells_by_height[height].append(AABB(center - Vector3(data.cell_size * 0.5, 0.02, data.cell_size * 0.5), Vector3(data.cell_size, 0.04, data.cell_size)))
	var heights: Array = cells_by_height.keys()
	heights.sort()
	if heights.size() > 2:
		push_warning("Water reflection supports two height groups; additional heights use the water material without a mirror.")
	var sources := get_parent().find_children("*", "GeometryInstance3D", true, false)
	for index in mini(2, heights.size()):
		_make_view(index, float(heights[index]), cells_by_height[heights[index]])
		_prepare_geometry(sources, index, float(heights[index]))
	water.set_shader_parameter("reflection_heights", Vector2(float(heights[0]), float(heights[mini(1, heights.size() - 1)])) if not heights.is_empty() else Vector2.ZERO)
	if "--no-reflection" in OS.get_cmdline_user_args():
		enabled = false

func _make_view(index: int, height: float, cells: Array) -> void:
	var viewport := SubViewport.new()
	viewport.name = "WaterMirror%d" % index
	viewport.world_3d = source_camera.get_world_3d()
	viewport.use_hdr_2d = true # Keep emissive light > 1; tone mapping happens in the main view.
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	add_child(viewport)
	var camera := Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(camera)
	camera.current = true
	camera.cull_mask = MIRROR_BITS[index]
	camera.environment = world_environment.environment.duplicate()
	var env := camera.environment
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.adjustment_enabled = false
	env.glow_enabled = false
	env.ssr_enabled = false
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.volumetric_fog_enabled = false
	views.append({"viewport": viewport, "camera": camera, "height": height, "cells": cells})
	water.set_shader_parameter("reflection_texture_%d" % index, viewport.get_texture())

func _process(_delta: float) -> void:
	# Use physical render pixels, rather than the stretched UI's logical size.
	var viewport := get_viewport()
	var render_size := DisplayServer.window_get_size((viewport as Window).get_window_id()) if viewport is Window else Vector2i(viewport.get_texture().get_size())
	var size := Vector2i(Vector2(render_size) * resolution_scale)
	size = Vector2i(maxi(16, size.x), maxi(16, size.y))
	if size != _last_size:
		_last_size = size
		for view in views:
			(view.viewport as SubViewport).size = size
	water.set_shader_parameter("reflection_strength", strength)
	water.set_shader_parameter("wave_strength", wave_strength)
	var frustum := source_camera.get_frustum()
	active_view_count = 0
	for index in views.size():
		var view := views[index]
		var visible := enabled and source_camera.global_position.y > float(view.height) + 0.02 and _water_visible(view.cells, frustum)
		var mirror_viewport: SubViewport = view.viewport
		mirror_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
		water.set_shader_parameter("reflection_enabled_%d" % index, visible)
		if not visible:
			continue
		active_view_count += 1
		var camera: Camera3D = view.camera
		var position := source_camera.global_position
		var direction := -source_camera.global_basis.z
		position.y = 2.0 * float(view.height) - position.y
		direction.y = -direction.y
		camera.global_position = position
		camera.look_at(position + direction, Vector3.UP)
		camera.fov = source_camera.fov
		camera.keep_aspect = source_camera.keep_aspect
		camera.near = source_camera.near
		camera.far = source_camera.far
		_sync_environment(camera.environment)
		water.set_shader_parameter("reflection_matrix_%d" % index, camera.get_camera_projection() * Projection(camera.global_transform.affine_inverse()))
	for pair in sprites:
		var source: Sprite3D = pair.source
		var proxy: MeshInstance3D = pair.proxy
		proxy.global_transform = source.get_global_transform_interpolated()
		proxy.visible = source.is_visible_in_tree()
		var material: ShaderMaterial = proxy.material_override
		material.set_shader_parameter("sprite_texture", source.texture)
		material.set_shader_parameter("tint", source.modulate)
		material.set_shader_parameter("flip_h", source.flip_h)
		material.set_shader_parameter("flip_v", source.flip_v)
		if source.has_method("apply_lighting_to"):
			source.apply_lighting_to(material, true)

func _sync_environment(env: Environment) -> void:
	var original := world_environment.environment
	env.sky = original.sky
	env.ambient_light_color = original.ambient_light_color
	env.ambient_light_energy = original.ambient_light_energy
	env.fog_enabled = original.fog_enabled
	env.fog_light_color = original.fog_light_color
	env.fog_density = original.fog_density
	env.fog_depth_begin = original.fog_depth_begin
	env.fog_depth_end = original.fog_depth_end
	env.fog_height_density = original.fog_height_density

func _water_visible(cells: Array, frustum: Array[Plane]) -> bool:
	for box: AABB in cells:
		var outside := false
		for plane in frustum:
			var all_outside := true
			for corner in 8:
				if plane.distance_to(box.get_endpoint(corner)) <= 0.0:
					all_outside = false
					break
			if all_outside:
				outside = true
				break
		if not outside:
			return true
	return false

func _prepare_geometry(sources: Array[Node], index: int, height: float) -> void:
	var bit: int = MIRROR_BITS[index]
	for source in sources:
		if source.is_in_group("light_beams"):
			continue # Mirrors omit volumetric fog and its cone surface accents.
		if source is Sprite3D:
			_make_sprite(source, bit, height)
			continue
		if not source is MeshInstance3D:
			continue # Particles and fog volumes stay out of the lean mirror.
		var mesh := source as MeshInstance3D
		if mesh.name == "Water" or mesh.name == "Waterfalls" or not mesh.mesh:
			continue
		if mesh.name == "Halo":
			# Camera-facing halo vertices need shader clipping, not their local AABB.
			mesh.layers |= bit
			var material := mesh.mesh.surface_get_material(0) as ShaderMaterial
			if material:
				material.set_shader_parameter("reflection_height_%d" % index, height)
			continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		if box.end.y <= height + 0.005:
			continue
		if box.position.y >= height + 0.005:
			mesh.layers |= bit
			continue
		var clipped := _clip_mesh(mesh, height + 0.005)
		if clipped.get_surface_count() == 0:
			continue
		var proxy := MeshInstance3D.new()
		proxy.name = "Clipped_%s_%d" % [mesh.name, index]
		proxy.mesh = clipped
		proxy.layers = bit
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		proxy.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(proxy)
		proxy.global_transform = mesh.global_transform

func _make_sprite(source: Sprite3D, bit: int, height: float) -> void:
	if not source.texture:
		return
	var quad := QuadMesh.new()
	quad.size = source.texture.get_size() * source.pixel_size
	var material := ShaderMaterial.new()
	material.shader = CHARACTER_SHADER if source.has_method("apply_lighting_to") else SPRITE_SHADER
	material.set_shader_parameter("clip_height", height + 0.005)
	material.set_shader_parameter("fixed_y", source.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y)
	material.set_shader_parameter("sprite_texture", source.texture)
	material.set_shader_parameter("tint", source.modulate)
	if source.has_method("apply_lighting_to"):
		source.apply_lighting_to(material, true)
	var proxy := MeshInstance3D.new()
	proxy.mesh = quad
	proxy.material_override = material
	proxy.layers = bit
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	proxy.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(proxy)
	sprites.append({"source": source, "proxy": proxy})

## Sutherland-Hodgman against world Y, retaining normals, UV, UV2 and vertex color.
## The current demo's crossing meshes are static and have no skinning/normal maps.
func _clip_mesh(source: MeshInstance3D, height: float) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface in source.mesh.get_surface_count():
		if source.mesh is ArrayMesh and (source.mesh as ArrayMesh).surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := source.mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else positions.size()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var emitted := false
		for start in range(0, count, 3):
			var triangle: Array[Dictionary] = []
			for corner in 3:
				var vertex: int = indices[start + corner] if not indices.is_empty() else start + corner
				triangle.append({"p": positions[vertex], "n": _attribute(arrays, Mesh.ARRAY_NORMAL, vertex, Vector3.UP), "uv": _attribute(arrays, Mesh.ARRAY_TEX_UV, vertex, Vector2.ZERO), "uv2": _attribute(arrays, Mesh.ARRAY_TEX_UV2, vertex, Vector2.ZERO), "c": _attribute(arrays, Mesh.ARRAY_COLOR, vertex, Color.WHITE)})
			var polygon: Array[Dictionary] = []
			for corner in 3:
				var a := triangle[corner]
				var b := triangle[(corner + 1) % 3]
				var da: float = (source.global_transform * (a.p as Vector3)).y - height
				var db: float = (source.global_transform * (b.p as Vector3)).y - height
				if da >= 0.0:
					polygon.append(a)
				if (da >= 0.0) != (db >= 0.0):
					var t := da / (da - db)
					polygon.append({"p": (a.p as Vector3).lerp(b.p, t), "n": (a.n as Vector3).lerp(b.n, t).normalized(), "uv": (a.uv as Vector2).lerp(b.uv, t), "uv2": (a.uv2 as Vector2).lerp(b.uv2, t), "c": (a.c as Color).lerp(b.c, t)})
			for corner in range(1, polygon.size() - 1):
				for vertex: Dictionary in [polygon[0], polygon[corner], polygon[corner + 1]]:
					st.set_normal(vertex.n)
					st.set_uv(vertex.uv)
					st.set_uv2(vertex.uv2)
					st.set_color(vertex.c)
					st.add_vertex(vertex.p)
					emitted = true
		if emitted:
			var material := source.get_active_material(surface)
			st.set_material(material)
			st.commit(result)
	return result

func _attribute(arrays: Array, channel: int, vertex: int, fallback: Variant) -> Variant:
	return arrays[channel][vertex] if arrays[channel] != null and arrays[channel].size() > vertex else fallback

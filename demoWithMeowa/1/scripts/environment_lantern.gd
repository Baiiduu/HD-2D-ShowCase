@tool
extends Node3D

const BEAM_LAYER := 1 << 17

## 每盏灯独立调节；选择预设或点击恢复会重置本灯参数。
@export_group("环境预设")
@export_enum("桥边 · 湿润柔光", "高地 · 通透聚光") var environment_style := 0:
	set(v):
		environment_style = v
		if not _restoring_missing:
			restore_preset()
@export_tool_button("恢复当前环境预设") var reset_preset: Callable = restore_preset

@export_group("照明")
@export var light_color := Color(1.0, 0.72, 0.42):
	set(v): light_color = v; _queue_apply()
@export_range(0.0, 8.0, 0.1) var direct_energy := 3.8:
	set(v): direct_energy = v; _queue_apply()
## 灯头向四周的直接照明，让人物与桥栏侧面受光；和向下聚光共同投影。
@export_range(0.0, 3.0, 0.05) var fill_energy := 1.25:
	set(v): fill_energy = v; _queue_apply()
@export_range(1.0, 8.0, 0.1, "suffix:m") var light_range := 5.0:
	set(v): light_range = v; _queue_apply()
@export_range(20.0, 70.0, 1.0, "degrees") var cone_angle := 57.0:
	set(v): cone_angle = v; _queue_apply()
@export_range(0.1, 4.0, 0.05) var edge_softness := 1.1:
	set(v): edge_softness = v; _queue_apply()
@export_range(0.0, 30.0, 1.0, "degrees") var tilt := 14.0:
	set(v): tilt = v; _queue_apply()
## 光束朝向；桥边灯可向水面倾斜。恢复预设保留此方向。
@export_range(-180.0, 180.0, 1.0, "degrees") var azimuth := -90.0:
	set(v): azimuth = v; _queue_apply()
@export_range(0.0, 1.0, 0.05) var specular_strength := 0.9:
	set(v): specular_strength = v; _queue_apply()

@export_group("水面受光")
## 只照亮水面，保留原来的全向碎光覆盖；仍接收桥栏、人物等真实遮挡。
@export_range(0.0, 5.0, 0.05) var water_energy := 1.8:
	set(v): water_energy = v; _queue_apply()
@export_range(2.0, 8.0, 0.1, "suffix:m") var water_range := 5.5:
	set(v): water_range = v; _queue_apply()

@export_group("空气质感")
@export_range(0.0, 30.0, 0.5) var scattering := 16.0:
	set(v): scattering = v; _queue_apply()
@export_range(0.0, 0.3, 0.005) var mist_density := 0.13:
	set(v): mist_density = v; _queue_apply()
@export_range(0.0, 1.0, 0.05) var mist_texture := 0.7:
	set(v): mist_texture = v; _queue_apply()
@export_range(0.0, 1.0, 0.05) var ground_haze := 0.75:
	set(v): ground_haze = v; _queue_apply()
## 世界坐标 X/Z 的雾纹漂移速度，米/秒；(0, 0) 静止。
@export var mist_wind := Vector2(0.06, 0.02):
	set(v): mist_wind = v; _queue_apply()
## 接收真实灯光和阴影的柔边光束轮廓；0 关闭。需要体积雾开启。
@export_range(0.0, 0.2, 0.005) var beam_strength := 0.045:
	set(v): beam_strength = v; _queue_apply()

@export_group("灯芯与光晕")
@export_range(0.0, 5.0, 0.05) var emission_energy := 3.5:
	set(v): emission_energy = v; _queue_apply()
@export_range(0.0, 2.0, 0.05) var halo_energy := 1.2:
	set(v): halo_energy = v; _queue_apply()
@export_range(0.3, 2.0, 0.05, "suffix:m") var halo_diameter := 1.3:
	set(v): halo_diameter = v; _queue_apply()

@export_group("阴影")
@export var shadows_enabled := true:
	set(v): shadows_enabled = v; _queue_apply()
@export_range(0.0, 1.0, 0.05) var shadow_opacity := 1.0:
	set(v): shadow_opacity = v; _queue_apply()
@export_range(0.0, 0.2, 0.005, "suffix:m") var shadow_size := 0.025:
	set(v): shadow_size = v; _queue_apply()
## 小灯和细灯杆使用较小偏移；过高会让贴地阴影断开，过低可能出现自阴影条纹。
@export_range(0.0, 1.0, 0.01) var shadow_bias := 0.025:
	set(v): shadow_bias = v; _queue_apply()
@export_range(0.0, 2.0, 0.05) var shadow_normal_bias := 0.2:
	set(v): shadow_normal_bias = v; _queue_apply()

var _apply_queued := false
var _restoring_missing := false

func _ready() -> void:
	apply()

func restore_preset() -> void:
	var wet := environment_style == 0
	light_color = Color(1.0, 0.72, 0.42) if wet else Color(1.0, 0.86, 0.65)
	direct_energy = 3.8 if wet else 4.0
	fill_energy = 1.25 if wet else 0.9
	light_range = 5.0 if wet else 4.3
	water_energy = 1.8 if wet else 1.3
	water_range = 5.5
	cone_angle = 57.0 if wet else 46.0
	edge_softness = 1.1 if wet else 1.4
	tilt = 14.0 if wet else 8.0
	specular_strength = 0.9 if wet else 0.65
	scattering = 16.0 if wet else 7.0
	mist_density = 0.13 if wet else 0.045
	mist_texture = 0.7 if wet else 0.4
	ground_haze = 0.75 if wet else 0.0
	mist_wind = Vector2(0.06, 0.02) if wet else Vector2(0.02, 0.0)
	beam_strength = 0.045 if wet else 0.025
	emission_energy = 3.5 if wet else 3.2
	halo_energy = 1.2 if wet else 0.8
	halo_diameter = 1.3 if wet else 0.9
	shadows_enabled = true
	shadow_opacity = 1.0
	shadow_size = 0.025 if wet else 0.015
	shadow_bias = 0.025
	shadow_normal_bias = 0.2
	_queue_apply()

func _queue_apply() -> void:
	if _apply_queued or not is_inside_tree():
		return
	_apply_queued = true
	apply.call_deferred()

func apply() -> void:
	# 编辑器热重载可能给新增导出字段留下 Nil，只恢复缺失值。
	_restoring_missing = true
	var script: Script = get_script()
	for property in script.get_script_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_EDITOR:
			var default_value: Variant = script.get_property_default_value(property.name)
			if get(property.name) == null and default_value != null:
				set(property.name, default_value)
	if get("reset_preset") == null:
		reset_preset = restore_preset
	_restoring_missing = false
	_apply_queued = false
	if not is_inside_tree() or not has_node("Cone"):
		return
	var fill := $Light as OmniLight3D
	fill.light_color = light_color
	fill.light_energy = fill_energy
	fill.omni_range = light_range
	fill.light_specular = specular_strength
	fill.light_volumetric_fog_energy = scattering * 0.12
	fill.shadow_enabled = shadows_enabled
	fill.shadow_opacity = shadow_opacity
	fill.light_size = shadow_size
	fill.shadow_bias = shadow_bias
	fill.shadow_normal_bias = shadow_normal_bias
	# This light has no volumetric contribution and cannot wash out land or sprites.
	# 子场景重载前，编辑器里的旧实例可能还没有新增的水面灯。
	var water := get_node_or_null("WaterLight") as OmniLight3D
	if water:
		water.light_cull_mask = Terrain.WATER_LIGHT_LAYER
		water.light_color = light_color
		water.light_energy = water_energy
		water.omni_range = water_range
		water.light_specular = specular_strength
		water.light_volumetric_fog_energy = 0.0
		water.shadow_enabled = shadows_enabled
		water.shadow_opacity = shadow_opacity
		water.shadow_bias = shadow_bias
		water.shadow_normal_bias = shadow_normal_bias
		water.light_size = shadow_size
	var cone := $Cone as SpotLight3D
	cone.light_color = light_color
	cone.light_energy = direct_energy
	cone.spot_range = light_range
	cone.spot_angle = cone_angle
	cone.spot_angle_attenuation = edge_softness
	cone.rotation_degrees = Vector3(-90.0 + tilt, azimuth, 0.0)
	cone.light_specular = specular_strength
	cone.light_volumetric_fog_energy = scattering
	cone.shadow_enabled = shadows_enabled
	cone.shadow_opacity = shadow_opacity
	cone.light_size = shadow_size
	cone.shadow_bias = shadow_bias
	cone.shadow_normal_bias = shadow_normal_bias
	cone.light_cull_mask |= BEAM_LAYER
	var beam := $Beam as MeshInstance3D
	var beam_basis := Basis.from_euler(Vector3(deg_to_rad(tilt), deg_to_rad(azimuth), 0.0))
	beam.basis = beam_basis
	beam.position = cone.position + beam_basis * Vector3.DOWN * 0.56
	var beam_mesh := beam.mesh as CylinderMesh
	beam_mesh.bottom_radius = tan(deg_to_rad(cone_angle)) * 1.12
	(beam_mesh.material as ShaderMaterial).set_shader_parameter("gain", beam_strength)
	beam.set_instance_shader_parameter("lamp_position", cone.global_position)
	var world := get_viewport().find_world_3d()
	beam.visible = beam_strength > 0.0 and world.environment != null and world.environment.volumetric_fog_enabled
	var mist := $Mist as FogVolume
	mist.visible = mist_density > 0.0
	var fog := mist.material as ShaderMaterial
	fog.set_shader_parameter("density", mist_density)
	fog.set_shader_parameter("texture_strength", mist_texture)
	fog.set_shader_parameter("ground_haze", ground_haze)
	fog.set_shader_parameter("wind", mist_wind)
	var lamp := $Lamp as MeshInstance3D
	var emission := lamp.mesh.surface_get_material(0) as StandardMaterial3D
	emission.emission = light_color
	emission.emission_energy_multiplier = emission_energy
	var halo := $Halo as MeshInstance3D
	var mesh := halo.mesh as QuadMesh
	mesh.size = Vector2.ONE * halo_diameter
	(mesh.material as ShaderMaterial).set_shader_parameter("energy", halo_energy)
	halo.set_instance_shader_parameter("halo_color", light_color)

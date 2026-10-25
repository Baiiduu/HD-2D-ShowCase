@tool
class_name ArtDirection
extends Node

const BEAM_LAYER := 1 << 17 # Layer 18; water mirror layers 19/20 remain separate.

## 美术总控：把调画面最常用的参数集中在一个节点上。
## 在编辑器检查器里修改会实时生效；运行时也以这里的数值为准，
## 会覆盖环境、月光、天空、地面材质、光晕与后处理中的对应设置。

@export_group("引用")
@export var world_environment: WorldEnvironment:
	set(v): world_environment = v; _queue_apply()
@export var moon: DirectionalLight3D:
	set(v): moon = v; _queue_apply()
@export var terrain: Terrain:
	set(v): terrain = v; _queue_apply()
@export var post_process: CanvasItem:
	set(v): post_process = v; _queue_apply()
@export var water_reflection: PlanarWaterReflection:
	set(v): water_reflection = v; _queue_apply()

@export_group("水面")
@export var water_reflection_enabled := true:
	set(v): water_reflection_enabled = v; _queue_apply()
## 宽高比例：0.5 对应四分之一像素数量；可见的两个水位各用一张视图。
@export_range(0.25, 1.0, 0.05) var water_reflection_scale := 0.5:
	set(v): water_reflection_scale = v; _queue_apply()
@export_range(0.0, 1.5, 0.05) var water_reflection_strength := 0.85:
	set(v): water_reflection_strength = v; _queue_apply()
@export_range(0.0, 0.3, 0.01) var water_wave_strength := 0.08:
	set(v): water_wave_strength = v; _queue_apply()
## 宽而柔和的灯光高光，与细碎波纹高光共用真实灯光与阴影。
@export_range(0.0, 4.0, 0.05) var water_highlight_strength := 1.0:
	set(v): water_highlight_strength = v; _queue_apply()
@export_range(0.08, 0.5, 0.01) var water_highlight_roughness := 0.22:
	set(v): water_highlight_roughness = v; _queue_apply()
@export_range(0.0, 2.0, 0.05) var water_glint_strength := 0.8:
	set(v): water_glint_strength = v; _queue_apply()

@export_group("瀑布")
## 下落速度，米/秒；流束有轻微速度差。
@export_range(0.2, 4.0, 0.05) var waterfall_speed := 2.2:
	set(v): waterfall_speed = v; _queue_apply()
## 水帘向下游翻出的距离，0 恢复平面。
@export_range(0.0, 0.4, 0.01) var waterfall_curve := 0.18:
	set(v): waterfall_curve = v; _queue_apply()
@export_range(0.0, 1.0, 0.01) var waterfall_opacity := 0.72:
	set(v): waterfall_opacity = v; _queue_apply()
## 明亮流束的强度，控制水帘的疏密层次。
@export_range(0.0, 1.5, 0.05) var waterfall_stream_contrast := 0.9:
	set(v): waterfall_stream_contrast = v; _queue_apply()
@export_range(0.0, 1.5, 0.05) var waterfall_foam_strength := 0.85:
	set(v): waterfall_foam_strength = v; _queue_apply()
## 落水泡沫向下游延伸的距离（米）。
@export_range(0.05, 1.0, 0.01) var waterfall_foam_length := 0.65:
	set(v): waterfall_foam_length = v; _queue_apply()
## 水花高度与可见度，0 关闭。
@export_range(0.0, 1.5, 0.05) var waterfall_splash_strength := 0.65:
	set(v): waterfall_splash_strength = v; _queue_apply()
## 仅影响落水点的局部薄雾，避免遮住流束和河面。
@export_range(0.0, 0.8, 0.01) var waterfall_mist_density := 0.18:
	set(v): waterfall_mist_density = v; _queue_apply()

@export_group("泡沫与水花")
## 岸边、落水白沫和飞溅水滴共用的颜色，仍接受场景灯光。
@export var water_foam_color := Color(0.78, 0.85, 0.85):
	set(v): water_foam_color = v; _queue_apply()
## 泡沫像素和水滴的共同尺寸倍率。
@export_range(0.5, 2.0, 0.05) var water_foam_scale := 1.0:
	set(v): water_foam_scale = v; _queue_apply()
## 泡沫成簇的覆盖率，越低空隙越多。
@export_range(0.0, 1.0, 0.05) var water_foam_density := 0.55:
	set(v): water_foam_density = v; _queue_apply()
## 泡沫随水流移动的速度（米/秒），0 静止。
@export_range(0.0, 0.3, 0.01) var water_foam_motion := 0.08:
	set(v): water_foam_motion = v; _queue_apply()
## 岸边泡沫带宽度（米），实际边缘带有不规则空隙。
@export_range(0.02, 0.4, 0.01) var water_bank_foam_width := 0.14:
	set(v): water_bank_foam_width = v; _queue_apply()
## 水面泡沫强度，0 关闭；瀑布白沫强度在瀑布分组中独立调节。
@export_range(0.0, 1.0, 0.05) var water_foam_strength := 0.8:
	set(v): water_foam_strength = v; _queue_apply()
## 水滴基础宽度（米），每滴有少量固定大小变化。
@export_range(0.02, 0.12, 0.005) var water_splash_size := 0.055:
	set(v): water_splash_size = v; _queue_apply()
## 可见水滴比例，0 关闭；固定种子使调节时保持可比较。
@export_range(0.0, 1.0, 0.05) var water_splash_density := 0.6:
	set(v): water_splash_density = v; _queue_apply()

@export_group("整体")
## 曝光：整体明暗，最直接的提亮手段
@export_range(0.2, 3.0, 0.01) var exposure := 1.3:
	set(v): exposure = v; _queue_apply()
@export_range(0.5, 2.0, 0.01) var brightness := 1.05:
	set(v): brightness = v; _queue_apply()
@export_range(0.5, 2.0, 0.01) var contrast := 1.05:
	set(v): contrast = v; _queue_apply()
@export_range(0.0, 2.0, 0.01) var saturation := 1.1:
	set(v): saturation = v; _queue_apply()
## 泛光强度：灯、霓虹的光晕扩散
@export_range(0.0, 2.0, 0.01) var bloom := 0.8:
	set(v): bloom = v; _queue_apply()

@export_group("环境光与月光")
## 环境光：决定阴影里的颜色和亮度
@export var ambient_color := Color(0.5, 0.48, 0.52):
	set(v): ambient_color = v; _queue_apply()
@export_range(0.0, 3.0, 0.01) var ambient_energy := 0.7:
	set(v): ambient_energy = v; _queue_apply()
@export var moon_color := Color(0.9, 0.86, 0.8):
	set(v): moon_color = v; _queue_apply()
@export_range(0.0, 4.0, 0.01) var moon_energy := 0.85:
	set(v): moon_energy = v; _queue_apply()
## 主光绕 Y 轴旋转的角度，决定投影在地面上的方向。
@export_range(-180.0, 180.0, 1.0, "degrees") var moon_azimuth := -32.0:
	set(v): moon_azimuth = v; _queue_apply()
## 主光俯照角度；越低，人物和灯杆的投影越长。
@export_range(5.0, 85.0, 1.0, "degrees") var moon_elevation := 48.0:
	set(v): moon_elevation = v; _queue_apply()

@export_group("雾")
## 雾色：同时用于距离雾、天空地平线、地图边缘
@export var fog_color := Color(0.38, 0.35, 0.4):
	set(v): fog_color = v; _queue_apply()
## 距离雾：从多远开始起雾、到多远达到最浓（米）
@export_range(0.0, 100.0, 0.5) var fog_begin := 14.0:
	set(v): fog_begin = v; _queue_apply()
@export_range(1.0, 200.0, 0.5) var fog_end := 50.0:
	set(v): fog_end = v; _queue_apply()
## 最远处雾的浓度（0 = 无雾，1 = 完全看不见）
@export_range(0.0, 1.0, 0.01) var fog_amount := 0.7:
	set(v): fog_amount = v; _queue_apply()
## 低处（溪谷）额外的雾
@export_range(0.0, 2.0, 0.01) var low_fog := 0.3:
	set(v): low_fog = v; _queue_apply()
## 地图最外圈多少米逐渐融进雾色，0 = 关闭
@export_range(0.0, 20.0, 0.1) var map_edge_fog := 0.0:
	set(v): map_edge_fog = v; _queue_apply()
## 体积雾：让灯光在空气里有光晕，过大会让画面发白
@export var volumetric_fog := true:
	set(v): volumetric_fog = v; _queue_apply()
@export_range(0.0, 0.1, 0.001) var volumetric_density := 0.006:
	set(v): volumetric_density = v; _queue_apply()

@export_group("天空")
@export var sky_top_color := Color(0.05, 0.05, 0.11):
	set(v): sky_top_color = v; _queue_apply()
## 远景剪影（远山、松林）最近一层的颜色
@export var silhouette_color := Color(0.1, 0.09, 0.13):
	set(v): silhouette_color = v; _queue_apply()
## 北方地平线的暖色辉光
@export var horizon_glow_color := Color(0.75, 0.42, 0.24):
	set(v): horizon_glow_color = v; _queue_apply()
@export_range(0.0, 2.0, 0.01) var horizon_glow := 0.5:
	set(v): horizon_glow = v; _queue_apply()
@export_range(0.0, 0.05, 0.001) var stars := 0.01:
	set(v): stars = v; _queue_apply()

@export_group("萤火虫")
@export var fireflies_enabled := true:
	set(v): fireflies_enabled = v; _queue_apply()
@export var firefly_color := Color(0.75, 1.0, 0.45):
	set(v): firefly_color = v; _queue_apply()
## 完整光晕面片直径，米；亮核远小于此尺寸。
@export_range(0.01, 0.15, 0.005, "suffix:m") var firefly_size := 0.045:
	set(v): firefly_size = maxf(v, 0.01); _queue_apply()
## 每个光点的尺寸在 1±该值之间随机变化。
@export_range(0.0, 0.6, 0.01) var firefly_size_variation := 0.3:
	set(v): firefly_size_variation = clampf(v, 0.0, 0.6); _queue_apply()
@export_range(0.0, 8.0, 0.1) var firefly_energy := 2.6:
	set(v): firefly_energy = maxf(v, 0.0); _queue_apply()
## 小亮核外柔和光晕的程度；不增加整屏模糊。
@export_range(0.0, 1.0, 0.01) var firefly_softness := 0.7:
	set(v): firefly_softness = clampf(v, 0.0, 1.0); _queue_apply()
## 缓慢明暗变化的幅度；0 关闭额外闪烁。
@export_range(0.0, 1.0, 0.01) var firefly_pulse_strength := 0.55:
	set(v): firefly_pulse_strength = clampf(v, 0.0, 1.0); _queue_apply()
## 每秒明暗循环数；各粒子的相位和速度略有不同。
@export_range(0.0, 2.0, 0.05, "suffix:Hz") var firefly_pulse_speed := 0.35:
	set(v): firefly_pulse_speed = maxf(v, 0.0); _queue_apply()

@export_group("地面受光")
## 地面湿润程度：0 干燥，1 雨后（灯光倒影随之变强）
@export_range(0.0, 1.0, 0.01) var wetness := 0.4:
	set(v): wetness = v; _queue_apply()
## 用现有地面纹理的明暗形成轻微受光起伏；0 恢复平面法线。
@export_range(0.0, 0.02, 0.001) var stone_relief := 0.006:
	set(v): stone_relief = v; _queue_apply()
## 石板亮面与缝隙的反光差异；0 恢复统一粗糙度。
@export_range(0.0, 1.0, 0.05) var stone_gloss_variation := 0.55:
	set(v): stone_gloss_variation = v; _queue_apply()
@export var puddles := false:
	set(v): puddles = v; _queue_apply()
## 积水多少（仅在开启积水时有效）
@export_range(0.0, 1.0, 0.01) var puddle_amount := 0.4:
	set(v): puddle_amount = v; _queue_apply()

@export_group("路灯调节")
@export_subgroup("主照明与光斑")
## 城市路灯：真实聚光照明、局部锥形雾和阴影贴图共用同一个光源。
@export var cone_enabled := true:
	set(v): cone_enabled = v; _queue_apply()
## 地面和人物的直接照明强度；空气中的亮度由 Cone Scattering 单独控制。
@export_range(0.0, 8.0, 0.1) var cone_energy := 3.6:
	set(v): cone_energy = v; _queue_apply()
## 地面照明与空气散射分开调节，避免雾光吞掉石板纹理。
@export var street_light_color := Color(1.0, 0.84, 0.60):
	set(v): street_light_color = v; _queue_apply()
## 聚光半角；越大，地面光斑越宽。
@export_range(15.0, 60.0, 1.0, "degrees") var cone_angle := 40.0:
	set(v): cone_angle = v; _queue_apply()
## 光斑边缘的衰减；越大，中心越集中、外围越柔和。
@export_range(0.1, 4.0, 0.05) var cone_edge_softness := 0.9:
	set(v): cone_edge_softness = v; _queue_apply()
## 光束略朝镜头倾斜，让人物与灯杆产生可见的遮挡层次。
@export_range(-20.0, 20.0, 1.0, "degrees") var cone_tilt := -10.0:
	set(v): cone_tilt = v; _queue_apply()
## 灯光在湿石板等表面产生的镜面高光强度，0 关闭该灯的高光。
@export_range(0.0, 1.0, 0.05) var street_specular := 0.85:
	set(v): street_specular = v; _queue_apply()

@export_subgroup("补光")
## 全向补光避免人物背面全黑；过高会冲淡聚光产生的阴影。
@export_range(0.0, 4.0, 0.05) var street_fill_energy := 0.45:
	set(v): street_fill_energy = v; _queue_apply()
## 全向补光范围，单位米。
@export_range(2.5, 8.0, 0.1, "suffix:m") var street_fill_range := 4.4:
	set(v): street_fill_range = v; _queue_apply()

@export_subgroup("雾中光束")
## 空气中的散射亮度；需要开启“雾”组的 Volumetric Fog。
@export_range(0.0, 40.0, 0.1) var cone_scattering := 10.0:
	set(v): cone_scattering = v; _queue_apply()
## 灯下局部雾的厚度；会同时增加遮蔽感和散射，建议先调散射亮度。
@export_range(0.0, 0.3, 0.005) var cone_density := 0.085:
	set(v): cone_density = v; _queue_apply()
## 雾的疏密变化，避免形成一整块均匀亮片；0 恢复均匀雾。
@export_range(0.0, 1.0, 0.05) var cone_mist_texture := 0.65:
	set(v): cone_mist_texture = v; _queue_apply()
## 雾纹的空间频率；越大，疏密变化越细碎。
@export_range(0.25, 4.0, 0.05) var cone_mist_scale := 1.0:
	set(v): cone_mist_scale = v; _queue_apply()
## 雾纹缓慢横向流动的速度；0 静止。
@export_range(0.0, 0.2, 0.005) var cone_mist_speed := 0.035:
	set(v): cone_mist_speed = v; _queue_apply()
## 聚光灯照亮的柔边锥面补充轮廓；仍然接收真实阴影。
@export_range(0.0, 2.0, 0.005) var cone_shape_gain := 0.055:
	set(v): cone_shape_gain = v; _queue_apply()

@export_subgroup("灯芯与光晕")
## 灯头自发光强度；只改变灯芯，不改变窗户或地面照明。
@export_range(0.0, 5.0, 0.05) var street_emission := 1.6:
	set(v): street_emission = v; _queue_apply()
## 路灯的局部光晕亮度；整体泛光由“整体”组的 Bloom 控制。
@export_range(0.0, 3.0, 0.05) var street_halo_energy := 0.9:
	set(v): street_halo_energy = v; _queue_apply()
## 路灯光晕面片直径，单位米；越大扩散越宽。
@export_range(0.4, 3.0, 0.05, "suffix:m") var street_halo_diameter := 1.6:
	set(v): street_halo_diameter = v; _queue_apply()

@export_subgroup("阴影")
## 路灯阴影开关；人物、灯杆的遮挡会同时影响地面和雾中光束。
@export var street_shadows_enabled := true:
	set(v): street_shadows_enabled = v; _queue_apply()
## 路灯阴影浓度；0 无阴影，1 完整遮挡。
@export_range(0.0, 1.0, 0.05) var street_shadow_opacity := 1.0:
	set(v): street_shadow_opacity = v; _queue_apply()
## 灯具尺寸决定离物体越远越柔和的 PCSS 阴影；0 可关闭该额外开销。
@export_range(0.0, 0.3, 0.01) var cone_shadow_size := 0.12:
	set(v): cone_shadow_size = v; _queue_apply()

@export_group("路灯通用 · 金色颗粒")
## 城市与右侧环境灯共享这些参数；雾关闭时隐藏。
@export var street_dust_enabled := true:
	set(v): street_dust_enabled = v; _queue_apply()
@export_range(1, 100, 1) var lamp_dust_count := 28:
	set(v): lamp_dust_count = v; _queue_apply()
@export_range(0.005, 0.08, 0.001, "suffix:m") var lamp_dust_size := 0.028:
	set(v): lamp_dust_size = v; _queue_apply()
@export_range(0.0, 0.2, 0.005, "suffix:m/s") var lamp_dust_speed := 0.06:
	set(v): lamp_dust_speed = v; _queue_apply()
@export_range(0.0, 2.0, 0.05) var lamp_dust_energy := 0.65:
	set(v): lamp_dust_energy = v; _queue_apply()
@export var lamp_dust_color := Color(1.0, 0.84, 0.48):
	set(v): lamp_dust_color = v; _queue_apply()

@export_group("后处理")
## 灯头光晕亮度
@export_range(0.0, 2.0, 0.01) var halo_energy := 0.35:
	set(v): halo_energy = v; _queue_apply()
@export_range(0.0, 1.0, 0.01) var vignette := 0.3:
	set(v): vignette = v; _queue_apply()
## 分离色调：暗部偏冷、亮部偏暖的程度
@export_range(0.0, 1.0, 0.01) var split_toning := 0.25:
	set(v): split_toning = v; _queue_apply()

var _apply_queued := false

func _ready() -> void:
	if not Engine.is_editor_hint() and "--no-reflection" in OS.get_cmdline_user_args():
		water_reflection_enabled = false
	apply()

func _queue_apply() -> void:
	if _apply_queued or not is_inside_tree():
		return
	_apply_queued = true
	apply.call_deferred()

func apply() -> void:
	_restore_missing_export_defaults()
	_apply_queued = false
	if terrain and terrain.water_material is ShaderMaterial:
		var water := terrain.water_material as ShaderMaterial
		water.set_shader_parameter("wave_strength", water_wave_strength)
		water.set_shader_parameter("highlight_strength", water_highlight_strength)
		water.set_shader_parameter("highlight_roughness", water_highlight_roughness)
		water.set_shader_parameter("glint_strength", water_glint_strength)
		water.set_shader_parameter("foam_color", water_foam_color)
		water.set_shader_parameter("foam_scale", water_foam_scale)
		water.set_shader_parameter("foam_density", water_foam_density)
		water.set_shader_parameter("foam_motion", water_foam_motion)
		water.set_shader_parameter("bank_foam_width", water_bank_foam_width)
		water.set_shader_parameter("foam_strength", water_foam_strength)
	if terrain and terrain.waterfall_material is ShaderMaterial:
		var waterfall := terrain.waterfall_material as ShaderMaterial
		waterfall.set_shader_parameter("speed", waterfall_speed)
		waterfall.set_shader_parameter("lip_curve", waterfall_curve)
		waterfall.set_shader_parameter("opacity", waterfall_opacity)
		waterfall.set_shader_parameter("stream_contrast", waterfall_stream_contrast)
		waterfall.set_shader_parameter("foam_strength", waterfall_foam_strength)
		waterfall.set_shader_parameter("foam_length", waterfall_foam_length)
		waterfall.set_shader_parameter("splash_strength", waterfall_splash_strength)
		waterfall.set_shader_parameter("foam_color", water_foam_color)
		waterfall.set_shader_parameter("foam_scale", water_foam_scale)
		waterfall.set_shader_parameter("foam_density", water_foam_density)
		waterfall.set_shader_parameter("foam_motion", water_foam_motion)
		waterfall.set_shader_parameter("splash_size", water_splash_size)
		waterfall.set_shader_parameter("splash_density", water_splash_density)
		if terrain.water_material is ShaderMaterial:
			var current_flow: Vector2 = (terrain.water_material as ShaderMaterial).get_shader_parameter("flow")
			waterfall.set_shader_parameter("foam_flow", current_flow.normalized())
	var waterfall_mist := get_parent().get_node_or_null("World/WaterfallMist") as FogVolume
	if waterfall_mist and waterfall_mist.material is FogMaterial:
		(waterfall_mist.material as FogMaterial).density = waterfall_mist_density
	if water_reflection and not Engine.is_editor_hint():
		water_reflection.enabled = water_reflection_enabled
		water_reflection.resolution_scale = water_reflection_scale
		water_reflection.strength = water_reflection_strength
		water_reflection.wave_strength = water_wave_strength
	if world_environment and world_environment.environment:
		var env := world_environment.environment
		env.tonemap_exposure = exposure
		env.adjustment_enabled = true
		env.adjustment_brightness = brightness
		env.adjustment_contrast = contrast
		env.adjustment_saturation = saturation
		env.glow_intensity = bloom
		env.ambient_light_color = ambient_color
		env.ambient_light_energy = ambient_energy
		env.fog_light_color = fog_color
		env.fog_depth_begin = fog_begin
		env.fog_depth_end = maxf(fog_end, fog_begin + 1.0)
		env.fog_density = fog_amount
		env.fog_height_density = low_fog
		env.volumetric_fog_enabled = volumetric_fog
		env.volumetric_fog_density = volumetric_density
		var sky := env.sky.sky_material as ShaderMaterial if env.sky else null
		if sky:
			sky.set_shader_parameter("zenith_color", sky_top_color)
			sky.set_shader_parameter("horizon_color", fog_color)
			sky.set_shader_parameter("fog_color", fog_color)
			sky.set_shader_parameter("silhouette_color", silhouette_color)
			sky.set_shader_parameter("glow_color", horizon_glow_color)
			sky.set_shader_parameter("glow_strength", horizon_glow)
			sky.set_shader_parameter("star_density", stars)
	if moon:
		moon.light_color = moon_color
		moon.light_energy = moon_energy
		moon.rotation_degrees = Vector3(-moon_elevation, moon_azimuth, 0.0)
	if terrain and terrain.top_material:
		var ground := terrain.top_material
		ground.set_shader_parameter("wetness", wetness)
		ground.set_shader_parameter("stone_relief", stone_relief)
		ground.set_shader_parameter("stone_gloss_variation", stone_gloss_variation)
		ground.set_shader_parameter("puddles", puddles)
		ground.set_shader_parameter("puddle_threshold", 1.0 - puddle_amount)
		ground.set_shader_parameter("edge_fog_color", fog_color)
		ground.set_shader_parameter("edge_fade_distance", map_edge_fog)
	if post_process and post_process.material is ShaderMaterial:
		var post := post_process.material as ShaderMaterial
		post.set_shader_parameter("vignette_strength", vignette)
		post.set_shader_parameter("split_toning", split_toning)
	if is_inside_tree():
		_apply_street_lights()
		for lamp in get_tree().get_nodes_in_group("environment_lanterns"):
			lamp.apply()
		_apply_lamp_dust()
		_apply_fireflies()
		_apply_halos(get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene)

func _restore_missing_export_defaults() -> void:
	# 热重载旧实例时，新增导出参数可能为 Nil；只恢复缺失值，保留 false、0 和有效调节值。
	var script: Script = get_script()
	var restored := false
	for property in script.get_script_property_list():
		if not (property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_EDITOR):
			continue
		var default_value: Variant = script.get_property_default_value(property.name)
		if get(property.name) == null and default_value != null:
			set(property.name, default_value)
			restored = true
	if restored and Engine.is_editor_hint():
		notify_property_list_changed()

func _apply_street_lights() -> void:
	for light: Light3D in get_parent().find_children("*", "Light3D", true, false):
		light.light_cull_mask &= ~BEAM_LAYER
	for light: OmniLight3D in get_tree().get_nodes_in_group("street_lights"):
		light.light_energy = street_fill_energy
		light.light_color = street_light_color
		light.omni_range = street_fill_range
		light.light_specular = street_specular
		light.shadow_enabled = street_shadows_enabled
		light.shadow_opacity = street_shadow_opacity
		var cone := light.get_node("Cone") as SpotLight3D
		cone.light_energy = cone_energy if cone_enabled else 0.0
		cone.light_color = street_light_color
		cone.spot_angle = cone_angle
		cone.spot_angle_attenuation = cone_edge_softness
		cone.rotation_degrees.x = -90.0 + cone_tilt
		cone.light_specular = street_specular
		cone.light_volumetric_fog_energy = cone_scattering
		cone.light_size = cone_shadow_size
		cone.shadow_enabled = street_shadows_enabled
		cone.shadow_opacity = street_shadow_opacity
		cone.light_cull_mask |= BEAM_LAYER
		var beam := light.get_node("Beam") as MeshInstance3D
		var beam_basis := Basis(Vector3.RIGHT, deg_to_rad(cone_tilt))
		beam.basis = beam_basis
		beam.position = cone.position + beam_basis * Vector3.DOWN * 1.18
		beam.visible = cone_enabled and volumetric_fog and cone_shape_gain > 0.0
		beam.set_instance_shader_parameter("lamp_position", cone.global_position)
		(beam.mesh.surface_get_material(0) as ShaderMaterial).set_shader_parameter("gain", cone_shape_gain)
		var mist := light.get_node("Mist") as FogVolume
		mist.transform = beam.transform
		mist.visible = cone_enabled
		(mist.material as ShaderMaterial).set_shader_parameter("density", cone_density)
		(mist.material as ShaderMaterial).set_shader_parameter("texture_strength", cone_mist_texture)
		(mist.material as ShaderMaterial).set_shader_parameter("wisp_scale", cone_mist_scale)
		(mist.material as ShaderMaterial).set_shader_parameter("drift_speed", cone_mist_speed)
	for lamp: MeshInstance3D in get_tree().get_nodes_in_group("street_emitters"):
		var material := lamp.material_override as StandardMaterial3D
		material.emission = street_light_color
		material.emission_energy_multiplier = street_emission

func _apply_lamp_dust() -> void:
	for dust: GPUParticles3D in get_tree().get_nodes_in_group("street_light_dust"):
		dust.amount = lamp_dust_count
		dust.emitting = street_dust_enabled
		dust.visible = street_dust_enabled and volumetric_fog
		var process := dust.process_material as ParticleProcessMaterial
		process.initial_velocity_min = 0.03
		process.initial_velocity_max = 0.08
		dust.speed_scale = lamp_dust_speed / 0.06
		var gradient := (process.color_ramp as GradientTexture1D).gradient
		for index in gradient.get_point_count():
			var color := lamp_dust_color
			color.a = gradient.get_color(index).a
			gradient.set_color(index, color)
		var mesh := dust.draw_pass_1 as QuadMesh
		mesh.size = Vector2.ONE * lamp_dust_size
		(mesh.material as ShaderMaterial).set_shader_parameter("energy", lamp_dust_energy)

func _apply_fireflies() -> void:
	for particles: GPUParticles3D in get_tree().get_nodes_in_group("fireflies"):
		particles.visible = fireflies_enabled
		particles.emitting = fireflies_enabled
		var process := particles.process_material as ParticleProcessMaterial
		process.scale_min = 1.0 - firefly_size_variation
		process.scale_max = 1.0 + firefly_size_variation
		var mesh := particles.draw_pass_1 as QuadMesh
		mesh.size = Vector2.ONE * firefly_size
		var material := mesh.material as ShaderMaterial
		material.set_shader_parameter("glow_color", firefly_color)
		material.set_shader_parameter("energy", firefly_energy)
		material.set_shader_parameter("softness", firefly_softness)
		material.set_shader_parameter("pulse_strength", firefly_pulse_strength)
		material.set_shader_parameter("pulse_speed", firefly_pulse_speed)

## 场景里所有名为 Halo 的光晕面片（包括灯笼子场景里的）
func _apply_halos(root: Node) -> void:
	if not root:
		return
	for node in root.find_children("Halo", "MeshInstance3D", true, false):
		if node.is_in_group("environment_lantern_halos"):
			continue # 环境灯由各自的控制节点管理光晕。
		var mesh := (node as MeshInstance3D).mesh
		if mesh and mesh.surface_get_material(0) is ShaderMaterial:
			(mesh.surface_get_material(0) as ShaderMaterial).set_shader_parameter("energy", street_halo_energy if node.is_in_group("street_halos") else halo_energy)
			if node.is_in_group("street_halos"):
				(mesh as QuadMesh).size = Vector2.ONE * street_halo_diameter
				node.set_instance_shader_parameter("halo_color", street_light_color)

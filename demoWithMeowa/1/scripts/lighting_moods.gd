class_name LightingMoods
extends RefCounted

## 光照情绪预设：主光方向与颜色、环境光、雾、天空配色一起切换。
## 第 0 个是场景文件里的原始设置，其余预设都是逆光：主光在画面深处（北方）低角度照来。

const SKY_PARAMS: Array[String] = ["zenith_color", "horizon_color", "fog_color", "silhouette_color",
	"glow_color", "glow_strength", "moon_glow_color", "star_density"]
const ENV_PARAMS: Array[String] = ["ambient_light_color", "ambient_light_energy", "fog_light_color",
	"fog_height_density", "volumetric_fog_density", "volumetric_fog_albedo",
	"volumetric_fog_emission", "volumetric_fog_anisotropy", "adjustment_saturation", "adjustment_contrast"]
const LIGHT_PARAMS: Array[String] = ["light_color", "light_energy", "light_volumetric_fog_energy"]

const PRESETS := [
	{
		"name": "月夜逆光",
		# 光照来向：方位角（0 = 正北，负数偏西）与仰角，单位度
		"azimuth": 18.0, "elevation": 14.0,
		"light": {"light_color": Color(0.62, 0.74, 1.0), "light_energy": 1.4, "light_volumetric_fog_energy": 0.9},
		"env": {
			"ambient_light_color": Color(0.3, 0.38, 0.6), "ambient_light_energy": 0.35,
			"fog_light_color": Color(0.14, 0.2, 0.34), "fog_height_density": 0.5,
			"volumetric_fog_density": 0.012, "volumetric_fog_albedo": Color(0.7, 0.78, 0.95),
			"volumetric_fog_emission": Color(0.005, 0.008, 0.02), "volumetric_fog_anisotropy": 0.6,
			"adjustment_saturation": 1.05, "adjustment_contrast": 1.12,
		},
		"sky": {
			"zenith_color": Color(0.01, 0.02, 0.06), "horizon_color": Color(0.14, 0.2, 0.38),
			"fog_color": Color(0.18, 0.26, 0.44), "silhouette_color": Color(0.03, 0.05, 0.1),
			"glow_color": Color(0.35, 0.45, 0.8), "glow_strength": 0.6,
			"moon_glow_color": Color(0.75, 0.82, 1.0), "star_density": 0.012,
		},
	},
	{
		"name": "黄昏逆光",
		"azimuth": -32.0, "elevation": 9.0,
		"light": {"light_color": Color(1.0, 0.6, 0.32), "light_energy": 2.2, "light_volumetric_fog_energy": 0.8},
		"env": {
			"ambient_light_color": Color(0.36, 0.42, 0.66), "ambient_light_energy": 0.45,
			"fog_light_color": Color(0.42, 0.3, 0.32), "fog_height_density": 0.4,
			"volumetric_fog_density": 0.012, "volumetric_fog_albedo": Color(1.0, 0.86, 0.72),
			"volumetric_fog_emission": Color(0.01, 0.005, 0.005), "volumetric_fog_anisotropy": 0.6,
			"adjustment_saturation": 1.15, "adjustment_contrast": 1.1,
		},
		"sky": {
			"zenith_color": Color(0.1, 0.12, 0.3), "horizon_color": Color(0.8, 0.45, 0.32),
			"fog_color": Color(0.95, 0.6, 0.4), "silhouette_color": Color(0.16, 0.1, 0.18),
			"glow_color": Color(1.0, 0.42, 0.2), "glow_strength": 0.7,
			"moon_glow_color": Color(1.0, 0.72, 0.42), "star_density": 0.0,
		},
	},
]

var _environment: Environment
var _light: DirectionalLight3D
var _sky: ShaderMaterial
var _original := {}

func _init(environment: Environment, light: DirectionalLight3D) -> void:
	_environment = environment
	_light = light
	_sky = environment.sky.sky_material as ShaderMaterial if environment.sky else null
	# 记下场景里的原始设置，作为第 0 个预设
	_original = {"transform": light.global_transform, "light": {}, "env": {}, "sky": {}}
	for key in LIGHT_PARAMS:
		_original.light[key] = light.get(key)
	for key in ENV_PARAMS:
		_original.env[key] = environment.get(key)
	if _sky:
		for key in SKY_PARAMS:
			var value = _sky.get_shader_parameter(key)
			# 材质上没有覆盖的参数取 shader 里的默认值
			if value == null:
				value = RenderingServer.shader_get_parameter_default(_sky.shader.get_rid(), key)
			_original.sky[key] = value

func count() -> int:
	return PRESETS.size() + 1

func name_of(index: int) -> String:
	return "原始" if index == 0 else PRESETS[index - 1].name

func apply(index: int) -> void:
	var preset: Dictionary = _original if index == 0 else PRESETS[index - 1]
	if index == 0:
		_light.global_transform = _original.transform
	else:
		var azimuth := deg_to_rad(preset.azimuth)
		var elevation := deg_to_rad(preset.elevation)
		# 指向光源的方向；镜头朝北（-Z），方位角 0 即画面正前方
		var toward_light := Vector3(sin(azimuth) * cos(elevation), sin(elevation), -cos(azimuth) * cos(elevation))
		_light.look_at(_light.global_position - toward_light, Vector3.UP)
	for key in preset.light:
		_light.set(key, preset.light[key])
	for key in preset.env:
		_environment.set(key, preset.env[key])
	if _sky:
		for key in preset.sky:
			if preset.sky[key] != null:
				_sky.set_shader_parameter(key, preset.sky[key])

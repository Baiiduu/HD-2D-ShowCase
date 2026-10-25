@tool
extends Sprite3D

const SHADER := preload("res://shaders/character_lighting.gdshader")

@export_group("人物受光")
## 关闭恢复原生 Sprite3D 材质；仍使用现有场景照明与阴影。
@export var lighting_enabled := true:
	set(value): lighting_enabled = value; _queue_apply()
## 扩大侧光的柔和过渡，避免贴片转为背光时突然失去直接照明。
@export_range(0.0, 0.8, 0.05) var light_wrap := 0.3:
	set(value): light_wrap = value; _queue_apply()
## 用世界朝上的受光补充身体体积感，使人物与脚下地面的灯光颜色更一致。
@export_range(0.0, 1.0, 0.05) var top_light_response := 0.4:
	set(value): top_light_response = value; _queue_apply()
## 真实背光照到轮廓时的窄亮边；遮挡或移出光照范围时消失，0 关闭。
@export_range(0.0, 0.5, 0.01) var back_rim_strength := 0.12:
	set(value): back_rim_strength = value; _queue_apply()

var _material: ShaderMaterial
var _original_material: Material
var _apply_queued := false

func _ready() -> void:
	process_priority = 1 # Sync flips after Player has selected this frame's facing.
	apply_lighting()

func _process(_delta: float) -> void:
	# An already-open @tool scene may not receive _ready after a script reload.
	if not _material:
		apply_lighting()
	if lighting_enabled:
		_material.set_shader_parameter("flip_h", flip_h)
		_material.set_shader_parameter("flip_v", flip_v)
		_material.set_shader_parameter("tint", modulate)

func _queue_apply() -> void:
	if not is_inside_tree() or _apply_queued:
		return
	_apply_queued = true
	apply_lighting.call_deferred()

func _sync_texture() -> void:
	if _material:
		_material.set_shader_parameter("sprite_texture", texture)
	else:
		_queue_apply()

func apply_lighting() -> void:
	_apply_queued = false
	if not texture_changed.is_connected(_sync_texture):
		texture_changed.connect(_sync_texture)
	var defaults := {"lighting_enabled": true, "light_wrap": 0.3,
		"top_light_response": 0.4, "back_rim_strength": 0.12}
	for key in defaults:
		if get(key) == null:
			set(key, defaults[key])
	if not _material:
		_original_material = material_override
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	apply_lighting_to(_material)
	material_override = _material if lighting_enabled else _original_material
	notify_property_list_changed()

func apply_lighting_to(material: ShaderMaterial, reflection := false) -> void:
	material.set_shader_parameter("sprite_texture", texture)
	material.set_shader_parameter("tint", modulate)
	material.set_shader_parameter("fixed_y", billboard == BaseMaterial3D.BILLBOARD_FIXED_Y)
	material.set_shader_parameter("mirror_view", reflection)
	material.set_shader_parameter("flip_h", flip_h)
	material.set_shader_parameter("flip_v", flip_v)
	material.set_shader_parameter("lighting_enabled", lighting_enabled)
	material.set_shader_parameter("light_wrap", light_wrap)
	material.set_shader_parameter("top_light_response", top_light_response)
	material.set_shader_parameter("back_rim_strength", back_rim_strength)

func _validate_property(property: Dictionary) -> void:
	# Recreate the preview material on load instead of saving a generated override.
	if property.name == "material_override" and _material and material_override == _material:
		property.usage &= ~PROPERTY_USAGE_STORAGE

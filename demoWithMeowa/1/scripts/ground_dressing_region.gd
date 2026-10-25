@tool
class_name GroundDressingRegion
extends Node3D

## 移动或复制此节点，指定花草随机生成的矩形区域。
signal settings_changed

@export var enabled := true:
	set(value):
		enabled = value
		_refresh()
## X 为宽度，Y 为地图 Z 方向的长度，单位为米。
@export var area_size := Vector2(12.0, 9.6):
	set(value):
		area_size = Vector2(maxf(absf(value.x), 0.1), maxf(absf(value.y), 0.1))
		_refresh()
## 本区域生成的类别；具体变种在父节点选择。
@export_flags("草", "花", "碎石") var categories := 3:
	set(value):
		categories = value
		_refresh()
## 乘以父节点各类密度，0 可清空本区域。
@export_range(0.0, 5.0, 0.05) var density_multiplier := 1.0:
	set(value):
		density_multiplier = clampf(value, 0.0, 5.0)
		_refresh()

@export_group("本区域资源")
## 与父节点允许的资源取交集；默认全部可用。
@export_flags("01 低矮疏草", "02 展开密草", "03 细长草叶", "04 羽叶杂草", "05 阔叶草", "06 金黄枯草") var grass_variants := 63:
	set(value):
		grass_variants = value
		_refresh()
@export_flags("01 白色矮花", "02 粉色矮花", "03 淡紫矮花", "04 黄色细茎花", "05 蓝色双朵花", "06 红花与花苞") var flower_variants := 63:
	set(value):
		flower_variants = value
		_refresh()
@export_flags("01 暖灰扁石", "02 小圆灰石", "03 细扁灰石", "04 棱角灰石", "05 两颗碎石", "06 三颗碎石") var pebble_variants := 63:
	set(value):
		pebble_variants = value
		_refresh()

var _outline: MeshInstance3D

func _ready() -> void:
	set_notify_transform(true)
	_refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_inside_tree():
		settings_changed.emit()

func _refresh() -> void:
	if not is_inside_tree():
		return
	settings_changed.emit()
	if not Engine.is_editor_hint():
		return
	if _outline:
		_outline.free()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = Color(0.2, 0.8, 1.0) if enabled else Color(0.4, 0.4, 0.4)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var half := area_size * 0.5
	var corners := [Vector3(-half.x, 0.04, -half.y), Vector3(half.x, 0.04, -half.y), Vector3(half.x, 0.04, half.y), Vector3(-half.x, 0.04, half.y)]
	for index in 4:
		mesh.surface_add_vertex(corners[index])
		mesh.surface_add_vertex(corners[(index + 1) % 4])
	mesh.surface_end()
	_outline = MeshInstance3D.new()
	_outline.name = "AreaOutline"
	_outline.mesh = mesh
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_outline)

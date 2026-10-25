class_name FollowCamera
extends Camera3D

## 跟随目标（人物）
@export var target: Node3D
## 焦点相对目标原点的高度：对准人物贴图中心
@export var focus_height: float = 0.75
## 相机到焦点的距离（米）
@export var distance: float = 13.0
## 俯角（度），越大越接近俯瞰
@export_range(10.0, 80.0) var pitch_degrees: float = 35.0
## 跟随平滑度，越大跟得越紧
@export var smoothing: float = 6.0
## 死区半径（米）：人物在焦点附近这个范围内移动时相机不动
@export var dead_zone: float = 0.6
## 焦点距离地图东西两侧、南侧、北侧边缘的最小距离（米），避免画面露出太多地图外区域
@export var bounds_margin_side: float = 5.0
@export var bounds_margin_south: float = 4.0
@export var bounds_margin_north: float = 0.0

@export_group("水平旋转")
## 初始水平朝向（度）；0 为从南向北看，Q/E 在此基础上左右旋转。
@export_range(-180.0, 180.0, 1.0) var yaw_degrees: float = 0.0
## 是否允许按住 Q/E 向左/向右绕焦点旋转。
@export var horizontal_rotation_enabled: bool = true
## 相对初始朝向，左右各自允许旋转的最大角度（度）；0 禁止旋转。
@export_range(0.0, 180.0, 1.0) var max_yaw_degrees: float = 45.0
## 按住 Q/E 时的目标旋转速度（度/秒）。
@export_range(0.0, 180.0, 1.0) var yaw_speed_degrees: float = 60.0
## 运镜响应时间（秒）：越大起转、收尾越柔和；0 恢复直接旋转。
## 默认 0.22 秒，松手后短距离缓停，接近最大角度时逐渐收稳。
@export_range(0.0, 1.0, 0.01) var yaw_smoothing_seconds: float = 0.22
## 松开 Q/E 后，沿最后的旋转方向平滑停到下一个吸附点，避免反向拉回。
## 初始朝向始终是一个吸附点，朝它旋转时可停靠回正。
@export var yaw_snap_enabled: bool = true
## 相对初始朝向的吸附间隔（度）；15 表示 0、±15、±30 等，最大角度两端也可停靠。
## 0 禁用吸附；按住 Q/E 时仍可自由旋转。
@export_range(0.0, 180.0, 1.0) var yaw_snap_degrees: float = 15.0

@export_group("景深")
@export var dof_enabled: bool = true
## 深度景深按前后距离虚化；椭圆虚化在画面中保留人物周围的清晰区。
@export_enum("深度景深", "椭圆虚化") var dof_mode: int = 1
## 焦点前后保持清晰的距离（米）
@export var dof_far_margin: float = 2.5
@export var dof_far_transition: float = 5.0
@export var dof_near_margin: float = 2.5
@export var dof_near_transition: float = 2.0
@export_range(0.0, 1.0) var dof_amount: float = 0.1

@export_group("椭圆清晰区")
## 清晰区半径：X 相对画面宽度，Y 相对画面高度；0.3 表示该方向全长为画面的 60%。
@export var ellipse_radius := Vector2(0.34, 0.27)
## 椭圆边缘向外过渡的宽度，相对清晰区半径；越大越柔和。
@export_range(0.05, 2.0, 0.01) var ellipse_transition := 0.7
## 相对人物屏幕位置的中心偏移；X 向右、Y 向下，单位为画面宽高比例。
@export var ellipse_center_offset := Vector2.ZERO

## 焦点在地面 XZ 上的活动范围，由 set_world_rect() 根据地图大小计算
var bounds_min := Vector2(-INF, -INF)
var bounds_max := Vector2(INF, INF)
var anchor: Vector3
var focus: Vector3
var _yaw_offset_degrees: float = 0.0
var _yaw_target_degrees: float = 0.0
var _yaw_input_active: bool = false
var _yaw_last_turn: float = 0.0
var _post_material: ShaderMaterial

func _ready() -> void:
	# 在 _process 中按插值后的人物位置移动，相机自身不参与物理插值
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if attributes == null:
		attributes = CameraAttributesPractical.new()
	snap_to_target()

func set_world_rect(rect: Rect2) -> void:
	bounds_min = rect.position + Vector2(bounds_margin_side, bounds_margin_north)
	bounds_max = rect.end - Vector2(bounds_margin_side, bounds_margin_south)
	# 地图比可视范围还窄时，焦点固定在中线上
	if bounds_min.x > bounds_max.x:
		bounds_min.x = rect.get_center().x
		bounds_max.x = bounds_min.x
	if bounds_min.y > bounds_max.y:
		bounds_min.y = rect.get_center().y
		bounds_max.y = bounds_min.y

func snap_to_target() -> void:
	if not target:
		return
	anchor = _clamp_to_bounds(_target_point())
	focus = anchor
	_apply_transform()
	_update_dof()

func _process(delta: float) -> void:
	if not target:
		return
	_update_horizontal_rotation(delta)
	var point := _target_point()
	var offset := Vector2(point.x - anchor.x, point.z - anchor.z)
	if offset.length() > dead_zone:
		var push := offset.normalized() * (offset.length() - dead_zone)
		anchor.x += push.x
		anchor.z += push.y
	anchor.y = point.y
	anchor = _clamp_to_bounds(anchor)
	focus = focus.lerp(anchor, 1.0 - exp(-smoothing * delta))
	_apply_transform()
	_update_dof()

func _update_horizontal_rotation(delta: float) -> void:
	_yaw_offset_degrees = clampf(_yaw_offset_degrees, -max_yaw_degrees, max_yaw_degrees)
	if not horizontal_rotation_enabled:
		# 关闭旋转时立即停住，并清除尚未完成的运镜。
		_yaw_target_degrees = _yaw_offset_degrees
		_yaw_input_active = false
		_yaw_last_turn = 0.0
		return
	var left := Input.is_physical_key_pressed(KEY_Q)
	var right := Input.is_physical_key_pressed(KEY_E)
	var input_active := left or right
	var turn := float(right) - float(left)
	if yaw_snap_enabled and yaw_snap_degrees > 0.0:
		if input_active and (not _yaw_input_active or (turn != 0.0 and turn != _yaw_last_turn)):
			# 再次按键或反向输入，从实际角度接管尚未完成的运镜。
			_yaw_target_degrees = _yaw_offset_degrees
		elif not input_active and _yaw_input_active:
			_yaw_target_degrees = _snapped_yaw(_yaw_offset_degrees, _yaw_last_turn)
	_yaw_input_active = input_active
	if turn != 0.0:
		_yaw_last_turn = turn
	_yaw_target_degrees = clampf(_yaw_target_degrees + turn * yaw_speed_degrees * delta, -max_yaw_degrees, max_yaw_degrees)
	if yaw_smoothing_seconds <= 0.0:
		_yaw_offset_degrees = _yaw_target_degrees
	else:
		_yaw_offset_degrees = lerpf(_yaw_offset_degrees, _yaw_target_degrees, 1.0 - exp(-delta / yaw_smoothing_seconds))
		if absf(_yaw_offset_degrees - _yaw_target_degrees) < 0.001:
			_yaw_offset_degrees = _yaw_target_degrees

func _snapped_yaw(angle: float, direction: float) -> float:
	if direction == 0.0:
		return angle
	var step := angle / yaw_snap_degrees
	var snapped := (ceilf(step) if direction > 0.0 else floorf(step)) * yaw_snap_degrees
	return clampf(snapped, -max_yaw_degrees, max_yaw_degrees)

func _target_point() -> Vector3:
	return target.get_global_transform_interpolated().origin + Vector3.UP * focus_height

func _clamp_to_bounds(point: Vector3) -> Vector3:
	point.x = clampf(point.x, bounds_min.x, bounds_max.x)
	point.z = clampf(point.z, bounds_min.y, bounds_max.y)
	return point

func _apply_transform() -> void:
	# 绕焦点水平旋转，保持距离和俯角。
	var pitch := deg_to_rad(pitch_degrees)
	var yaw := deg_to_rad(yaw_degrees + _yaw_offset_degrees)
	global_position = focus + Vector3(0.0, sin(pitch), cos(pitch)).rotated(Vector3.UP, yaw) * distance
	look_at(focus, Vector3.UP)

## 只恢复 Q/E 旋转偏移，保留初始朝向、俯角、距离与景深设置。
func reset_horizontal_rotation() -> void:
	_yaw_offset_degrees = 0.0
	_yaw_target_degrees = 0.0
	_yaw_input_active = false
	_yaw_last_turn = 0.0
	if target:
		_apply_transform()
		_update_dof()

func _update_dof() -> void:
	var practical := attributes as CameraAttributesPractical
	if not practical:
		return
	var focus_distance := global_position.distance_to(_target_point())
	practical.dof_blur_far_enabled = dof_enabled and dof_mode == 0
	practical.dof_blur_near_enabled = dof_enabled and dof_mode == 0
	practical.dof_blur_far_distance = focus_distance + dof_far_margin
	practical.dof_blur_far_transition = dof_far_transition
	practical.dof_blur_near_distance = maxf(focus_distance - dof_near_margin, 0.1)
	practical.dof_blur_near_transition = dof_near_transition
	practical.dof_blur_amount = dof_amount
	if not _post_material:
		var screen := get_parent().get_node_or_null("PostProcess/Screen") as CanvasItem
		if screen and screen.material is ShaderMaterial:
			_post_material = screen.material.duplicate() as ShaderMaterial
			screen.material = _post_material
	if _post_material:
		var viewport_size := get_viewport().get_visible_rect().size
		var center := unproject_position(_target_point()) / viewport_size + ellipse_center_offset
		_post_material.set_shader_parameter("ellipse_enabled", dof_enabled and dof_mode == 1)
		_post_material.set_shader_parameter("ellipse_center", center)
		_post_material.set_shader_parameter("ellipse_radius", Vector2(maxf(ellipse_radius.x, 0.01), maxf(ellipse_radius.y, 0.01)))
		_post_material.set_shader_parameter("ellipse_transition", ellipse_transition)
		_post_material.set_shader_parameter("ellipse_blur_amount", dof_amount)

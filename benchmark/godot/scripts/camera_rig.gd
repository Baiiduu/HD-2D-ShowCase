extends Node3D
## South-of-target perspective follow camera with a small dead zone.

const DEADZONE := 0.3
const FOLLOW := 5.0
const BOUNDS_MIN := Vector2(-8.6, -6.5)
const BOUNDS_MAX := Vector2(32.6, 4.4)
const TARGET_LIFT := 0.75

var target: Node3D
var cam: Camera3D
var pitch := 10.0
var distance := 11.0
var focus := Vector3.ZERO


func setup(t: Node3D, fov: float, pitch_deg: float, dist: float) -> void:
	target = t
	pitch = pitch_deg
	distance = dist
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = fov
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 0.15
	cam.far = 700.0
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = distance + 7.0
	attrs.dof_blur_far_transition = 12.0
	attrs.dof_blur_near_enabled = true
	attrs.dof_blur_near_distance = 6.0
	attrs.dof_blur_near_transition = 3.0
	attrs.dof_blur_amount = 0.07
	cam.attributes = attrs
	add_child(cam)


func _desired() -> Vector3:
	return target.global_position + Vector3(0, TARGET_LIFT, 0)


func _clamp_focus(f: Vector3) -> Vector3:
	return Vector3(clampf(f.x, BOUNDS_MIN.x, BOUNDS_MAX.x), f.y, clampf(f.z, BOUNDS_MIN.y, BOUNDS_MAX.y))


func snap() -> void:
	focus = _clamp_focus(_desired())
	_apply()


func _process(delta: float) -> void:
	if target == null:
		return
	var want := _desired()
	var off := Vector2(want.x - focus.x, want.z - focus.z)
	var goal := focus
	if off.length() > DEADZONE:
		var excess := off - off.normalized() * DEADZONE
		goal.x += excess.x
		goal.z += excess.y
	goal.y = want.y
	goal = _clamp_focus(goal)
	var k := 1.0 - exp(-FOLLOW * delta)
	focus = focus.lerp(goal, k)
	_apply()


func _apply() -> void:
	var p := deg_to_rad(pitch)
	var pos := focus + Vector3(0, sin(p) * distance, cos(p) * distance)
	cam.global_transform = Transform3D(Basis.looking_at(focus - pos, Vector3.UP), pos)

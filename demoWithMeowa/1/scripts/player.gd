class_name Player
extends CharacterBody3D

const ANIMATION_REFERENCE_SPEED := 4.0
@export var speed: float = 4.0
@export var animations: SpriteFrames
## 移动参照相机：W/S 沿相机前后方向，A/D 沿相机左右方向，均投影到地面。
@export var movement_camera: Camera3D
## 可活动范围（XZ），由场景根据地形大小设置
var bounds := Rect2(-INF, -INF, INF, INF)
@onready var sprite: Sprite3D = $Sprite
var _animation: StringName = &"idle"
var _animation_frame := 0
var _animation_elapsed := 0.0
var _movement_speed := 0.0
var _facing: StringName = &"side"
var _side_flip_h := false

func _ready() -> void:
	if animations:
		sprite.texture = animations.get_frame_texture(_animation, 0)

func _process(delta: float) -> void:
	if not animations:
		return
	var playback_speed := _movement_speed / ANIMATION_REFERENCE_SPEED if _animation.begins_with("run") else 1.0
	_animation_elapsed += delta * playback_speed
	var frame_duration := animations.get_frame_duration(_animation, _animation_frame) / animations.get_animation_speed(_animation)
	while _animation_elapsed >= frame_duration:
		_animation_elapsed -= frame_duration
		_animation_frame = (_animation_frame + 1) % animations.get_frame_count(_animation)
		frame_duration = animations.get_frame_duration(_animation, _animation_frame) / animations.get_animation_speed(_animation)
	sprite.texture = animations.get_frame_texture(_animation, _animation_frame)

func _physics_process(delta: float) -> void:
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	).normalized()
	var movement := Vector3(direction.x, 0.0, direction.y)
	if movement_camera:
		var right := movement_camera.global_basis.x
		var backward := movement_camera.global_basis.z
		right.y = 0.0
		backward.y = 0.0
		movement = (right.normalized() * direction.x + backward.normalized() * direction.y).normalized()
	velocity.x = movement.x * speed
	velocity.z = movement.z * speed
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = 0.0
	# 斜向移动以横向为主；松开按键后保留最后朝向。
	if direction != Vector2.ZERO:
		if absf(direction.x) >= absf(direction.y):
			_facing = &"side"
			_side_flip_h = direction.x < 0.0
			sprite.flip_h = _side_flip_h
		elif direction.y < 0.0:
			_facing = &"back"
			sprite.flip_h = false
		else:
			_facing = &"side"
			sprite.flip_h = _side_flip_h
	var previous_position := position
	move_and_slide()
	position.x = clampf(position.x, bounds.position.x, bounds.end.x)
	position.z = clampf(position.z, bounds.position.y, bounds.end.y)
	_movement_speed = Vector2(position.x - previous_position.x, position.z - previous_position.z).length() / delta
	var next_animation: StringName = &"run" if _movement_speed > 0.05 else &"idle"
	if _facing != &"side":
		next_animation = StringName(str(next_animation) + "_" + str(_facing))
	if next_animation != _animation:
		_animation = next_animation
		_animation_frame = 0
		_animation_elapsed = 0.0

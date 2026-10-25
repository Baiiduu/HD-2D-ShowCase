@tool
extends Node3D

## 天气总控。花草、雨丝与地表反馈可在编辑器预览，镜头水滴在游戏画面中生效。
const RAIN_SHADER := preload("res://shaders/rain_streak.gdshader")
const MAX_DROPS := 12

@export_group("天气")
@export var enabled := true:
	set(v): enabled = v; _queue_apply()
@export_enum("晴天", "细雨") var weather_mode := 1:
	set(v): weather_mode = v; _queue_apply()
## 不运行也预览雨丝、花草风摆和水面/地表反馈；不影响游戏中的天气开关。
@export var editor_preview := true:
	set(v): editor_preview = v; _queue_apply()
@export var weather_seed := 10102026:
	set(v): weather_seed = v; _queue_apply()

@export_group("细雨")
## 雨丝数量占 Rain Amount 的比例；0 停雨。
@export_range(0.0, 1.0, 0.01) var rain_intensity := 0.55:
	set(v): rain_intensity = clampf(v, 0.0, 1.0); _queue_apply()
@export_range(100, 8000, 100) var rain_amount := 1600:
	set(v): rain_amount = maxi(v, 100); _queue_apply()
## 雨滴下落速度，米/秒。
@export_range(2.0, 20.0, 0.1) var rain_speed := 8.0:
	set(v): rain_speed = maxf(v, 2.0); _queue_apply()
## 每根雨丝宽度与长度，单位为米。
@export var rain_streak_size := Vector2(0.008, 0.26):
	set(v): rain_streak_size = Vector2(maxf(v.x, 0.001), maxf(v.y, 0.01)); _queue_apply()
@export var rain_color := Color(0.65, 0.76, 0.84, 0.24):
	set(v): rain_color = v; _queue_apply()
## 围绕镜头关注区域的雨幕宽度和深度，单位为米。
@export var rain_area := Vector2(24.0, 20.0):
	set(v): rain_area = Vector2(maxf(v.x, 4.0), maxf(v.y, 4.0)); _queue_apply()
@export_range(3.0, 20.0, 0.1) var rain_height := 9.0:
	set(v): rain_height = maxf(v, 3.0); _queue_apply()

@export_group("雨声音效")
@export var rain_audio_enabled := true:
	set(v): rain_audio_enabled = v; _queue_apply()
## 循环环境音；仅在运行游戏时播放，音量随雨量变化。
@export var rain_sound: AudioStream = preload("res://assets/meowa/weather/rain.wav"):
	set(v): rain_sound = v; _queue_apply()
## 满雨量时的音量，分贝；0 是素材原始音量，负数更轻。
@export_range(-40.0, 6.0, 0.5) var rain_volume_db := -8.0:
	set(v): rain_volume_db = v; _queue_apply()
## 雨声渐入、停雨淡出的时间，秒。
@export_range(0.1, 5.0, 0.1) var rain_audio_fade_time := 1.5:
	set(v): rain_audio_fade_time = maxf(v, 0.1); _queue_apply()
## 默认 Master；可填写项目中已有音频总线名称。
@export var rain_audio_bus: StringName = &"Master":
	set(v): rain_audio_bus = v; _queue_apply()

@export_group("轻微风声")
@export var wind_audio_enabled := true:
	set(v): wind_audio_enabled = v; _queue_apply()
## 风声循环素材；音量随现有花草风力变化，编辑器不播放。
@export var wind_sound: AudioStream = preload("res://assets/meowa/audio/wind.wav"):
	set(v): wind_sound = v; _queue_apply()
## 风力达到 3 时的播放增益；一般风力会更轻。
@export_range(-40.0, 6.0, 0.5) var wind_volume_db := -16.0:
	set(v): wind_volume_db = v; _queue_apply()
@export_range(0.1, 10.0, 0.1) var wind_audio_fade_time := 3.0:
	set(v): wind_audio_fade_time = maxf(v, 0.1); _queue_apply()
@export var wind_audio_bus: StringName = &"Master":
	set(v): wind_audio_bus = v; _queue_apply()

@export_group("水面雨纹")
@export var water_rain_enabled := true:
	set(v): water_rain_enabled = v; _queue_apply()
## 满雨量时每平方米每秒的涟漪数（近似）；位置和出现时间分别随机。
@export_range(0.0, 10.0, 0.1) var water_ripple_density := 1.8:
	set(v): water_ripple_density = maxf(v, 0.0); _queue_apply()
## 扩散到最大时的半径，米。
@export_range(0.05, 0.6, 0.01) var water_ripple_size := 0.28:
	set(v): water_ripple_size = maxf(v, 0.05); _queue_apply()
@export_range(0.0, 1.0, 0.01) var water_ripple_strength := 0.35:
	set(v): water_ripple_strength = clampf(v, 0.0, 1.0); _queue_apply()
@export_range(0.2, 2.0, 0.05) var water_ripple_lifetime := 0.8:
	set(v): water_ripple_lifetime = maxf(v, 0.2); _queue_apply()

@export_group("地表雨水")
@export var ground_rain_enabled := true:
	set(v): ground_rain_enabled = v; _queue_apply()
## 满雨量时每平方米每秒的地面溅点数（近似）；草地反馈更轻。
@export_range(0.0, 10.0, 0.1) var ground_splash_density := 0.9:
	set(v): ground_splash_density = maxf(v, 0.0); _queue_apply()
@export_range(0.03, 0.3, 0.01) var ground_splash_size := 0.11:
	set(v): ground_splash_size = maxf(v, 0.03); _queue_apply()
@export_range(0.0, 1.0, 0.01) var ground_splash_strength := 0.32:
	set(v): ground_splash_strength = clampf(v, 0.0, 1.0); _queue_apply()
## 天气额外增加的湿润程度；叠加在 ArtDirection 原有湿润设置上。
@export_range(0.0, 0.5, 0.01) var rain_wetness := 0.12:
	set(v): rain_wetness = clampf(v, 0.0, 0.5); _queue_apply()
## 地面打湿/停雨后恢复的时间，秒。
@export_range(0.1, 30.0, 0.5) var wetting_time := 8.0:
	set(v): wetting_time = maxf(v, 0.1); _queue_apply()
@export_range(0.1, 120.0, 1.0) var drying_time := 25.0:
	set(v): drying_time = maxf(v, 0.1); _queue_apply()

@export_group("花草风摆")
@export var wind_enabled := true:
	set(v): wind_enabled = v; _queue_apply()
## 地图 X/Z 平面的风向；会同时影响花草和雨丝倾斜。
@export var wind_direction := Vector2(1.0, 0.25):
	set(v): wind_direction = v; _queue_apply()
@export_range(0.0, 3.0, 0.01) var wind_strength := 0.65:
	set(v): wind_strength = maxf(v, 0.0); _queue_apply()
@export_range(0.1, 5.0, 0.05) var wind_speed := 1.6:
	set(v): wind_speed = maxf(v, 0.1); _queue_apply()
@export_range(0.0, 1.0, 0.01) var gust_strength := 0.3:
	set(v): gust_strength = clampf(v, 0.0, 1.0); _queue_apply()
## 下雨时额外增加的风力，乘以雨量。
@export_range(0.0, 2.0, 0.01) var rain_wind_boost := 0.25:
	set(v): rain_wind_boost = maxf(v, 0.0); _queue_apply()
## 草叶与花茎顶部的摆幅，米；根部固定。
@export_range(0.0, 0.2, 0.001) var grass_sway := 0.055:
	set(v): grass_sway = maxf(v, 0.0); _queue_apply()
@export_range(0.0, 0.2, 0.001) var flower_sway := 0.035:
	set(v): flower_sway = maxf(v, 0.0); _queue_apply()

@export_group("镜头水滴")
@export var lens_drops_enabled := true:
	set(v): lens_drops_enabled = v; _queue_apply()
## 满雨量时每秒产生的镜头水滴数；实际频率乘以 Rain Intensity。
@export_range(0.0, 5.0, 0.05) var lens_drop_rate := 0.8:
	set(v): lens_drop_rate = maxf(v, 0.0); _queue_apply()
## 同时存在的水滴上限。
@export_range(1, 12, 1) var lens_drop_limit := 8:
	set(v): lens_drop_limit = clampi(v, 1, MAX_DROPS); _queue_apply()
## 水滴半径的最小/最大值，以 900 像素高的画面为基准。
@export var lens_drop_size := Vector2(18.0, 34.0):
	set(v): lens_drop_size = Vector2(maxf(v.x, 2.0), maxf(v.y, 2.0)); _queue_apply()
## 水滴存续时间，秒；实际有少量随机变化。
@export_range(0.5, 10.0, 0.1) var lens_drop_lifetime := 3.8:
	set(v): lens_drop_lifetime = maxf(v, 0.5); _queue_apply()
## 消失前淡出的时间，秒。
@export_range(0.1, 4.0, 0.1) var lens_fade_time := 1.0:
	set(v): lens_fade_time = maxf(v, 0.1); _queue_apply()
@export_range(0.0, 30.0, 0.5) var lens_slide_speed := 6.0:
	set(v): lens_slide_speed = maxf(v, 0.0); _queue_apply()
## 仅水滴覆盖的小片区域虚化，单位为像素；0 保留折射但不模糊。
@export_range(0.0, 5.0, 0.1) var lens_blur := 1.0:
	set(v): lens_blur = maxf(v, 0.0); _queue_apply()
## 水滴厚度梯度造成的最大画面偏移，以 900 像素高画面下的像素为基准。
@export_range(0.0, 24.0, 0.5) var lens_refraction := 9.0:
	set(v): lens_refraction = maxf(v, 0.0); _queue_apply()
## 轮廓、偏轴与内部厚度的不规则程度；0 更圆润，1 变化最明显。
@export_range(0.0, 1.0, 0.01) var lens_irregularity := 0.7:
	set(v): lens_irregularity = clampf(v, 0.0, 1.0); _queue_apply()
## 已有灯光/光晕经水滴折射产生的局部亮斑强度，保留光源颜色。
@export_range(0.0, 2.0, 0.05) var lens_light_response := 0.55:
	set(v): lens_light_response = maxf(v, 0.0); _queue_apply()
## 弧形高光和下侧暗边的强度，帮助辨认透明水滴的轮廓。
@export_range(0.0, 0.5, 0.01) var lens_rim_strength := 0.18:
	set(v): lens_rim_strength = clampf(v, 0.0, 0.5); _queue_apply()
## 人物周围的水滴保护半径，相对画面高度；0 关闭保护。
@export_range(0.0, 0.35, 0.01) var lens_center_protection := 0.14:
	set(v): lens_center_protection = maxf(v, 0.0); _queue_apply()

@export_group("场景引用")
@export var camera: Camera3D:
	set(v): camera = v; _queue_apply()
@export var dressing: Node3D:
	set(v): dressing = v; _queue_apply()
@export var post_process: CanvasItem:
	set(v): post_process = v; _queue_apply()
@export var terrain: Terrain:
	set(v): terrain = v; _queue_apply()

var _rain: GPUParticles3D
var _rain_process: ParticleProcessMaterial
var _rain_material: ShaderMaterial
var _rain_mesh: QuadMesh
var _post: ShaderMaterial
var _vegetation: Array[ShaderMaterial] = []
var _drops: Array[Dictionary] = []
var _random := RandomNumberGenerator.new()
var _last_seed := -1
var _until_drop := 0.0
var _clock := 0.0
var _apply_queued := false
var _rain_audio: AudioStreamPlayer
var _audio_source: AudioStream
var _audio_level := 0.0
var _wind_audio: AudioStreamPlayer
var _wind_source: AudioStream
var _wind_audio_level := 0.0
var _water: ShaderMaterial
var _ground: ShaderMaterial
var _wetness := 0.0

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_apply()

func _queue_apply() -> void:
	if not is_inside_tree() or _apply_queued:
		return
	_apply_queued = true
	_apply.call_deferred()

func _active() -> bool:
	return enabled and (not Engine.is_editor_hint() or editor_preview)

func _rainfall() -> float:
	return rain_intensity if _active() and weather_mode == 1 else 0.0

func _effective_wind() -> float:
	return wind_strength + _rainfall() * rain_wind_boost if _active() and wind_enabled else 0.0

func _ensure_rain() -> void:
	if is_instance_valid(_rain):
		return
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.emitting = false
	_rain.local_coords = false
	_rain.fixed_fps = 60
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_process = ParticleProcessMaterial.new()
	_rain_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_process.gravity = Vector3.ZERO
	_rain_process.spread = 2.0
	_rain.process_material = _rain_process
	_rain_material = ShaderMaterial.new()
	_rain_material.shader = RAIN_SHADER
	_rain_mesh = QuadMesh.new()
	_rain_mesh.material = _rain_material
	_rain.draw_pass_1 = _rain_mesh
	add_child(_rain)

func _apply() -> void:
	_apply_queued = false
	if not is_inside_tree():
		return
	_ensure_rain()
	if weather_seed != _last_seed:
		_last_seed = weather_seed
		_random.seed = weather_seed
		_drops.clear()
		_until_drop = 0.0
		_rain.use_fixed_seed = true
		_rain.seed = weather_seed
	var direction := wind_direction.normalized()
	var slant := direction * _effective_wind() * 0.12
	_rain_process.direction = Vector3(slant.x, -1.0, slant.y).normalized()
	_rain_process.initial_velocity_min = rain_speed
	_rain_process.initial_velocity_max = rain_speed * 1.2
	_rain_process.emission_box_extents = Vector3(rain_area.x * 0.5, 0.5, rain_area.y * 0.5)
	_rain_mesh.size = rain_streak_size
	_rain_material.set_shader_parameter("rain_color", rain_color)
	_rain_material.set_shader_parameter("slant", slant)
	if _rain.amount != rain_amount:
		_rain.amount = rain_amount
	_rain.lifetime = (rain_height + 3.0) / rain_speed
	_rain.amount_ratio = _rainfall()
	_rain.emitting = _rainfall() > 0.0
	_rain.visible = _active()
	_rain.visibility_aabb = AABB(Vector3(-rain_area.x, -rain_height - 5.0, -rain_area.y), Vector3(rain_area.x * 2.0, rain_height + 7.0, rain_area.y * 2.0))
	if not _active() or not lens_drops_enabled or Engine.is_editor_hint():
		_drops.clear()
	if _drops.size() > lens_drop_limit:
		_drops.resize(lens_drop_limit)
	if dressing and dressing.has_signal("dressing_rebuilt") and not dressing.is_connected("dressing_rebuilt", _refresh_vegetation):
		dressing.connect("dressing_rebuilt", _refresh_vegetation)
	_refresh_vegetation()
	_bind_post()
	_apply_lens_settings()
	_follow_rain()
	_apply_audio()
	_apply_wind_audio()
	_apply_surface()

func _bind_surface() -> void:
	if not terrain:
		return
	var water := terrain.water_material as ShaderMaterial
	var ground := terrain.top_material
	if water != _water or ground != _ground:
		_water = water
		_ground = ground
		_apply_surface()

func _apply_surface() -> void:
	if not terrain:
		return
	_water = terrain.water_material as ShaderMaterial
	_ground = terrain.top_material
	if _water:
		_water.set_shader_parameter("rain_amount", _rainfall() if water_rain_enabled else 0.0)
		_water.set_shader_parameter("rain_density", water_ripple_density)
		_water.set_shader_parameter("rain_radius", water_ripple_size)
		_water.set_shader_parameter("rain_lifetime", water_ripple_lifetime)
		_water.set_shader_parameter("rain_strength", water_ripple_strength)
	if _ground:
		_ground.set_shader_parameter("rain_amount", _rainfall() if ground_rain_enabled else 0.0)
		_ground.set_shader_parameter("rain_density", ground_splash_density)
		_ground.set_shader_parameter("rain_radius", ground_splash_size)
		_ground.set_shader_parameter("rain_strength", ground_splash_strength)
	_update_surface(0.0)

func _update_surface(delta: float) -> void:
	var target := _rainfall() * rain_wetness if ground_rain_enabled else 0.0
	if Engine.is_editor_hint():
		_wetness = target
	elif not _active() or not ground_rain_enabled:
		_wetness = 0.0
	else:
		var duration := wetting_time if target > _wetness else drying_time
		_wetness = move_toward(_wetness, target, delta * maxf(rain_wetness, 0.001) / duration)
	if _water:
		_water.set_shader_parameter("rain_clock", _clock)
	if _ground:
		_ground.set_shader_parameter("rain_clock", _clock)
		_ground.set_shader_parameter("weather_wetness", _wetness)

func _apply_audio() -> void:
	if Engine.is_editor_hint():
		return
	if not is_instance_valid(_rain_audio):
		_rain_audio = AudioStreamPlayer.new()
		_rain_audio.name = "RainAudio"
		_rain_audio.volume_db = -80.0
		add_child(_rain_audio)
	_rain_audio.bus = rain_audio_bus if AudioServer.get_bus_index(rain_audio_bus) >= 0 else &"Master"
	if _audio_source != rain_sound:
		_audio_source = rain_sound
		_audio_level = 0.0
		_rain_audio.stop()
		_rain_audio.stream = rain_sound.duplicate() as AudioStream if rain_sound else null
		var stream := _rain_audio.stream
		if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
			stream.loop = true
		elif stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = roundi(stream.get_length() * stream.mix_rate)

func _update_audio(delta: float) -> void:
	if not is_instance_valid(_rain_audio):
		return
	var target := sqrt(_rainfall()) if rain_audio_enabled and _rain_audio.stream else 0.0
	_audio_level = move_toward(_audio_level, target, delta / rain_audio_fade_time)
	_rain_audio.volume_db = rain_volume_db + linear_to_db(maxf(_audio_level, 0.0001))
	if _audio_level > 0.0001:
		if not _rain_audio.playing:
			_rain_audio.play()
	elif _rain_audio.playing:
		_rain_audio.stop()

func _apply_wind_audio() -> void:
	if Engine.is_editor_hint():
		return
	if not is_instance_valid(_wind_audio):
		_wind_audio = AudioStreamPlayer.new()
		_wind_audio.name = "WindAudio"
		_wind_audio.volume_db = -80.0
		add_child(_wind_audio)
	_wind_audio.bus = wind_audio_bus if AudioServer.get_bus_index(wind_audio_bus) >= 0 else &"Master"
	if _wind_source != wind_sound:
		_wind_source = wind_sound
		_wind_audio_level = 0.0
		_wind_audio.stop()
		_wind_audio.stream = wind_sound.duplicate() as AudioStream if wind_sound else null
		var stream := _wind_audio.stream
		if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
			stream.loop = true
		elif stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = roundi(stream.get_length() * stream.mix_rate)

func _update_wind_audio(delta: float) -> void:
	if not is_instance_valid(_wind_audio):
		return
	var target := sqrt(clampf(_effective_wind() / 3.0, 0.0, 1.0)) if wind_audio_enabled and _wind_audio.stream else 0.0
	_wind_audio_level = move_toward(_wind_audio_level, target, delta / wind_audio_fade_time)
	_wind_audio.volume_db = wind_volume_db + linear_to_db(maxf(_wind_audio_level, 0.0001))
	if _wind_audio_level > 0.0001:
		if not _wind_audio.playing:
			_wind_audio.play()
	elif _wind_audio.playing:
		_wind_audio.stop()

func _refresh_vegetation() -> void:
	_vegetation.clear()
	if not dressing:
		return
	for batch: MultiMeshInstance3D in dressing.find_children("*", "MultiMeshInstance3D", true, false):
		var material := batch.multimesh.mesh.material as ShaderMaterial
		if not material or _vegetation.has(material):
			continue
		_vegetation.append(material)
		material.set_shader_parameter("wind_direction", wind_direction.normalized())
		material.set_shader_parameter("wind_strength", _effective_wind())
		material.set_shader_parameter("wind_speed", wind_speed)
		material.set_shader_parameter("gust_strength", gust_strength)
		material.set_shader_parameter("flexibility", grass_sway if String(batch.name).begins_with("grass_") else flower_sway)
		material.set_shader_parameter("wind_time", _clock)

func _bind_post() -> void:
	if post_process and post_process.material is ShaderMaterial and _post != post_process.material:
		_post = post_process.material as ShaderMaterial
		_apply_lens_settings()

func _apply_lens_settings() -> void:
	if not _post:
		return
	_post.set_shader_parameter("lens_blur", lens_blur)
	_post.set_shader_parameter("lens_refraction", lens_refraction)
	_post.set_shader_parameter("lens_irregularity", lens_irregularity)
	_post.set_shader_parameter("lens_light_response", lens_light_response)
	_post.set_shader_parameter("lens_rim_strength", lens_rim_strength)
	_post.set_shader_parameter("lens_center_protection", lens_center_protection)
	_write_drops()

func _follow_rain() -> void:
	if not camera or not is_instance_valid(_rain):
		return
	var ahead := -camera.global_basis.z
	ahead.y = 0.0
	var center := camera.global_position + ahead.normalized() * 8.0
	_rain.global_position = Vector3(center.x, camera.global_position.y + rain_height, center.z)

func _process(delta: float) -> void:
	if not is_instance_valid(_rain):
		_apply()
	_clock += delta
	for material in _vegetation:
		material.set_shader_parameter("wind_time", _clock)
	_follow_rain()
	_bind_post()
	_bind_surface()
	_update_surface(delta)
	if not Engine.is_editor_hint():
		_advance_drops(delta)
		_update_audio(delta)
		_update_wind_audio(delta)

func _advance_drops(delta: float) -> void:
	for index in range(_drops.size() - 1, -1, -1):
		var drop: Dictionary = _drops[index]
		drop["age"] += delta
		drop["uv"].y += lens_slide_speed * float(drop["slide"]) * delta / 900.0
		if float(drop["age"]) >= float(drop["lifetime"]) or drop["uv"].y > 1.1:
			_drops.remove_at(index)
	var rate := lens_drop_rate * _rainfall() if lens_drops_enabled else 0.0
	if rate > 0.0:
		_until_drop -= delta
		if _until_drop <= 0.0:
			_spawn_drop()
			_until_drop = -log(maxf(_random.randf(), 0.00001)) / rate
	_write_drops()

func _spawn_drop() -> void:
	if _drops.size() >= lens_drop_limit:
		return
	var center: Vector2 = _post.get_shader_parameter("ellipse_center") if _post else Vector2(0.5, 0.5)
	var aspect := get_viewport().get_visible_rect().size.x / get_viewport().get_visible_rect().size.y
	for attempt in 20:
		var uv := Vector2(_random.randf_range(0.05, 0.95), _random.randf_range(0.05, 0.9))
		if ((uv - center) * Vector2(aspect, 1.0)).length() < lens_center_protection + 0.04:
			continue
		var shape := Vector4(_random.randf_range(0.0, TAU), _random.randf_range(0.8, 1.55), _random.randf_range(-0.4, 0.4), _random.randf())
		_drops.append({"uv": uv, "radius": _random.randf_range(minf(lens_drop_size.x, lens_drop_size.y), maxf(lens_drop_size.x, lens_drop_size.y)), "age": 0.0, "lifetime": lens_drop_lifetime * _random.randf_range(0.8, 1.2), "slide": _random.randf_range(0.6, 1.4), "shape": shape})
		return

func _write_drops() -> void:
	if not _post:
		return
	var values := PackedVector4Array()
	values.resize(MAX_DROPS)
	var shapes := PackedVector4Array()
	shapes.resize(MAX_DROPS)
	for index in mini(_drops.size(), MAX_DROPS):
		var drop: Dictionary = _drops[index]
		var fade := smoothstep(0.0, 0.15, float(drop["age"])) * smoothstep(0.0, minf(lens_fade_time, float(drop["lifetime"]) * 0.5), float(drop["lifetime"]) - float(drop["age"]))
		var radius: float = drop["radius"] * lerpf(0.7, 1.0, smoothstep(0.0, 0.2, float(drop["age"])))
		values[index] = Vector4(drop["uv"].x, drop["uv"].y, radius, fade)
		shapes[index] = drop.get("shape", Vector4(0.0, 1.2, 0.0, 0.0))
	_post.set_shader_parameter("lens_enabled", _active() and lens_drops_enabled and not _drops.is_empty())
	_post.set_shader_parameter("lens_drop_count", mini(_drops.size(), MAX_DROPS))
	_post.set_shader_parameter("lens_drops", values)
	_post.set_shader_parameter("lens_drop_shapes", shapes)

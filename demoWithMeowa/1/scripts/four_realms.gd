extends Node3D

# 与 TerrainData.Biome 顺序一致
const ZONE_NAMES: Array[String] = ["城市街区", "赛博朋克", "修仙庭院", "野外林地"]

@onready var camera: FollowCamera = $Camera3D
@onready var environment: Environment = $WorldEnvironment.environment
@onready var player: CharacterBody3D = $Player
@onready var status: Label = $HUD/Panel/Margin/Column/Status
@onready var terrain: Terrain = $World/Ground
var shadows_enabled: bool = true
var current_zone: int = -1
var moods: LightingMoods
var mood_index: int = 0

func _ready() -> void:
	var world_rect := terrain.get_world_rect()
	player.bounds = world_rect.grow(-0.3)
	camera.set_world_rect(world_rect)
	camera.snap_to_target()
	moods = LightingMoods.new(environment, $Moon)
	$HUD/Panel/Margin/Column/Effects/Glow.toggled.connect(_set_glow)
	$HUD/Panel/Margin/Column/Effects/Shadows.toggled.connect(_set_shadows)
	$HUD/Panel/Margin/Column/Effects/Fog.toggled.connect(_set_fog)
	_update_status()
	if "--capture" in OS.get_cmdline_user_args():
		_capture_preview()

func _process(_delta: float) -> void:
	if _zone_at(player.global_position) != current_zone:
		_update_status()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_G:
		$HUD/Panel/Margin/Column/Effects/Glow.button_pressed = not environment.glow_enabled
	elif event.keycode == KEY_H:
		$HUD/Panel/Margin/Column/Effects/Shadows.button_pressed = not shadows_enabled
	elif event.keycode == KEY_F:
		$HUD/Panel/Margin/Column/Effects/Fog.button_pressed = not environment.volumetric_fog_enabled
	elif event.keycode == KEY_L:
		_set_mood((mood_index + 1) % moods.count())
	elif event.keycode == KEY_R:
		$ArtDirection.water_reflection_enabled = not $WaterReflection.enabled

func _zone_at(point: Vector3) -> int:
	return terrain.data.get_biome(terrain.data.world_to_cell(point - terrain.global_position))

func _set_glow(enabled: bool) -> void:
	environment.glow_enabled = enabled
	_update_status()

func _set_shadows(enabled: bool) -> void:
	shadows_enabled = enabled
	$ArtDirection.street_shadows_enabled = enabled
	for lamp in get_tree().get_nodes_in_group("environment_lanterns"):
		lamp.shadows_enabled = enabled
	for light: Light3D in get_tree().get_nodes_in_group("shadow_lights"):
		light.shadow_enabled = enabled
	_update_status()

func _set_fog(enabled: bool) -> void:
	# Keep the master setting in sync so a queued material update cannot restore fog.
	$ArtDirection.volumetric_fog = enabled
	environment.volumetric_fog_enabled = enabled
	for lamp in get_tree().get_nodes_in_group("environment_lanterns"):
		lamp.apply()
	for dust: GPUParticles3D in get_tree().get_nodes_in_group("street_light_dust"):
		dust.visible = enabled and dust.emitting
	for beam: MeshInstance3D in get_tree().get_nodes_in_group("light_beams"):
		if beam.get_parent().is_in_group("environment_lanterns"):
			continue # These lamps apply their own beam strength above.
		beam.visible = enabled and $ArtDirection.cone_enabled and $ArtDirection.cone_shape_gain > 0.0
	_update_status()

func _set_mood(index: int) -> void:
	mood_index = index
	moods.apply(index)
	_update_status()

func _update_status() -> void:
	current_zone = _zone_at(player.global_position)
	status.text = "%s    ·    泛光 %s / 阴影 %s / 雾效 %s / 光照 %s" % [ZONE_NAMES[current_zone], "开" if environment.glow_enabled else "关", "开" if shadows_enabled else "关", "开" if environment.volumetric_fog_enabled else "关", moods.name_of(mood_index) if moods else "原始"]

func _capture_preview() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--capture")
	if index + 1 >= args.size():
		get_tree().quit(1)
		return
	if "--at" in args:
		var coords := args[args.find("--at") + 1].split(",")
		player.global_position = Vector3(float(coords[0]), 2.6, float(coords[1]))
		player.reset_physics_interpolation()
		camera.snap_to_target()
	if "--no-glow" in args:
		_set_glow(false)
	if "--no-shadows" in args:
		_set_shadows(false)
	if "--no-fog" in args:
		_set_fog(false)
	if "--mood" in args:
		_set_mood(int(args[args.find("--mood") + 1]))
	if "--no-dof" in args:
		camera.dof_enabled = false
	for frame in range(40):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(args[index + 1])
	print("Preview saved: %s (error=%d)" % [args[index + 1], error])
	get_tree().quit(0 if error == OK else 1)

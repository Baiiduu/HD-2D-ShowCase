extends Node3D

## 独立素材验看场景：沿用四境画面、相机与光照，在人物附近排列素材。
## 主场景不依赖本脚本；这里只展示尺寸与透明边，不承担正式地编分布。
const PACK := "res://assets/meowa/dressing/assets.json"
const GROUPS: Array[String] = ["flowers", "grass", "pebbles"]
var _sprites: Dictionary = {}

func _ready() -> void:
	var world: Node3D = load("res://scenes/four_realms.tscn").instantiate()
	add_child(world)
	world.get_node("World/GroundDressing").hide()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var player: CharacterBody3D = world.get_node("Player")
	# 对比时人物与六个变种处于同一深度，避免透视把前排素材显得过大。
	var camera_anchor := Node3D.new()
	camera_anchor.position = Vector3(0.0, 0.02, 1.4)
	world.add_child(camera_anchor)
	var camera: FollowCamera = world.get_node("Camera3D")
	camera.target = camera_anchor
	camera.snap_to_target()
	# 用人物原始 Sprite3D 作静态比例尺，避免现有建筑碰撞把验看人物挤开。
	player.hide()
	player.set_physics_process(false)
	var reference: Sprite3D = player.get_node("Sprite").duplicate()
	reference.name = "CharacterScaleReference"
	reference.texture = player.animations.get_frame_texture(&"idle", 0)
	reference.position = Vector3(-3.4, 0.77, 1.4)
	add_child(reference)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PACK))
	var entries: Array = manifest["assets"]
	for i in entries.size():
		var item: Dictionary = entries[i]
		var group: String = item["id"].get_slice("_", 0)
		var point := Vector3(-1.9 + (i % 6) * 0.9, 0.0, 1.4)
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 10.0, point - Vector3.UP * 10.0)
		query.exclude = [player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			point.y = hit["position"].y
		var sprite := Sprite3D.new()
		sprite.name = item["id"]
		sprite.texture = load(item["texture"])
		sprite.pixel_size = item["pixel_size"]
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sprite.shaded = true
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		# 图片底部落点位于 (24,44)，中心在 (24,24)。只平移，不缩放。
		sprite.position = point + Vector3.UP * (item["anchor"][1] - item["canvas"][1] * 0.5) * sprite.pixel_size
		add_child(sprite)
		if not _sprites.has(group):
			_sprites[group] = []
		_sprites[group].append(sprite)
	_show_group("flowers")
	print("Dressing preview: %d sprites, original character pixel size, nearest sampling" % entries.size())
	var args := OS.get_cmdline_user_args()
	var capture_index := args.find("--dressing-capture")
	if capture_index >= 0 and capture_index + 1 < args.size():
		for frame in 80:
			await get_tree().process_frame
		var capture_base := args[capture_index + 1].get_basename()
		for group in GROUPS:
			_show_group(group)
			for frame in 12:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var error := get_viewport().get_texture().get_image().save_png(capture_base + "-" + group + ".png")
			print("Dressing preview saved: %s error=%d" % [group, error])
			if error != OK:
				get_tree().quit(1)
				return
		get_tree().quit(0)

func _show_group(group: String) -> void:
	for category in _sprites:
		for sprite: Sprite3D in _sprites[category]:
			sprite.visible = category == group

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			_show_group("flowers")
		elif event.keycode == KEY_2:
			_show_group("grass")
		elif event.keycode == KEY_3:
			_show_group("pebbles")

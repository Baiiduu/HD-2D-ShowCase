extends SceneTree
## 一次性脚本：在原有四境地图东侧扩出一片带高差的野外区域。
## 用法：godot --headless --path . -s res://tools/expand_terrain_east.gd

const PATH := "res://data/four_realms_terrain.tres"

func _initialize() -> void:
	var data: TerrainData = load(PATH)
	data.resize(Vector2i(-7, -6), Vector2i(30, 13))
	for z in range(-6, 7):
		for x in range(8, 23):
			var cell := Vector2i(x, z)
			data.set_biome(cell, TerrainData.Biome.WILD)
			# 北侧高地（第 1 层），东北角再抬一层台地（第 2 层）
			var level := 1 if z <= -2 else 0
			if x >= 17 and x <= 21 and z <= -4:
				level = 2
			data.set_level(cell, level)
	# 东西大路继续向东延伸
	for x in range(8, 23):
		data.set_overlay(Vector2i(x, 0), TerrainData.OVERLAY_PATH, true)
	# 高地溪流：河床比高地低一层；流到高地南缘后跌落成瀑布，进入低地溪流
	for z in range(-6, -1):
		_water(data, Vector2i(14, z), 0)
	for cell in [Vector2i(14, -1), Vector2i(14, 0), Vector2i(14, 1), Vector2i(14, 2), Vector2i(14, 3),
			Vector2i(15, 3), Vector2i(15, 4), Vector2i(15, 5), Vector2i(15, 6)]:
		_water(data, cell, -1)
	data.set_overlay(Vector2i(14, 0), TerrainData.OVERLAY_BRIDGE, true)
	# 上山小路：坡道上高地，木桥过溪，再上坡道到第 2 层台地
	for cell in [Vector2i(10, -1), Vector2i(10, -2), Vector2i(10, -3), Vector2i(11, -3), Vector2i(12, -3),
			Vector2i(13, -3), Vector2i(15, -3), Vector2i(16, -3), Vector2i(17, -3), Vector2i(18, -3),
			Vector2i(18, -4), Vector2i(18, -5)]:
		data.set_overlay(cell, TerrainData.OVERLAY_DIRT, true)
	data.set_overlay(Vector2i(10, -1), TerrainData.OVERLAY_RAMP, true)
	data.set_overlay(Vector2i(18, -3), TerrainData.OVERLAY_RAMP, true)
	data.set_overlay(Vector2i(14, -3), TerrainData.OVERLAY_BRIDGE, true)
	print("save: ", ResourceSaver.save(data, PATH))
	quit()

func _water(data: TerrainData, cell: Vector2i, bed_level: int) -> void:
	data.set_level(cell, bed_level)
	data.set_overlay(cell, TerrainData.OVERLAY_WATER, true)

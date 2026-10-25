class_name ScreenshotRunner
extends Node
## Unattended screenshot mode.
##   Godot --path . -- --screenshots            all five reference shots
##   Godot --path . -- --shot=x,z[,name]        a single custom shot
## Images are written at 1280x800 to <project>/screenshots/.

const SHOTS := [
	["shot_1_crossroads.png", Vector2(0.0, 1.4)],
	["shot_2_city_lamp.png", Vector2(-2.4, -0.6)],
	["shot_3_wild.png", Vector2(6.0, 3.0)],
	["shot_4_waterfall.png", Vector2(22.4, 2.5)],
	["shot_5_highland.png", Vector2(28.0, -4.8)],
]
const SIZE := Vector2i(1280, 800)
const SETTLE_SEC := 3.0
const SETTLE_FRAMES := 150


static func debug_cam() -> Array:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cam="):
			var p := a.substr(6).split(",")
			return [Vector3(float(p[0]), float(p[1]), float(p[2])), Vector3(float(p[3]), float(p[4]), float(p[5]))]
	return []


static func wanted() -> Array:
	var out: Array = []
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a == "--screenshots":
			out = SHOTS.duplicate()
		elif a.begins_with("--shot="):
			var p := a.substr(7).split(",")
			var nm := "shot_custom.png" if p.size() < 3 else p[2] + ".png"
			out.append([nm, Vector2(float(p[0]), float(p[1]))])
	return out


func run(main: Node, shots: Array) -> void:
	var win := get_window()
	win.mode = Window.MODE_WINDOWED
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	win.size = SIZE
	var dir := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	set_process_input(false)
	var player: Node3D = main.player
	var rig: Node3D = main.rig
	player.set_process(false)   # no keyboard input while capturing
	for s in shots:
		player.place(s[1])
		rig.snap()
		# let camera, temporal fog, SDFGI cascades and particles converge
		var t0 := Time.get_ticks_msec()
		var frames := 0
		while frames < SETTLE_FRAMES or Time.get_ticks_msec() - t0 < SETTLE_SEC * 1000.0:
			await get_tree().process_frame
			rig.snap()
			frames += 1
		await RenderingServer.frame_post_draw
		if OS.get_cmdline_user_args().has("--fps"):
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			for i in 30:
				await get_tree().process_frame
			var f0 := Engine.get_frames_drawn()
			var m0 := Time.get_ticks_usec()
			while Time.get_ticks_usec() - m0 < 5000000:
				await get_tree().process_frame
			var fps := (Engine.get_frames_drawn() - f0) / ((Time.get_ticks_usec() - m0) / 1000000.0)
			print("fps %s: %.1f" % [s[0], fps])
		var dc := debug_cam()
		if not dc.is_empty():
			rig.set_process(false)
			rig.cam.fov = 50.0
			rig.cam.global_transform = Transform3D(Basis.looking_at(dc[1] - dc[0], Vector3.UP), dc[0])
			for i in 60:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img.get_size() != SIZE:
			push_warning("viewport is %s, resizing capture to 1280x800" % [img.get_size()])
			img.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
		var path: String = dir.path_join(s[0])
		img.save_png(path)
		print("saved ", path)
	get_tree().quit()

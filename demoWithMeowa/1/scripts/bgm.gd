@tool
extends Node

## 探索背景音乐。只在游戏中播放，两路交叉淡化避免循环时突兀切断。
@export_group("背景音乐")
@export var music_enabled := true
@export var music_stream: AudioStream = preload("res://assets/meowa/audio/bgm.mp3"):
	set(v): music_stream = v; _configure()
## 素材的播放增益；负数越小，音乐越轻。
@export_range(-40.0, 6.0, 0.5) var music_volume_db := -20.0
## 开关音乐时的淡入淡出时间，秒。
@export_range(0.1, 10.0, 0.1) var music_fade_time := 3.0
## 循环末尾与开头的交叉淡化时间，秒；短素材自动缩短。
@export_range(0.1, 15.0, 0.1) var music_loop_crossfade := 6.0
## 项目中已有的音频总线名称；不存在时使用 Master。
@export var music_bus: StringName = &"Master"

var _players: Array[AudioStreamPlayer] = []
var _source: AudioStream
var _active := 0
var _level := 0.0
var _blending := false
var _blend_time := 0.0
var _blend_duration := 0.0

func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	_configure()

func _configure() -> void:
	if not is_inside_tree() or Engine.is_editor_hint():
		return
	if _players.is_empty():
		for index in range(2):
			var player := AudioStreamPlayer.new()
			player.name = "Music%d" % index
			player.volume_db = -80.0
			add_child(player)
			_players.append(player)
	if _source == music_stream:
		return
	_source = music_stream
	_level = 0.0
	_active = 0
	_blending = false
	for player in _players:
		player.stop()
		player.stream = music_stream.duplicate() as AudioStream if music_stream else null
		if player.stream is AudioStreamMP3 or player.stream is AudioStreamOggVorbis:
			player.stream.loop = false
		elif player.stream is AudioStreamWAV:
			player.stream.loop_mode = AudioStreamWAV.LOOP_DISABLED

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _players.is_empty():
		return
	var target := 1.0 if music_enabled and music_stream else 0.0
	_level = move_toward(_level, target, delta / maxf(music_fade_time, 0.1))
	if _level <= 0.0001:
		for player in _players:
			player.stop()
		_blending = false
		return
	var current := _players[_active]
	var next := _players[1 - _active]
	if not current.playing and not _blending:
		current.play()
	if _blending:
		_blend_time += delta
		if _blend_time >= _blend_duration:
			current.stop()
			_active = 1 - _active
			_blending = false
	else:
		_blend_duration = minf(maxf(music_loop_crossfade, 0.1), music_stream.get_length() * 0.25)
		if current.get_playback_position() >= music_stream.get_length() - _blend_duration:
			next.play()
			_blend_time = 0.0
			_blending = true
	var phase := clampf(_blend_time / _blend_duration, 0.0, 1.0) if _blending else 0.0
	var bus := music_bus if AudioServer.get_bus_index(music_bus) >= 0 else &"Master"
	for index in range(2):
		var gain := cos(phase * PI * 0.5) if index == _active else sin(phase * PI * 0.5)
		_players[index].bus = bus
		_players[index].volume_db = music_volume_db + linear_to_db(maxf(_level * gain, 0.0001))

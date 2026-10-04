extends Node

signal track_changed(name: String)

const FADE_TIME := 1.2
const BATTLE_STINGER_TIME := 0.4

var player_a: AudioStreamPlayer
var player_b: AudioStreamPlayer
var stinger_player: AudioStreamPlayer
var active: AudioStreamPlayer
var current_track_name: String = ""
var paused_track: AudioStream = null

func _ready() -> void:
	player_a = _make_player("MusicA")
	player_b = _make_player("MusicB")
	stinger_player = _make_player("Stinger")
	active = player_a

func _make_player(name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = name
	p.bus = "Master"
	p.volume_db = -10.0
	add_child(p)
	return p

func play_music(stream: AudioStream, track_name: String = "", fade: float = FADE_TIME) -> void:
	if stream == null:
		stop(fade)
		return
	if current_track_name == track_name and active.stream == stream:
		return
	current_track_name = track_name
	track_changed.emit(track_name)
	var next: AudioStreamPlayer = player_b if active == player_a else player_a
	next.stream = stream
	next.volume_db = -60.0
	next.play()
	# Crossfade
	var tween := create_tween().set_parallel(true)
	tween.tween_property(next, "volume_db", -10.0, fade)
	if active.playing:
		tween.tween_property(active, "volume_db", -60.0, fade)
		tween.chain().tween_callback(active.stop)
	active = next

func stop(fade: float = 0.5) -> void:
	if active and active.playing:
		var tw := create_tween()
		tw.tween_property(active, "volume_db", -60.0, fade)
		tw.tween_callback(active.stop)
	current_track_name = ""

func play_battle_music(stream: AudioStream) -> void:
	# Guarda la pista anterior para restaurarla al fin de combate
	if active and active.playing:
		paused_track = active.stream
	play_music(stream, "battle", BATTLE_STINGER_TIME)

func restore_after_battle(field_stream: AudioStream = null) -> void:
	if field_stream != null:
		play_music(field_stream, "field")
		paused_track = null
		return
	if paused_track != null:
		play_music(paused_track, "field")
		paused_track = null

func play_stinger(stinger: AudioStream) -> void:
	if stinger == null: return
	stinger_player.stream = stinger
	stinger_player.volume_db = 0.0
	stinger_player.play()

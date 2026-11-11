extends Node
## Background music (assets/music/, made from art_source/music/ by
## tools/prep_music.sh): "menu" (Majestic Crescendo) on the start screen,
## "battle" (Antes de la Batalla) in a game. Tracks loop and crossfade.
## Plays on the "Music" bus, so the Settings volume applies.

const Settings := preload("res://scripts/settings.gd")
const TRACKS := {
	"menu": preload("res://assets/music/majestic_crescendo.ogg"),
	"battle": preload("res://assets/music/antes_de_la_batalla.ogg"),
}
const FADE := 1.2
## The music sits under the voices and effects (at slider 100%).
const LEVEL_DB := -8.0

var current := ""
var _players: Array = []
var _active := 0


func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = Settings.music_bus()
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)


## Starts a track (fading out whatever was playing). Same track: nothing.
func play(track: String) -> void:
	if track == current or not TRACKS.has(track):
		return
	current = track
	var old: AudioStreamPlayer = _players[_active]
	_active = 1 - _active
	var new: AudioStreamPlayer = _players[_active]
	var stream: AudioStream = TRACKS[track].duplicate()
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	new.stream = stream
	new.volume_db = -40.0
	new.play()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(new, "volume_db", LEVEL_DB, FADE)
	if old.playing:
		tween.tween_property(old, "volume_db", -80.0, FADE)
		tween.chain().tween_callback(old.stop)

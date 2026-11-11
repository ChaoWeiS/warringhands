extends Node
## Unit voices (assets/sounds/, made from art_source/sounds/ by
## tools/prep_sounds.sh):
##   acknowledge: a unit is selected        objective: it's given an order
##   attack: it swings at someone           defend: a blow lands on it
##   death: it falls
## and building sounds: build_place (a thud and hammer knocks when a
## construction is laid down), build_done (when it's finished; made by
## tools/make_build_sounds.py). All on the "SFX" bus (Settings volume).
## Every selected unit answers with the same line, together (a small chorus:
## each a hair apart in pitch and timing, so the words stay clear; quieter
## the more there are). Combat
## sounds play only for units on screen, and only so many at once.
## Purely cosmetic: nothing here touches the simulation.

const CLIPS := {
	"acknowledge": [
		preload("res://assets/sounds/acknowledge_yes.ogg"),
		preload("res://assets/sounds/acknowledge_wassup.ogg"),
		preload("res://assets/sounds/acknowledge_waduwant.ogg"),
	],
	"objective": [
		preload("res://assets/sounds/objective_ok.ogg"),
		preload("res://assets/sounds/objective_roger.ogg"),
		preload("res://assets/sounds/objective_letsgo.ogg"),
		preload("res://assets/sounds/objective_affirmative.ogg"),
	],
	"attack": [
		preload("res://assets/sounds/attack_hootah.ogg"),
		preload("res://assets/sounds/attack_chiongah.ogg"),
		preload("res://assets/sounds/attack_slapuah.ogg"),
	],
	"defend": [
		preload("res://assets/sounds/defend_ouch.ogg"),
		preload("res://assets/sounds/defend_ayah.ogg"),
		preload("res://assets/sounds/defend_aaaaaa.ogg"),
	],
	"build_place": [preload("res://assets/sounds/build_place.ogg")],
	"build_done": [preload("res://assets/sounds/build_done.ogg")],
	"death": [
		preload("res://assets/sounds/death_dead.ogg"),
		preload("res://assets/sounds/death_ouch.ogg"),
		preload("res://assets/sounds/death_mampos.ogg"),
		preload("res://assets/sounds/death_siliao.ogg"),
		preload("res://assets/sounds/death_makauhijau.ogg"),
	],
}
## Voices that can sound at once (the rest are skipped).
const MAX_VOICES := 16
## A selection's chorus: at most this many voices, spread over this long
## (short enough to sound like one shout, long enough to sound like a crowd).
const MAX_CHORUS := 12
const CHORUS_SPREAD := 0.04
const CHORUS_PITCH := 0.05
## Combat: at most this many sounds of one kind per window (s).
const COMBAT_LIMIT := 4
const COMBAT_WINDOW := 0.3
const BASE_DB := -4.0

## Is a point in the world on screen (in any pane)? Set by the game.
var on_screen: Callable = func(_pos: Vector3) -> bool: return true
## Everything played (category), newest last; tests read it.
var played: Array = []
var played_clips: Array = []  # which recording, in the same order

var _voices: Array = []
var _rng := RandomNumberGenerator.new()
var _recent := {}  # category -> Array of times (s)


func _ready() -> void:
	_rng.randomize()
	for i in MAX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = load("res://scripts/settings.gd").sfx_bus()
		add_child(p)
		_voices.append(p)


## Every one of these units answers at once (acknowledge / objective).
func respond(category: String, unit_ids: Array) -> void:
	var count: int = mini(unit_ids.size(), MAX_CHORUS)
	if count == 0:
		return
	# Quieter per voice the bigger the group, so a crowd doesn't distort.
	var db: float = BASE_DB - 6.0 * log(float(count)) / log(4.0)
	var clip: AudioStream = _pick(category)
	if clip == null:
		return
	for i in count:
		var delay: float = 0.0 if i == 0 else _rng.randf() * CHORUS_SPREAD
		var pitch: float = 1.0 if i == 0 else _rng.randf_range(1.0 - CHORUS_PITCH, 1.0 + CHORUS_PITCH)
		_play_clip(category, clip, db, delay, pitch)


## One unit's combat sound at a place in the world (if it's on screen).
func unit_event(category: String, at: Vector3) -> void:
	if not on_screen.call(at):
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var times: Array = _recent.get(category, [])
	times = times.filter(func(t): return now - t < COMBAT_WINDOW)
	if times.size() >= COMBAT_LIMIT:
		_recent[category] = times
		return
	times.append(now)
	_recent[category] = times
	var clip: AudioStream = _pick(category)
	if clip != null:
		_play_clip(category, clip, BASE_DB - 2.0, 0.0, _rng.randf_range(0.92, 1.12))


func _pick(category: String) -> AudioStream:
	var clips: Array = CLIPS.get(category, [])
	return null if clips.is_empty() else clips[_rng.randi() % clips.size()]


func _play_clip(category: String, clip: AudioStream, db: float, delay: float, pitch: float) -> void:
	played.append(category)
	played_clips.append(clip)
	if played.size() > 200:
		played = played.slice(-100)
		played_clips = played_clips.slice(-100)
	if delay <= 0.0:
		_start(clip, db, pitch)
	else:
		get_tree().create_timer(delay).timeout.connect(_start.bind(clip, db, pitch))


func _start(clip: AudioStream, db: float, pitch: float) -> void:
	for p in _voices:
		if not p.playing:
			p.stream = clip
			p.volume_db = db
			p.pitch_scale = pitch
			p.play()
			return

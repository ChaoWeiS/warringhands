extends Node
## Background music (assets/music/, made from art_source/music/ by
## tools/prep_music.sh): "menu" (Majestic Crescendo) on the start screen,
## "battle" (Antes de la Batalla) in a game. Tracks loop and crossfade.
## Plays on the "Music" bus, so the Settings volume applies.
##
## On the web the music isn't in the game's main download (so the game
## starts sooner): it's music.pck beside the page, fetched in the background
## once the game is running (the browser caches it, so later visits get it
## at once). A track asked for before it arrives starts as soon as it does.

const Settings := preload("res://scripts/settings.gd")
const BuildInfo := preload("res://scripts/build_info.gd")
const TRACKS := {
	"menu": "res://assets/music/majestic_crescendo.ogg",
	"battle": "res://assets/music/antes_de_la_batalla.ogg",
}
const PACK := "music.pck"
## Try the download again this long after a failure (e.g. offline).
const RETRY_S := 20.0
const FADE := 1.2
## The music sits under the voices and effects (at slider 100%).
const LEVEL_DB := -8.0

var current := ""
var _players: Array = []
var _active := 0
var _waiting := ""      # a track asked for before the music arrived
var _fetching := false
var _retry_at := -1.0


func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = Settings.music_bus()
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	if not has_music():
		_fetch_pack()


## Whether the music is here (always, except on the web before music.pck).
static func has_music() -> bool:
	return ResourceLoader.exists(TRACKS.menu)


## Gets music.pck (a copy kept from before if there is one, else from
## beside the web page) and adds it to the game's files.
func _fetch_pack() -> void:
	if _fetching:
		return
	var saved: String = "user://music_%s.pck" % BuildInfo.VERSION
	if FileAccess.file_exists(saved) and _mount(saved):
		return
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return
	var url: String = str(JavaScriptBridge.eval("new URL('%s?v=%s', window.location.href).href" % [PACK, BuildInfo.VERSION], true))
	_fetching = true
	var http := HTTPRequest.new()
	add_child(http)
	http.download_file = saved
	http.download_chunk_size = 1 << 20  # (default 64 KB a frame: slow for a few MB)
	# The browser already undoes the server's compression (GitHub Pages
	# gzips it); asking Godot to as well fails ("decompress failed").
	http.accept_gzip = false
	http.request_completed.connect(func(result: int, code: int, _h, _b):
		http.queue_free()
		_fetching = false
		if result == HTTPRequest.RESULT_SUCCESS and code == 200 and _mount(saved):
			_forget_old_packs(saved)
		else:
			print("Music: download failed (result %d, HTTP %d); trying again soon" % [result, code])
			DirAccess.remove_absolute(saved)
			_retry_at = Time.get_ticks_msec() / 1000.0 + RETRY_S)
	if http.request(url) != OK:
		_fetching = false
		_retry_at = Time.get_ticks_msec() / 1000.0 + RETRY_S


## Adds the pack (without replacing any of the game's own files) and starts
## the track that was waiting.
func _mount(file: String) -> bool:
	if not ProjectSettings.load_resource_pack(file, false) or not has_music():
		print("Music: couldn't load ", file)
		return false
	print("Music: ready (", file, ")")
	if _waiting != "":
		var track: String = _waiting
		_waiting = ""
		current = ""
		play(track)
	return true


## Copies kept for older versions are deleted.
func _forget_old_packs(keep: String) -> void:
	for f in DirAccess.get_files_at("user://"):
		var path: String = "user://" + f
		if f.begins_with("music_") and f.ends_with(".pck") and path != keep:
			DirAccess.remove_absolute(path)


func _process(_delta: float) -> void:
	if _retry_at > 0.0 and Time.get_ticks_msec() / 1000.0 >= _retry_at:
		_retry_at = -1.0
		_fetch_pack()


## Starts a track (fading out whatever was playing). Same track: nothing.
func play(track: String) -> void:
	if track == current or not TRACKS.has(track):
		return
	if not has_music():
		_waiting = track  # starts when the music arrives
		current = track
		return
	current = track
	var old: AudioStreamPlayer = _players[_active]
	_active = 1 - _active
	var new: AudioStreamPlayer = _players[_active]
	var stream: AudioStream = (load(TRACKS[track]) as AudioStream).duplicate()
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

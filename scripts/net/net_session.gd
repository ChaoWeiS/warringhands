extends Node
## One online match: talks to the relay server (server/index.js) over a
## WebSocket, gets a room code or joins one, then connects the simulation to
## the other player. Only orders and fingerprints travel; both devices run
## the same lockstep simulation (see sim.gd start_online()).
##
##   var net = NetSession.new(); add_child(net)
##   net.connect_to(url); net.create_room()   -> created(code), then started(seat)
##   net.connect_to(url); net.join_room(code) -> started(seat)
##   net.attach(sim)                          -> orders flow both ways

signal connected
signal created(code: String)
signal started(seat: int)
signal failed(message: String)
signal opponent_left
signal desynced

const Config := preload("res://scripts/net/net_config.gd")
static var _BASE64 := RegEx.create_from_string("^[A-Za-z0-9+/]+={0,2}$")

var seat := -1
## The map: the host's pick, sent to the guest right after the start.
var map := ""
var _awaiting_setup := false
var _early: Array = []  # their orders that came before attach()
var code := ""
var sim: Node = null
var _socket := WebSocketPeer.new()
var _open := false
var _waiting: Array = []  # messages to send once connected
var _was_closed := true


## Set by tests (a local server).
static var url_override := ""


## The server to use: ?server=... on the web page, else net_config.gd.
static func server_url() -> String:
	if url_override != "":
		return url_override
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var from_page: Variant = JavaScriptBridge.eval(
				"new URLSearchParams(window.location.search).get('server') || ''", true)
		if from_page is String and from_page != "":
			return from_page
	return Config.SERVER_URL


func connect_to(url: String) -> void:
	_socket = WebSocketPeer.new()
	_open = false
	_was_closed = false
	var err := _socket.connect_to_url(url)
	if err != OK:
		failed.emit("Can't reach the game server")


func create_room() -> void:
	_send({"t": "create"})


func join_room(room_code: String) -> void:
	_send({"t": "join", "code": room_code})


## Hooks the simulation up: our orders and fingerprints go out, theirs come in.
func attach(simulation: Node) -> void:
	sim = simulation
	sim.start_online(seat)
	sim.turn_ready.connect(func(at, cmds): _send({"t": "turn", "tick": at, "c": encode_commands(cmds)}))
	sim.hash_ready.connect(func(at, h): _send({"t": "hash", "tick": at, "h": str(h)}))
	sim.desynced.connect(func(_at): desynced.emit())
	# Orders that arrived while we were still loading (the map, the countdown).
	for msg in _early:
		_handle_game(msg)
	_early.clear()


func leave() -> void:
	_socket.close()
	_was_closed = true


func _process(_delta: float) -> void:
	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _open:
			_open = true
			connected.emit()
			for msg in _waiting:
				_socket.send_text(JSON.stringify(msg))
			_waiting.clear()
		while _socket.get_available_packet_count() > 0:
			_handle(_socket.get_packet().get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSED and not _was_closed:
		_was_closed = true
		_open = false
		if seat >= 0:
			opponent_left.emit()  # we lost the connection mid-game
		else:
			failed.emit("Can't reach the game server")


func _send(msg: Dictionary) -> void:
	if _open:
		_socket.send_text(JSON.stringify(msg))
	else:
		_waiting.append(msg)


func _handle(text: String) -> void:
	var msg: Variant = JSON.parse_string(text)
	if not msg is Dictionary or not msg.has("t"):
		return
	match msg.t:
		"created":
			code = str(msg.get("code", ""))
			created.emit(code)
		"start":
			seat = int(msg.get("seat", 0))
			code = str(msg.get("code", code))
			if seat == 0:
				# We made the game: tell the other player which map.
				_send({"t": "setup", "map": map})
				started.emit(seat)
			else:
				_awaiting_setup = true
		"setup":
			map = str(msg.get("map", ""))
			if _awaiting_setup:
				_awaiting_setup = false
				started.emit(seat)
		"error":
			failed.emit(str(msg.get("msg", "Something went wrong")))
		"left":
			opponent_left.emit()
		"turn", "hash":
			if sim == null:
				_early.append(msg)
			else:
				_handle_game(msg)


func _handle_game(msg: Dictionary) -> void:
	if msg.t == "turn":
		sim.receive_turn(int(msg.get("tick", -1)), int(msg.get("seat", -1)),
				decode_commands(str(msg.get("c", ""))))
	else:
		sim.receive_hash(int(msg.get("tick", -1)), int(msg.get("seat", -1)), str(msg.get("h", "0")).to_int())


## Orders as text for the wire: Godot's own binary format (whole numbers
## stay whole, unlike JSON), base64. No objects, ever.
static func encode_commands(commands: Array) -> String:
	return Marshalls.variant_to_base64(commands, false)


## Orders from the wire: only a list of plain dictionaries gets through.
static func decode_commands(text: String) -> Array:
	if text == "" or not _BASE64.search(text) or text.length() > 60000:
		return []
	var data: Variant = Marshalls.base64_to_variant(text, false)
	var out: Array = []
	if data is Array:
		for c in data:
			if c is Dictionary and c.get("type") is String:
				out.append(c)
	return out

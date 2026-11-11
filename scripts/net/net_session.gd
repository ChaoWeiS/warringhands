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
## Both players have loaded the game: start the countdown together.
signal both_ready
## The other player asks for a rematch; then both agreed (start it).
signal rematch_requested
signal rematch_agreed

const Config := preload("res://scripts/net/net_config.gd")
static var _BASE64 := RegEx.create_from_string("^[A-Za-z0-9+/]+={0,2}$")

var seat := -1
## The map: the host's pick, sent to the guest right after the start.
var map := ""
var _awaiting_setup := false
var _early: Array = []  # their orders that came before attach()
var _i_am_ready := false
## Which match on this connection (0, then 1 after a rematch...). Game
## messages carry it, so stray orders from the last match are dropped.
var game_no := 0
var _we_want_rematch := false
var _they_want_rematch := false
var _gone := false
## Online slack (ticks), set by the host from measured round trips.
var net_delay: int = 6
const PINGS := 5
var _ping_sent := 0
var _rtts: Array = []
var _they_are_ready := false
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
	sim.net_delay = net_delay
	sim.start_online(seat)
	var g: int = game_no
	sim.turn_ready.connect(func(at, cmds): _send({"t": "turn", "tick": at, "c": encode_commands(cmds), "g": g}))
	sim.hash_ready.connect(func(at, h): _send({"t": "hash", "tick": at, "h": str(h), "g": g}))
	sim.desynced.connect(func(_at): desynced.emit())
	# Orders that arrived while we were still loading (the map, the countdown).
	for msg in _early:
		_handle_game(msg)
	_early.clear()


## Our game is loaded (map built, sim attached). Once the other player says
## the same, both_ready fires on both devices (within the network delay).
##
## The host first times a few messages to the other player and back, picks
## the slack (net_delay) to fit, and sends it along with its "ready".
func mark_ready() -> void:
	if _i_am_ready or _ping_sent > 0:
		return
	if seat == 0:
		_ping()
	else:
		_i_am_ready = true
		_send({"t": "ready", "g": game_no})
		_check_ready()


func _ping() -> void:
	_ping_sent += 1
	_send({"t": "ping", "at": Time.get_ticks_msec()})


## Slack for orders: the one-way trip (half a round trip, the slowest of the
## middle ones), in ticks, plus 4 ticks to spare; between 6 and 24.
static func delay_for(round_trips: Array) -> int:
	var sorted: Array = round_trips.duplicate()
	sorted.sort()
	var typical: float = sorted[mini(sorted.size() - 1, sorted.size() * 3 / 4)]
	return clampi(ceili(typical * 0.5 / 50.0) + 4, 6, 24)


func _host_ready() -> void:
	net_delay = delay_for(_rtts)
	if sim != null:
		sim.set_net_delay(net_delay)
	_i_am_ready = true
	_send({"t": "ready", "delay": net_delay, "g": game_no})
	_check_ready()


func is_both_ready() -> bool:
	return _i_am_ready and _they_are_ready


func _check_ready() -> void:
	if _i_am_ready and _they_are_ready:
		both_ready.emit()


func request_rematch() -> void:
	if _we_want_rematch or _gone:
		return
	_we_want_rematch = true
	_send({"t": "rematch", "g": game_no})
	_check_rematch()


func _check_rematch() -> void:
	if _we_want_rematch and _they_want_rematch:
		rematch_agreed.emit()


## Ready for the next match on the same connection (same seats).
func reset_for_rematch() -> void:
	game_no += 1
	sim = null
	_early.clear()
	_i_am_ready = false
	_they_are_ready = false
	_ping_sent = 0
	_rtts.clear()
	_we_want_rematch = false
	_they_want_rematch = false
	# Drop the old game's hookups (it's about to go).
	for sig in ["both_ready", "rematch_requested", "rematch_agreed", "opponent_left", "desynced"]:
		for c in get_signal_connection_list(sig):
			disconnect(sig, c.callable)


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
			_gone = true
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
			_gone = true
			opponent_left.emit()
		"rematch":
			if int(msg.get("g", -1)) == game_no and not _they_want_rematch:
				_they_want_rematch = true
				rematch_requested.emit()
				_check_rematch()
		"ping":
			_send({"t": "pong", "at": msg.get("at", 0)})
		"pong":
			if seat == 0 and not _i_am_ready:
				_rtts.append(Time.get_ticks_msec() - int(msg.get("at", 0)))
				if _ping_sent < PINGS:
					_ping()
				else:
					_host_ready()
		"ready":
			if int(msg.get("g", 0)) != game_no:
				return
			if msg.has("delay"):
				net_delay = int(msg.delay)  # the host's measure
				if sim != null:
					sim.set_net_delay(net_delay)
			if not _they_are_ready:
				_they_are_ready = true
				_check_ready()
		"turn", "hash":
			if int(msg.get("g", 0)) != game_no:
				return  # from the last match
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

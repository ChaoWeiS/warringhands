extends Node
## The game simulation: where every unit is and what it's doing.
##
## Written for lockstep multiplayer from the start:
##   - It runs in fixed ticks (20 per second), not per frame.
##   - Positions are whole numbers (1 map unit = 100 sim units), so every
##     device computes exactly the same result.
##   - Players never move units directly. They send commands, which run a
##     couple of ticks later (online, that's the time to reach the other player).
## The visuals (units_view.gd) only read from here and smooth between ticks.
##
## Combat: units have HP and hit enemies they're touching once a second.
## Rock beats scissors, scissors beats paper, paper beats rock: a counter hit
## does double damage, being countered does half. Idle units spot enemies in
## sight, walk up and fight. Orders:
##   - move: go there first, fight after (but fight back if attacked);
##   - attack-move: go there, fighting any enemy met on the way, then carry on;
##   - attack: go after one particular enemy until it's dead.
##
## Economy: each side has an HQ and a stock of stone / wood / metal. Units
## gather from resource spots and carry it to their HQ (twice as fast for
## their own resource: rock-stone, paper-wood, scissors-metal). Factories
## (quarry, mill, forge) are built from resources and train rocks, papers and
## scissors. Buildings block movement and can be attacked. Lose your HQ and
## you lose the game.

signal ticked
## A unit was hit. strength: 1 = counter hit, 0 = even, -1 = countered.
signal unit_hit(target_id: int, attacker_id: int, damage: int, strength: int)
signal unit_died(id: int)
signal building_added(id: int)
signal building_destroyed(id: int)
signal game_over(winner: int)
## HP restored to a building this tick (all its repairers together).
signal building_repaired(building_id: int, amount: int)
## Online: our orders for a future tick, to send to the other player.
signal turn_ready(at_tick: int, commands: Array)
## Online: a fingerprint of the game at a tick, to compare with theirs.
signal hash_ready(at_tick: int, value: int)
## Online: the two games no longer match (should never happen).
signal desynced(at_tick: int)

const NavGrid := preload("res://scripts/sim/nav_grid.gd")
const AI := preload("res://scripts/sim/ai.gd")

## Sim units per map unit.
const SCALE := 100
const TICK_RATE := 20
const TICK_TIME := 1.0 / TICK_RATE
## Commands run this many ticks after they're given.
const COMMAND_DELAY := 2
## Online: orders are sent this many ticks ahead (300 ms) to hide the network
## delay. Every tick waits until both players' orders for it are in.
const NET_DELAY := 6
const HASH_EVERY := 20
## Gap between units when a group moves together (sim units).
const SPACING := 1000
## Each unit's round body (sim units). Bodies don't overlap: units closer
## than two radii are pushed apart every tick.
const RADIUS := 320
## Overlap passes per tick (more = firmer, a little slower).
const PUSH_PASSES := 8
## Idle units of the same side closer than this slowly drift apart until
## each has its own space (formations are spaced wider, so they don't move).
const COMFORT := 860
## How far an idle unit drifts per tick while fanning out.
const SPREAD_STEP := 14
## A walker that barely moves for this many ticks (e.g. pressed against
## enemies) stops where it is.
const STUCK_TICKS := 30

enum Kind { ROCK, PAPER, SCISSORS }

# --- Combat (placeholder numbers until balancing) ---
const MAX_HP := 100
## Damage per hit: even fight, counter (double), countered (half).
const DAMAGE := 10
const DAMAGE_COUNTER := 20
const DAMAGE_COUNTERED := 5
## Ticks between hits (20 = once a second).
const ATTACK_COOLDOWN := 20
## Centre-to-centre reach of a hit: bodies touching, plus a little.
const ATTACK_RANGE := RADIUS * 2 + 180
## How far an idle unit notices enemies.
const SIGHT := 3500
## Give up chasing a target further than this.
const LEASH := 5000
## How often a chasing unit re-plans its route to a moving target.
const REPATH_TICKS := 10

# --- Economy (placeholder numbers until balancing) ---
enum Res { STONE, WOOD, METAL }
const START_RESOURCES := 300
## Carried per trip, and ticks to gather it (own resource / other resource).
const CARRY := 20
const GATHER_TICKS_OWN := 40
const GATHER_TICKS_OTHER := 80
const NODE_AMOUNT := [2000, 2000, 1000]  # per spot: stone, wood, metal
## Wood in one forest tree. A cut-down tree is gone and its ground opens up.
const TREE_AMOUNT := 100
## When a spot runs out, gatherers move on to the nearest spot of the same
## resource within this distance of it.
const NEXT_SPOT_RANGE := 4000
## Route attempts before a gatherer gives up on a spot it can't reach (a tree
## deep in a forest) and picks the nearest other one.
const REACH_TRIES := 3
## Buildings: footprint radius (sim units; as big as the ground the
## building's picture covers, so nobody walks into the drawing), HP, cost, build time (ticks).
## Factories make the unit of the same kind as their resource.
## New buildings go within this distance (centre to centre, sim units) of
## one of the team's own buildings.
const BUILD_RANGE := 5000
## Repairs: your units within this distance of a damaged building's edge
## answer the call; each restores REPAIR_HP every REPAIR_TICKS (free).
const REPAIR_CALL := 4000
## Enemies this close to a team's building (beyond its edge) mean a fight is on.
const FIGHT_NEAR := 6000
const REPAIR_TICKS := 20
const REPAIR_HP := 10
const BUILDINGS := {
	# Extra HQs cost 150 of every resource (res -1 = all three), take 20 s,
	# and can go anywhere (no build range). The starting HQs come ready.
	"hq": {"radius": 1200, "hp": 2000, "cost": 150, "res": -1, "build": 400, "kind": -1},
	"quarry": {"radius": 900, "hp": 800, "cost": 150, "res": Res.STONE, "build": 200, "kind": Kind.ROCK},
	"mill": {"radius": 900, "hp": 800, "cost": 150, "res": Res.WOOD, "build": 200, "kind": Kind.PAPER},
	"forge": {"radius": 900, "hp": 800, "cost": 150, "res": Res.METAL, "build": 200, "kind": Kind.SCISSORS},
}
const FACTORY_FOR_KIND := ["quarry", "mill", "forge"]
const UNIT_COST := 60
## Selling a finished building gives back this share of its cost (percent).
## Cancelling one still going up gives it all back.
const SELL_REFUND := 50
const TRAIN_TICKS := 100
const QUEUE_MAX := 5
## Where each HQ stands (offset from the island centre, mirrored for team 1).
## Team 0's HQ on the first map (each map has its own: field.hq_offset).
const HQ_OFFSET := Vector2i(-200, -30)

## Movement per tick, by kind (placeholder numbers until balancing).
const SPEED := [72, 85, 78]
const UNITS_PER_KIND := 4

## The island, for where units can walk.
@export var field_path: NodePath

var field: Node = null
var tick: int = 0
## Off = units never fight (e.g. early tutorial steps, or testing movement).
var combat_enabled: bool = true
## Every unit: {id, team, kind, x, z, px, pz, tx, tz, moving, path, hp,
## target, ordered, next_attack, attack_tick, hurt_tick, repath, stuck}.
## (px, pz) = position at the previous tick, for smooth drawing.
## path = waypoints (Vector2i, sim units) still to walk; the last is (tx, tz).
## target = id of the enemy being fought (0 = none). ordered = on a plain
## move order (won't stop to fight unless attacked). attack_move + dest_x/z =
## heading to dest, fighting on the way. focus = target was picked by the
## player (chase it anywhere). chasing = current path leads to the target.
var units: Array = []
## Every building: {id, team, btype, x, z, radius, hp, max_hp, progress,
## queue (kinds), train}. progress < build time = still under construction.
var buildings: Array = []
## Resource spots: {id, res, x, z, radius, amount}.
var nodes: Array = []
var _nodes_by_id: Dictionary = {}
## Forest trees that have been cut down: map position -> true (and by node id).
var cut_trees: Dictionary = {}
var _tree_pos: Dictionary = {}  # node id -> map position (Vector2) of a tree
## Resources per team: [stone, wood, metal].
var resources: Array = [[START_RESOURCES, START_RESOURCES, START_RESOURCES],
		[START_RESOURCES, START_RESOURCES, START_RESOURCES]]
## -1 while playing; then the winning team.
var winner: int = -1

var _by_id: Dictionary = {}  # units and buildings
var _next_id: int = 1
var _pending: Dictionary = {}  # tick -> Array of commands
## Online play (lockstep): both devices run this same simulation and only
## swap orders. See start_online().
var online := false
var local_team := 0
var stalled := false             # waiting for the other player's orders
var net_delay: int = NET_DELAY    # online: ticks of slack for orders to arrive
var _outbox: Array = []          # our orders not yet sent
var _turns: Dictionary = {}      # tick -> {seat: Array of commands}
var _sent_until := -1            # last tick we've sent our orders for
var _hashes: Dictionary = {}     # tick -> {seat: fingerprint}
var _accum: float = 0.0
var _nav = null  # NavGrid, built on first use
var _ais: Dictionary = {}  # team -> computer opponent

## One walkable grid per island, shared by every sim using it (building it
## takes a moment).
static var _nav_cache: Dictionary = {}


func _ready() -> void:
	if field == null and not field_path.is_empty():
		field = get_node(field_path)
	if units.is_empty():
		_spawn_armies()
	if buildings.is_empty() and field != null:
		_spawn_bases()


func _process(delta: float) -> void:
	_accum += delta
	var steps := 0
	while _accum >= TICK_TIME and steps < 5:
		if online and not _online_ready():
			stalled = true
			_accum = minf(_accum, TICK_TIME)
			break
		stalled = false
		_accum -= TICK_TIME
		_step()
		steps += 1


## Starts lockstep play as `team` (0 or 1). From now on our orders are sent
## out (turn_ready) and ticks wait for the other player's (receive_turn).
func start_online(team: int) -> void:
	online = true
	local_team = team
	set_net_delay(net_delay)


## How many ticks ahead orders are scheduled online. Both players must use
## the same; the host measures the connection and tells the guest (see
## net_session.gd). Only before the game starts moving.
func set_net_delay(ticks: int) -> void:
	net_delay = ticks
	_sent_until = net_delay - 1  # the first ticks have no orders, for both


## The other player's orders for a tick. `seat` comes from the server, so
## the orders can only move that seat's own units.
func receive_turn(at_tick: int, seat: int, commands: Array) -> void:
	if seat == local_team or at_tick < tick:
		return
	var stamped: Array = []
	for c in commands:
		if c is Dictionary:
			var copy: Dictionary = c.duplicate(true)
			copy.by = seat
			stamped.append(copy)
	_turn_slot(at_tick)[seat] = stamped


## The other player's fingerprint of the game at a tick.
func receive_hash(at_tick: int, seat: int, value: int) -> void:
	_hash_slot(at_tick)[seat] = value
	_compare_hashes(at_tick)


## Online: may we run the current tick? (Sends our orders on the way.)
func _online_ready() -> bool:
	while _sent_until < tick + net_delay:
		_sent_until += 1
		var mine: Array = _outbox
		_outbox = []
		_turn_slot(_sent_until)[local_team] = mine
		turn_ready.emit(_sent_until, mine)
	if tick < net_delay:
		return true
	return _turns.has(tick) and _turns[tick].size() == 2


func _turn_slot(at_tick: int) -> Dictionary:
	if not _turns.has(at_tick):
		_turns[at_tick] = {}
	return _turns[at_tick]


func _hash_slot(at_tick: int) -> Dictionary:
	if not _hashes.has(at_tick):
		_hashes[at_tick] = {}
	return _hashes[at_tick]


func _compare_hashes(at_tick: int) -> void:
	var slot: Dictionary = _hashes.get(at_tick, {})
	if slot.size() == 2:
		if slot[0] != slot[1]:
			desynced.emit(at_tick)
		_hashes.erase(at_tick)


## A fingerprint of everything that matters in the game.
func state_hash() -> int:
	var parts: Array = [tick, resources]
	for u in units:
		parts.append([u.id, u.x, u.z, u.hp, u.target, u.job, u.orders.size()])
	for b in buildings:
		parts.append([b.id, b.hp, b.progress, b.queue.size()])
	for n in nodes:
		parts.append([n.id, n.amount])
	return hash(parts)


## How far we are between the last tick and the next (0-1), for smoothing.
func tick_fraction() -> float:
	return clampf(_accum / TICK_TIME, 0.0, 1.0)


## Runs `count` ticks immediately (used by tests).
func step_ticks(count: int) -> void:
	for i in count:
		_step()


func get_unit(id: int) -> Dictionary:
	return _by_id.get(id, {})


## Map position (x, z) of a unit at the latest tick.
func unit_ground(id: int) -> Vector2:
	var u: Dictionary = get_unit(id)
	return Vector2(u.x, u.z) / float(SCALE)


## Orders units to move to a ground point. Takes effect COMMAND_DELAY ticks
## from now. The point is turned into whole sim units right here, which is
## exactly what would be sent to the other player online.
## (Every unit order can be `queued`: added after what the units are
## already doing instead of replacing it. See _enqueue.)
func command_move(ids: Array, ground: Vector3, queued: bool = false) -> void:
	_queue(_maybe_queued({
		"type": "move",
		"ids": ids.duplicate(),
		"x": roundi(ground.x * SCALE),
		"z": roundi(ground.z * SCALE),
	}, queued))


static func _maybe_queued(command: Dictionary, queued: bool) -> Dictionary:
	if queued:
		command["queued"] = true
	return command


## Attack-move: go to a ground point, fighting any enemy met on the way.
func command_attack_move(ids: Array, ground: Vector3, queued: bool = false) -> void:
	_queue(_maybe_queued({
		"type": "attack_move",
		"ids": ids.duplicate(),
		"x": roundi(ground.x * SCALE),
		"z": roundi(ground.z * SCALE),
	}, queued))


## Attack one particular enemy, following it until it's dead.
func command_attack(ids: Array, target_id: int, queued: bool = false) -> void:
	_queue(_maybe_queued({"type": "attack", "ids": ids.duplicate(), "target": target_id}, queued))


func has_pending_commands() -> bool:
	return not _pending.is_empty()


## Does kind `a` beat kind `b`? (rock > scissors > paper > rock)
static func beats(a: int, b: int) -> bool:
	return (a - b + 3) % 3 == 1


## Damage a hit from kind `a` does to kind `b`.
static func damage_for(a: int, b: int) -> int:
	if a == b:
		return DAMAGE
	return DAMAGE_COUNTER if beats(a, b) else DAMAGE_COUNTERED


## Adds a unit at a ground point (map units). Returns its id.
func add_unit(team: int, kind: int, ground: Vector2) -> int:
	_add_unit(team, kind, Vector2i(roundi(ground.x * SCALE), roundi(ground.y * SCALE)))
	return _next_id - 1


## Removes every unit (used by tests and future scenarios).
func clear_units() -> void:
	for u in units:
		_by_id.erase(u.id)
	units.clear()


## Any unit or building, by id ({} if gone).
func get_entity(id: int) -> Dictionary:
	return _by_id.get(id, {})


func get_node_by_id(id: int) -> Dictionary:
	return _nodes_by_id.get(id, {})


## The walkable grid (null if there's no island, e.g. in some tests). Each
## game gets its own copy, so its buildings don't leak into other games.
func nav():
	if _nav == null and field != null:
		var key: int = field.get_instance_id()
		if not _nav_cache.has(key):
			field.build()
			_nav_cache[key] = NavGrid.new(field, int(field.map_size.x))
		_nav = _nav_cache[key].copy()
		for b in buildings:
			_nav.set_blocked(b.x, b.z, b.radius, true)
	return _nav


## Lets the computer play a team (it gives orders like a player would).
## The computer plays this side ("easy", "normal" or "hard").
func enable_ai(team: int, difficulty: String = "normal") -> void:
	var old = _ais.get(team, null)
	if old != null and old.bonus() > 0:
		for res in 3:
			resources[team][res] -= old.bonus()
	_ais[team] = AI.new(team, difficulty)
	for res in 3:
		resources[team][res] += _ais[team].bonus()


func ai_of(team: int):
	return _ais.get(team, null)


func hq_of(team: int) -> Dictionary:
	for b in buildings:
		if b.team == team and b.btype == "hq":
			return b
	return {}


func can_afford(team: int, res: int, amount: int) -> bool:
	if res < 0:  # all three
		return resources[team].all(func(have): return have >= amount)
	return resources[team][res] >= amount


## What a building costs: [stone, wood, metal].
static func cost_of(btype: String) -> Array:
	var spec: Dictionary = BUILDINGS[btype]
	var cost := [0, 0, 0]
	for res in 3:
		if spec.res < 0 or spec.res == res:
			cost[res] = spec.cost
	return cost


## Can `team` put a building of this type here (ground point, map units)?
## Needs open ground (no water, trees, other buildings) and no units in the way.
## Can a building go here? Open ground, nobody standing there, and (for a
## team) within BUILD_RANGE of one of its own buildings.
func can_place(btype: String, ground: Vector2, team: int = -1) -> bool:
	var x: int = roundi(ground.x * SCALE)
	var z: int = roundi(ground.y * SCALE)
	if team >= 0 and btype != "hq" and not in_build_range(team, x, z):
		return false
	var radius: int = BUILDINGS[btype].radius
	# All on one flat level (the grassland or a plateau top): not on a
	# ramp or a cliff edge, and not hanging over one.
	if field != null:
		var c := Vector2(x, z) / float(SCALE)
		var r: float = float(radius) / SCALE
		var level: float = field.height_at(c)
		for k in 9:
			var p: Vector2 = c if k == 8 else c + Vector2.from_angle(k * TAU / 8.0) * r
			if field.is_slope_or_edge(p) or absf(field.height_at(p) - level) > 0.01:
				return false
	var grid = nav()
	if grid != null and not grid.circle_is_open(x, z, radius + RADIUS):
		return false
	for u in units:
		var dx: int = u.x - x
		var dz: int = u.z - z
		if dx * dx + dz * dz < (radius + RADIUS) * (radius + RADIUS):
			return false
	return true


## Within BUILD_RANGE of one of the team's buildings (sim units)?
func in_build_range(team: int, x: int, z: int) -> bool:
	for b in buildings:
		if b.team != team:
			continue
		var dx: int = b.x - x
		var dz: int = b.z - z
		if dx * dx + dz * dz <= BUILD_RANGE * BUILD_RANGE:
			return true
	return false


## Build a factory (or HQ) at a ground point. Paid when it happens.
func command_build(team: int, btype: String, ground: Vector2) -> void:
	_queue({"type": "build", "team": team, "btype": btype,
			"x": roundi(ground.x * SCALE), "z": roundi(ground.y * SCALE)})


## Queue a unit at a factory. Paid when queued.
func command_train(team: int, building_id: int) -> void:
	_queue({"type": "train", "team": team, "building": building_id})


## Send units to gather from a resource spot.
func command_gather(ids: Array, node_id: int, queued: bool = false) -> void:
	_queue(_maybe_queued({"type": "gather", "ids": ids.duplicate(), "node": node_id}, queued))


## Each unit gathers the resource it's fastest at (rock: stone, paper: wood,
## scissors: metal), from the spot of it nearest its HQ.
func command_harvest(ids: Array, queued: bool = false) -> void:
	_queue(_maybe_queued({"type": "harvest", "ids": ids.duplicate()}, queued))


## Gives up: the other side wins.
func command_surrender(team: int) -> void:
	_queue({"type": "surrender", "team": team})


## Units stop where they are and stay: they fight whatever comes within
## reach, but don't chase or go back to work, until they get a new order.
func command_hold(ids: Array) -> void:
	_queue({"type": "hold", "ids": ids.duplicate()})


## Calls the team's units near a damaged building to repair it.
func command_repair(team: int, building_id: int) -> void:
	_queue({"type": "repair", "team": team, "building": building_id})


## Cancels buildings still going up (all the cost back) or sells finished
## ones (SELL_REFUND% back); units queued in them are refunded too. A team's
## last HQ can't go.
func command_sell(team: int, building_ids: Array) -> void:
	_queue({"type": "sell", "team": team, "ids_b": building_ids.duplicate()})


## What selling (or cancelling) this building gives back: [stone, wood, metal].
func refund_of(b: Dictionary) -> Array:
	var spec: Dictionary = BUILDINGS[b.btype]
	var cost: Array = cost_of(b.btype)
	var out := [0, 0, 0]
	var finished: bool = b.progress >= spec.build
	for res in 3:
		out[res] = cost[res] if not finished else cost[res] * SELL_REFUND / 100
	if spec.res >= 0:
		out[spec.res] += UNIT_COST * b.queue.size()
	return out


## Can this building be sold / cancelled? (Not a team's only HQ.)
func can_sell(b: Dictionary) -> bool:
	if b.is_empty() or not b.has("btype"):
		return false
	if b.btype != "hq":
		return true
	for other in buildings:
		if other.team == b.team and other.btype == "hq" and other.id != b.id:
			return true
	return false


# --- Simulation ----------------------------------------------------------------

func _queue(command: Dictionary) -> void:
	if online:
		command.by = local_team
		_outbox.append(command)
		return
	var at: int = tick + COMMAND_DELAY
	if not _pending.has(at):
		_pending[at] = []
	_pending[at].append(command)


func _step() -> void:
	for command in _pending.get(tick, []):
		_apply(command)
	_pending.erase(tick)
	if online:
		# Both players' orders, always seat 0's first.
		var turn: Dictionary = _turns.get(tick, {})
		for seat in [0, 1]:
			for command in turn.get(seat, []):
				_apply(command)
		_turns.erase(tick)
	var ai_teams: Array = _ais.keys()
	ai_teams.sort()
	for team in ai_teams:
		if tick >= AI.START and tick % _ais[team].interval == team:
			_ais[team].think(self)
	for u in units:
		u.px = u.x
		u.pz = u.z
	_construct_and_train()
	_advance_queues()
	_work()
	_fight()
	for u in units:
		if u.moving:
			_move(u)
	for pass_index in PUSH_PASSES:
		_separate()
		_push_out_of_buildings()
	_spread_idle()
	_push_out_of_buildings()  # buildings always win over fanning out
	_check_stuck()
	tick += 1
	if online and tick % HASH_EVERY == 0:
		var h: int = state_hash()
		_hash_slot(tick)[local_team] = h
		hash_ready.emit(tick, h)
		_compare_hashes(tick)
	ticked.emit()


func _apply(command: Dictionary) -> void:
	if command.has("by"):
		# Online: a player may only give orders to their own side.
		if command.has("team") and command.team != command.by:
			return
		if command.has("ids"):
			var own: Array = []
			for id in command.ids:
				var u: Dictionary = _by_id.get(id, {})
				if not u.is_empty() and not u.has("btype") and u.team == command.by:
					own.append(id)
			command.ids = own
	if command.get("queued", false) and QUEUEABLE.has(command.type):
		_enqueue(command)
		return
	if command.has("ids"):
		for id in command.ids:
			var held: Dictionary = _by_id.get(id, {})
			if not held.is_empty() and not held.has("btype"):
				held.orders.clear()  # a plain order (or Hold) replaces the plan
				if command.type != "hold":
					held.hold = false  # a new order lets a held unit go
	match command.type:
		"hold":
			_apply_hold(command)
		"surrender":
			if winner < 0:
				winner = 1 - int(command.team)
				game_over.emit(winner)
		"move", "attack_move":
			_apply_move(command)
		"attack":
			_apply_attack(command)
		"build":
			_apply_build(command)
		"train":
			_apply_train(command)
		"gather":
			_apply_gather(command)
		"harvest":
			_apply_harvest(command)
		"repair":
			_apply_repair(command)
		"sell":
			_apply_sell(command)


## Spreads the group into a square formation around the target point.
## Orders that can be queued.
const QUEUEABLE := ["move", "attack_move", "attack", "gather", "harvest"]


## A queued order: each unit gets its own step (a move's formation spot
## worked out now), done at once if it's idle with nothing queued,
## otherwise after what it's already got.
func _enqueue(command: Dictionary) -> void:
	var ids: Array = command.ids.duplicate()
	ids.sort()
	var group: Array = []
	for id in ids:
		var u: Dictionary = _by_id.get(id, {})
		if not u.is_empty() and not u.has("btype"):
			group.append(u)
	var spots: Array = []
	if command.type == "move" or command.type == "attack_move":
		spots = _formation(group.size(), command.x, command.z)
	for i in group.size():
		var u: Dictionary = group[i]
		var step := {"type": command.type}
		match command.type:
			"move", "attack_move":
				step.x = spots[i].x
				step.z = spots[i].y
			"attack":
				step.target = command.target
			"gather":
				step.node = command.node
		u.hold = false
		if u.orders.is_empty() and _is_idle(u):
			_run_step(u, step)
		else:
			u.orders.append(step)


## Spots for a group of n in a square formation around (x, z).
func _formation(n: int, x: int, z: int) -> Array:
	var cols := 1
	while cols * cols < n:
		cols += 1
	var rows: int = (n + cols - 1) / cols
	var out: Array = []
	for i in n:
		var c: int = i % cols
		var r: int = i / cols
		out.append(Vector2i(x + (c * 2 - (cols - 1)) * SPACING / 2, z + (r * 2 - (rows - 1)) * SPACING / 2))
	return out


## Nothing on: not walking, not fighting, no job.
func _is_idle(u: Dictionary) -> bool:
	return not u.moving and u.target == 0 and u.job == "" and not u.attack_move


func _run_step(u: Dictionary, step: Dictionary) -> void:
	var command: Dictionary = step.duplicate()
	command.ids = [u.id]
	match step.type:
		"move", "attack_move":
			_apply_move(command)
		"attack":
			_apply_attack(command)
		"gather":
			_apply_gather(command)
		"harvest":
			_apply_harvest(command)


## Units that have finished what they were doing start their next step
## (a step whose target is gone is skipped).
func _advance_queues() -> void:
	for u in units:
		while not u.orders.is_empty() and _is_idle(u):
			var step: Dictionary = u.orders.pop_front()
			if step.type == "attack" and not _by_id.has(step.target):
				continue
			if step.type == "gather" and get_node_by_id(step.node).is_empty():
				continue
			_run_step(u, step)


func _apply_move(command: Dictionary) -> void:
	var ids: Array = command.ids.duplicate()
	ids.sort()  # same order on every device
	var group: Array = []
	for id in ids:
		if _by_id.has(id):
			group.append(_by_id[id])
	var n: int = group.size()
	if n == 0:
		return
	var cols := 1
	while cols * cols < n:
		cols += 1
	var rows: int = (n + cols - 1) / cols
	for i in n:
		var u: Dictionary = group[i]
		var c: int = i % cols
		var r: int = i / cols
		var tx: int = command.x + (c * 2 - (cols - 1)) * SPACING / 2
		var tz: int = command.z + (r * 2 - (rows - 1)) * SPACING / 2
		u.target = 0  # the player's order comes first
		u.job = ""
		u.focus = false
		u.chasing = false
		u.ordered = command.type == "move"
		u.attack_move = command.type == "attack_move"
		u.dest_x = tx
		u.dest_z = tz
		_route(u, tx, tz)


func _apply_hold(command: Dictionary) -> void:
	for id in command.ids:
		var u: Dictionary = _by_id.get(id, {})
		if u.is_empty() or u.has("btype"):
			continue
		_clear_orders(u)
		u.job = ""
		u.phase = ""
		u.hold = true
		u.dest_x = u.x
		u.dest_z = u.z


func _apply_attack(command: Dictionary) -> void:
	if not _by_id.has(command.target):
		return
	var ids: Array = command.ids.duplicate()
	ids.sort()
	for id in ids:
		var u: Dictionary = _by_id.get(id, {})
		if u.is_empty() or u.team == _by_id[command.target].team:
			continue
		u.ordered = false
		u.attack_move = false
		u.job = ""
		u.focus = true
		u.chasing = false
		u.target = command.target


## Plans a unit's way to (tx, tz) around lakes, forests and the like. If the
## spot itself is blocked (e.g. in a lake), it goes to the nearest open spot.
func _route(u: Dictionary, tx: int, tz: int) -> void:
	var grid = nav()
	var path: Array = [Vector2i(tx, tz)] if grid == null else grid.find_route(u.x, u.z, tx, tz)
	u.path = path
	u.moving = not path.is_empty()
	if u.moving:
		u.tx = path[path.size() - 1].x
		u.tz = path[path.size() - 1].y


# --- Combat ----------------------------------------------------------------------

## Every unit decides what to do about enemies, then all hits land together
## (so neither side gets a free first hit just for having a lower id).
func _fight() -> void:
	var hits: Array = []  # [attacker, target, damage]
	for u in units:
		if u.ordered:
			if u.moving:
				continue  # following the player's order first
			u.ordered = false
		if not combat_enabled:
			continue
		if u.job != "" and u.target == 0:
			continue  # busy gathering (still fights back if attacked)
		var target: Dictionary = _by_id.get(u.target, {})
		if not target.is_empty() and not u.focus and _dist2(u, target) > LEASH * LEASH:
			target = {}
		if target.is_empty():
			u.focus = false
			target = _nearest_enemy(u, SIGHT)
		if target.is_empty():
			u.target = 0
			if u.chasing:
				# The fight is over: carry on to an attack-move's destination,
				# otherwise stop here.
				u.chasing = false
				if u.attack_move:
					_route(u, u.dest_x, u.dest_z)
				else:
					u.moving = false
					u.path.clear()
			elif u.attack_move and not u.moving:
				u.attack_move = false  # arrived
			continue
		if u.hold and not _in_reach(u, target):
			u.target = 0  # holding: only fight what's in reach, never chase
			continue
		u.target = target.id
		if _in_reach(u, target):
			# In reach: stand and fight.
			u.moving = false
			u.path.clear()
			u.chasing = true
			if tick >= u.next_attack:
				var dmg: int = DAMAGE if target.has("btype") else damage_for(u.kind, target.kind)
				hits.append([u, target, dmg])
				u.next_attack = tick + ATTACK_COOLDOWN
				u.attack_tick = tick
		elif not u.moving or not u.chasing or tick >= u.repath:
			# Chase, re-planning now and then as the target moves.
			_route(u, target.x, target.z)
			u.chasing = true
			u.repath = tick + REPATH_TICKS
	for hit in hits:
		var attacker: Dictionary = hit[0]
		var victim: Dictionary = hit[1]
		victim.hp -= hit[2]
		victim.hurt_tick = tick
		if victim.has("btype"):
			unit_hit.emit(victim.id, attacker.id, hit[2], 0)
			continue
		if victim.ordered:
			# Attacked while on a plain move order: stop and fight back.
			victim.ordered = false
			victim.target = attacker.id
			victim.moving = false
			victim.path.clear()
		if victim.job != "":
			# Attacked while gathering: drop it and fight back.
			victim.job = ""
			victim.target = attacker.id
			victim.moving = false
			victim.path.clear()
		var strength: int = 0
		if attacker.kind != victim.kind:
			strength = 1 if beats(attacker.kind, victim.kind) else -1
		unit_hit.emit(victim.id, attacker.id, hit[2], strength)
	var dead: Array = []
	for u in units:
		if u.hp <= 0:
			dead.append(u)
	for u in dead:
		units.erase(u)
		_by_id.erase(u.id)
		unit_died.emit(u.id)
	var fallen: Array = buildings.filter(func(b): return b.hp <= 0)
	for b in fallen:
		_remove_building(b)


## Closest enemy unit within `reach`, or failing that the closest enemy
## building (measured to its edge). Ties go to the lower id. {} if none.
func _nearest_enemy(u: Dictionary, reach: int) -> Dictionary:
	var best: Dictionary = {}
	var best_d2: int = reach * reach + 1
	for other in units:
		if other.team == u.team:
			continue
		var d2: int = _dist2(u, other)
		if d2 < best_d2:
			best = other
			best_d2 = d2
	if not best.is_empty():
		return best
	for b in buildings:
		if b.team == u.team:
			continue
		var edge: int = maxi(0, _isqrt(_dist2(u, b)) - b.radius)
		if edge * edge < best_d2:
			best = b
			best_d2 = edge * edge
	return best


## Close enough to hit? (Buildings are hit from their edge.)
func _in_reach(u: Dictionary, target: Dictionary) -> bool:
	var reach: int = ATTACK_RANGE
	if target.has("btype"):
		reach = target.radius + RADIUS + 180
	return _dist2(u, target) <= reach * reach


# --- Economy ---------------------------------------------------------------------

func _apply_build(command: Dictionary) -> void:
	var spec: Dictionary = BUILDINGS[command.btype]
	var ground := Vector2(command.x, command.z) / float(SCALE)
	if winner >= 0 or not can_afford(command.team, spec.res, spec.cost) or not can_place(command.btype, ground, command.team):
		return
	var cost: Array = cost_of(command.btype)
	for res in 3:
		resources[command.team][res] -= cost[res]
	_add_building(command.team, command.btype, Vector2i(command.x, command.z), false)


func _apply_train(command: Dictionary) -> void:
	var b: Dictionary = _by_id.get(command.building, {})
	if b.is_empty() or not b.has("btype") or b.team != command.team:
		return
	var spec: Dictionary = BUILDINGS[b.btype]
	if spec.kind < 0 or b.progress < spec.build or b.queue.size() >= QUEUE_MAX \
			or not can_afford(b.team, spec.res, UNIT_COST):
		return
	resources[b.team][spec.res] -= UNIT_COST
	b.queue.append(spec.kind)


func _apply_sell(command: Dictionary) -> void:
	if winner >= 0:
		return
	for id in command.ids_b:
		var b: Dictionary = _by_id.get(int(id), {})
		if b.is_empty() or not b.has("btype") or b.team != command.team or not can_sell(b):
			continue
		var back: Array = refund_of(b)
		for res in 3:
			resources[b.team][res] += back[res]
		_remove_building(b)


func _apply_gather(command: Dictionary) -> void:
	var node: Dictionary = get_node_by_id(command.node)
	if node.is_empty():
		return
	var ids: Array = command.ids.duplicate()
	ids.sort()
	for id in ids:
		var u: Dictionary = _by_id.get(id, {})
		if u.is_empty() or u.has("btype"):
			continue
		_assign_gather(u, node)


func _apply_harvest(command: Dictionary) -> void:
	var ids: Array = command.ids.duplicate()
	ids.sort()
	for id in ids:
		var u: Dictionary = _by_id.get(id, {})
		if u.is_empty() or u.has("btype"):
			continue
		var hq: Dictionary = hq_of(u.team)
		_gather_own(u, hq if not hq.is_empty() else u)


## Gather the unit's own resource from the spot of it nearest `from`.
## False if there's none left.
func _gather_own(u: Dictionary, from: Dictionary) -> bool:
	var best: Dictionary = {}
	for n in nodes:
		if n.res == u.kind and (best.is_empty() or _dist2(n, from) < _dist2(best, from)):
			best = n
	if best.is_empty():
		return false
	_assign_gather(u, best)
	return true


## Is the team in a fight? One of its units is fighting, or an enemy is
## within FIGHT_NEAR of one of its buildings.
func in_fight(team: int) -> bool:
	for u in units:
		if u.team == team and u.target != 0:
			return true
	for e in units:
		if e.team == team:
			continue
		for b in buildings:
			if b.team == team and _dist2(e, b) <= (b.radius + FIGHT_NEAR) * (b.radius + FIGHT_NEAR):
				return true
	return false


func _assign_gather(u: Dictionary, node: Dictionary) -> void:
	_clear_orders(u)
	u.job = "gather"
	u.node = node.id
	u.work_x = node.x
	u.work_z = node.z
	u.work_res = node.res
	u.tries = 0
	u.phase = "to_node" if u.carry == 0 else "to_drop"


func _clear_orders(u: Dictionary) -> void:
	u.orders.clear()
	u.hold = false
	u.ordered = false
	u.attack_move = false
	u.focus = false
	u.target = 0
	u.chasing = false
	u.moving = false
	u.path.clear()


func _apply_repair(command: Dictionary) -> void:
	var b: Dictionary = _by_id.get(command.building, {})
	if b.is_empty() or not b.has("btype") or b.team != command.team or b.hp >= b.max_hp:
		return
	var reach: int = b.radius + REPAIR_CALL
	for u in units:
		if u.team != b.team or u.target != 0:
			continue  # busy fighting
		if _dist2(u, b) > reach * reach:
			continue
		_clear_orders(u)
		u.job = "repair"
		u.node = b.id
		u.phase = "to_site"
		u.timer = REPAIR_TICKS


## Construction progress and factory production.
func _construct_and_train() -> void:
	for b in buildings:
		var spec: Dictionary = BUILDINGS[b.btype]
		if b.progress < spec.build:
			b.progress += 1
			continue
		if b.queue.is_empty():
			b.train = 0
			continue
		b.train += 1
		if b.train >= TRAIN_TICKS:
			b.train = 0
			var kind: int = b.queue.pop_front()
			_spawn_from(b, kind)


## A newly trained unit steps out of its factory towards the island centre.
func _spawn_from(b: Dictionary, kind: int) -> void:
	var centre := Vector2i(410, 410) * SCALE
	var dx: int = centre.x - b.x
	var dz: int = centre.y - b.z
	var d: int = maxi(1, _isqrt(dx * dx + dz * dz))
	var out: int = b.radius + RADIUS + 150
	var at := Vector2i(b.x + dx * out / d, b.z + dz * out / d)
	var grid = nav()
	# On a plateau: step out onto the same level, not off the cliff.
	if field != null and grid != null:
		var level: float = field.height_at(Vector2(b.x, b.z) / float(SCALE))
		var facing: float = atan2(float(dz), float(dx))
		for k in 16:
			var turn: float = facing + (k + 1) / 2 * (TAU / 16.0) * (1 if k % 2 == 0 else -1)
			var p := Vector2i(b.x + roundi(cos(turn) * out), b.z + roundi(sin(turn) * out))
			if grid.is_walkable_cell(grid.cell_of(p.x, p.y)) \
					and absf(field.height_at(Vector2(p) / float(SCALE)) - level) < 0.01:
				at = p
				break
	if grid != null:
		var cell: Vector2i = grid.nearest_walkable(grid.cell_of(at.x, at.y))
		if cell.x >= 0 and not grid.is_walkable_cell(grid.cell_of(at.x, at.y)):
			at = grid.cell_centre(cell)
	_add_unit(b.team, kind, at)
	var u: Dictionary = units[units.size() - 1]
	# A player's new unit goes straight to work unless there's a fight on.
	# (The computer opponent decides for its own units.)
	if ai_of(b.team) == null and not in_fight(b.team) and _gather_own(u, b):
		return
	var rally := Vector2i(b.x + dx * (out + 1200) / d, b.z + dz * (out + 1200) / d)
	_route(u, rally.x, rally.y)


## Gatherers: walk to the spot, gather, carry it home, repeat.
func _work() -> void:
	var repaired := {}  # building id -> HP restored this tick
	for u in units:
		if u.job == "repair":
			_repair(u, repaired)
			continue
		if u.job != "gather":
			continue
		var node: Dictionary = get_node_by_id(u.node)
		match u.phase:
			"to_node":
				if node.is_empty() or u.tries >= REACH_TRIES:
					# Gone, or out of reach: the nearest other spot of its kind.
					node = _next_spot(u, u.work_res, u.node)
					if node.is_empty():
						u.job = ""
						continue
					u.node = node.id
					u.work_x = node.x
					u.work_z = node.z
					u.tries = 0
				if _near_edge(u, node.x, node.z, node.radius):
					u.phase = "gathering"
					u.timer = GATHER_TICKS_OWN if u.kind == node.res else GATHER_TICKS_OTHER
					u.moving = false
					u.path.clear()
					u.tries = 0
				elif not u.moving:
					u.tries += 1
					_route_to_edge(u, node.x, node.z, node.radius)
			"gathering":
				if node.is_empty():
					u.phase = "to_drop" if u.carry > 0 else "to_node"
					continue
				u.timer -= 1
				if u.timer <= 0:
					var take: int = mini(CARRY, node.amount)
					node.amount -= take
					u.carry = take
					u.carry_res = node.res
					u.phase = "to_drop"
					if node.amount <= 0:
						_remove_node(node)
			"to_drop":
				var drop: Dictionary = _drop_for(u)
				if drop.is_empty():
					u.job = ""
					continue
				if _near_edge(u, drop.x, drop.z, drop.radius):
					resources[u.team][u.carry_res] += u.carry
					u.carry = 0
					u.phase = "to_node"
					u.moving = false
					u.path.clear()
				elif not u.moving:
					_route_to_edge(u, drop.x, drop.z, drop.radius)
	for id in repaired:
		building_repaired.emit(id, repaired[id])


## Where a gatherer takes its load: the nearest finished building of its
## team that takes it, the HQ (anything) or the matching factory (stone to a
## quarry, wood to a mill, metal to a forge). {} if none.
func _drop_for(u: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_walk := 0
	for b in buildings:
		if b.team != u.team:
			continue
		var spec: Dictionary = BUILDINGS[b.btype]
		if b.progress < spec.build or (b.btype != "hq" and spec.res != u.carry_res):
			continue
		var walk: int = _isqrt(_dist2(b, u)) - b.radius  # to its edge
		if best.is_empty() or walk < best_walk:
			best = b
			best_walk = walk
	return best


## The spot of resource `res` nearest to where the unit was working, within
## NEXT_SPOT_RANGE, other than `skip`; nearest to the unit breaks ties. {} if none.
func _next_spot(u: Dictionary, res: int, skip: int) -> Dictionary:
	var best: Dictionary = {}
	var best_d: int = NEXT_SPOT_RANGE * NEXT_SPOT_RANGE
	for n in nodes:
		if n.res != res or n.id == skip:
			continue
		var dx: int = n.x - u.work_x
		var dz: int = n.z - u.work_z
		var d: int = dx * dx + dz * dz
		if d < best_d or (d == best_d and not best.is_empty() and _dist2(n, u) < _dist2(best, u)):
			best = n
			best_d = d
	return best


## A spot ran out. A forest tree is cut down: its ground opens up.
func _remove_node(node: Dictionary) -> void:
	nodes.erase(node)
	_nodes_by_id.erase(node.id)
	if not _tree_pos.has(node.id):
		return
	var pos: Vector2 = _tree_pos[node.id]
	cut_trees[pos] = true
	var grid = nav()
	if grid == null:
		return
	var reach: int = roundi((field.TREE_RADIUS + field.UNIT_CLEARANCE) * SCALE)
	for cell in grid.cells_in_circle(node.x, node.z, reach):
		if grid.is_walkable_cell(cell):
			continue
		var centre: Vector2i = grid.cell_centre(cell)
		if field.is_walkable(Vector2(centre) / float(SCALE), cut_trees):
			grid.open_terrain(cell)


## A repairer: walk to the building, then patch it up until it's whole.
func _repair(u: Dictionary, repaired: Dictionary) -> void:
	var b: Dictionary = _by_id.get(u.node, {})
	if b.is_empty() or not b.has("btype") or b.hp >= b.max_hp:
		u.job = ""
		return
	if not _near_edge(u, b.x, b.z, b.radius):
		if not u.moving:
			_route_to_edge(u, b.x, b.z, b.radius)
		return
	u.moving = false
	u.path.clear()
	u.phase = "repairing"
	u.timer -= 1
	if u.timer <= 0:
		u.timer = REPAIR_TICKS
		var amount: int = mini(REPAIR_HP, b.max_hp - b.hp)
		b.hp += amount
		repaired[b.id] = repaired.get(b.id, 0) + amount


## Close enough to work at something round of `radius`?
func _near_edge(u: Dictionary, x: int, z: int, radius: int) -> bool:
	var reach: int = radius + RADIUS * 2 + 400
	var dx: int = u.x - x
	var dz: int = u.z - z
	return dx * dx + dz * dz <= reach * reach


## Walk to the edge of something round, on the side facing the unit (so a
## group spreads around it instead of queueing for one spot).
func _route_to_edge(u: Dictionary, x: int, z: int, radius: int) -> void:
	var dx: int = u.x - x
	var dz: int = u.z - z
	var d: int = _isqrt(dx * dx + dz * dz)
	if d == 0:
		dx = 1
		d = 1
	var out: int = radius + RADIUS + 100
	_route(u, x + dx * out / d, z + dz * out / d)


## Units can't stand inside buildings: push them out to the edge.
func _push_out_of_buildings() -> void:
	for b in buildings:
		var clear: int = b.radius + RADIUS
		for u in units:
			var dx: int = u.x - b.x
			var dz: int = u.z - b.z
			if absi(dx) >= clear or absi(dz) >= clear:
				continue
			var d2: int = dx * dx + dz * dz
			if d2 >= clear * clear:
				continue
			var d: int = _isqrt(d2)
			if d == 0:
				dx = 1
				d = 1
			var push: int = clear - d
			if not _nudge(u, dx * push / d, dz * push / d):
				u.x = b.x + dx * clear / d
				u.z = b.z + dz * clear / d


func _remove_building(b: Dictionary) -> void:
	buildings.erase(b)
	_by_id.erase(b.id)
	var grid = nav()
	if grid != null:
		grid.set_blocked(b.x, b.z, b.radius, false)
	building_destroyed.emit(b.id)
	# Lose your last HQ (finished or not), lose the game.
	if b.btype == "hq" and winner < 0 and hq_of(b.team).is_empty():
		winner = 1 - b.team
		game_over.emit(winner)


func _add_building(team: int, btype: String, at: Vector2i, finished: bool) -> Dictionary:
	var spec: Dictionary = BUILDINGS[btype]
	var b := {
		"id": _next_id, "team": team, "btype": btype, "x": at.x, "z": at.y,
		"radius": spec.radius, "hp": spec.hp, "max_hp": spec.hp,
		"progress": spec.build if finished else 0, "queue": [], "train": 0,
	}
	_next_id += 1
	buildings.append(b)
	_by_id[b.id] = b
	var grid = nav()
	if grid != null:
		grid.set_blocked(b.x, b.z, b.radius, true)
	building_added.emit(b.id)
	return b


## HQs (mirrored) and the resource spots.
func _spawn_bases() -> void:
	var centre := Vector2i(410, 410) * SCALE
	field.build()
	var hq_at: Vector2i = field.hq_offset * SCALE
	_add_building(0, "hq", centre + hq_at, true)
	_add_building(1, "hq", centre - hq_at, true)
	for spot in field.resource_spots():
		var tree: bool = spot.get("tree", false)
		var n := {
			"id": _next_id, "res": spot.res,
			"x": roundi(spot.pos.x * SCALE), "z": roundi(spot.pos.y * SCALE),
			"radius": roundi(spot.radius * SCALE),
			"amount": TREE_AMOUNT if tree else NODE_AMOUNT[spot.res], "tree": tree,
		}
		nodes.append(n)
		_nodes_by_id[n.id] = n
		if tree:
			_tree_pos[n.id] = spot.pos
		_next_id += 1


static func _dist2(a: Dictionary, b: Dictionary) -> int:
	var dx: int = a.x - b.x
	var dz: int = a.z - b.z
	return dx * dx + dz * dz


# --- Movement ----------------------------------------------------------------------

## Walks towards the next waypoint; on reaching it, moves on to the next.
func _move(u: Dictionary) -> void:
	var path: Array = u.path
	if path.is_empty():
		u.moving = false
		return
	var next: Vector2i = path[0]
	var dx: int = next.x - u.x
	var dz: int = next.y - u.z
	var dist: int = _isqrt(dx * dx + dz * dz)
	var speed: int = SPEED[u.kind]
	if dist <= speed:
		u.x = next.x
		u.z = next.y
		path.pop_front()
		if path.is_empty():
			u.moving = false
	else:
		u.x += dx * speed / dist
		u.z += dz * speed / dist


## Pushes overlapping units apart, never into blocked ground:
##   - two walkers, or two idle units: half each;
##   - a walker meets an idle unit of its own side: the idle one steps aside
##     (sideways out of the walker's path);
##   - a walker meets an idle enemy: the enemy holds its ground and the
##     walker is blocked.
## A walker whose exact spot is already taken stops right next to it.
## Whole numbers and a fixed order (by id), so every device agrees.
func _separate() -> void:
	var min_dist: int = RADIUS * 2
	var buckets := _buckets(min_dist)
	var n: int = units.size()
	for i in n:
		var a: Dictionary = units[i]
		var cell := Vector2i(a.x / min_dist, a.z / min_dist)
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				for j in buckets.get(cell + Vector2i(ox, oy), []):
					if j <= i:
						continue  # each pair once
					_push_apart(a, units[j], min_dist)
	for u in units:
		if u.moving and u.path.size() == 1:
			_stop_if_spot_taken(u, min_dist)


## Unit indexes grouped by square cells of `size`, for nearby lookups.
func _buckets(size: int) -> Dictionary:
	var buckets := {}
	for i in units.size():
		var u: Dictionary = units[i]
		var cell := Vector2i(u.x / size, u.z / size)
		if not buckets.has(cell):
			buckets[cell] = []
		buckets[cell].append(i)
	return buckets


func _push_apart(a: Dictionary, b: Dictionary, min_dist: int) -> void:
	var dx: int = b.x - a.x
	var dz: int = b.z - a.z
	if absi(dx) >= min_dist or absi(dz) >= min_dist:
		return
	var d2: int = dx * dx + dz * dz
	if d2 >= min_dist * min_dist:
		return
	var d: int = _isqrt(d2)
	if d == 0:
		# Exactly on top of each other: split sideways, by id.
		dx = 1 if a.id < b.id else -1
		dz = 0
		d = 1
	var overlap: int = min_dist - d
	# Direction from a to b, scaled to 1000.
	var nx: int = dx * 1000 / d
	var nz: int = dz * 1000 / d
	if a.moving == b.moving:
		var half: int = overlap / 2
		_nudge_or_other(a, b, -nx * half / 1000, -nz * half / 1000)
		_nudge_or_other(b, a, nx * (overlap - half) / 1000, nz * (overlap - half) / 1000)
		return
	var walker: Dictionary = a if a.moving else b
	var idle: Dictionary = b if a.moving else a
	var sign: int = 1 if walker == a else -1  # direction walker -> idle
	if walker.team != idle.team:
		# Enemies don't make way: the walker is held back.
		_nudge(walker, -sign * nx * overlap / 1000, -sign * nz * overlap / 1000)
		return
	# Our own idle unit steps aside, mostly sideways to the walker's heading,
	# exactly far enough to clear the walker's body.
	var side: Vector2i = _sidestep(walker, idle, Vector2i(sign * nx, sign * nz))
	var wx: int = idle.x - walker.x
	var wz: int = idle.z - walker.z
	var along: int = (wx * side.x + wz * side.y) / 1000  # how far apart along the step
	var dist_now2: int = wx * wx + wz * wz
	var step: int = _isqrt(along * along + min_dist * min_dist - dist_now2) - along + 1
	if _nudge(idle, side.x * step / 1000, side.y * step / 1000):
		# The walker eases off a little too, so in a crowd the stepping-aside
		# unit isn't the only one absorbing the pushes.
		_nudge(walker, -sign * nx * overlap / 4000, -sign * nz * overlap / 4000)
	else:
		_nudge(walker, -sign * nx * overlap / 1000, -sign * nz * overlap / 1000)


## Direction (scaled to 1000) for an idle unit to step out of a walker's way:
## sideways to where the walker is heading, on the side it's already on,
## plus a little straight away from the walker.
func _sidestep(walker: Dictionary, idle: Dictionary, away: Vector2i) -> Vector2i:
	var next: Vector2i = walker.path[0] if not walker.path.is_empty() else Vector2i(walker.tx, walker.tz)
	var hx: int = next.x - walker.x
	var hz: int = next.y - walker.z
	var h: int = _isqrt(hx * hx + hz * hz)
	if h == 0:
		return away
	var px: int = -hz * 1000 / h
	var pz: int = hx * 1000 / h
	var on_side: int = px * away.x + pz * away.y
	if on_side < 0 or (on_side == 0 and idle.id % 2 == 0):
		px = -px
		pz = -pz
	var vx: int = px * 2 + away.x
	var vz: int = pz * 2 + away.y
	var v: int = _isqrt(vx * vx + vz * vz)
	if v == 0:
		return away
	return Vector2i(vx * 1000 / v, vz * 1000 / v)


## Nudges `u`; if it can't move there (blocked ground), pushes `other` the
## opposite way instead, so the overlap still gets resolved.
func _nudge_or_other(u: Dictionary, other: Dictionary, dx: int, dz: int) -> void:
	if not _nudge(u, dx, dz):
		_nudge(other, -dx, -dz)


## Moves a unit by (dx, dz) unless that would put it on blocked ground.
## Returns false if it couldn't move.
func _nudge(u: Dictionary, dx: int, dz: int) -> bool:
	if dx == 0 and dz == 0:
		return true
	var nx: int = u.x + dx
	var nz: int = u.z + dz
	var grid = nav()
	if grid != null and not grid.is_walkable_cell(grid.cell_of(nx, nz)):
		return false
	u.x = nx
	u.z = nz
	return true


## Idle units of the same side that are a bit too close drift apart, a little
## each tick, until each has its own space.
func _spread_idle() -> void:
	var buckets := _buckets(COMFORT)
	var n: int = units.size()
	for i in n:
		var a: Dictionary = units[i]
		if a.moving:
			continue
		var cell := Vector2i(a.x / COMFORT, a.z / COMFORT)
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				for j in buckets.get(cell + Vector2i(ox, oy), []):
					if j <= i:
						continue
					var b: Dictionary = units[j]
					if b.moving or b.team != a.team:
						continue
					var dx: int = b.x - a.x
					var dz: int = b.z - a.z
					var d2: int = dx * dx + dz * dz
					if d2 >= COMFORT * COMFORT:
						continue
					var d: int = _isqrt(d2)
					if d == 0:
						dx = 1 if a.id < b.id else -1
						dz = 0
						d = 1
					var step: int = mini(SPREAD_STEP, (COMFORT - d) / 2)
					if step <= 0:
						continue
					_nudge_or_other(a, b, -dx * step / d, -dz * step / d)
					_nudge_or_other(b, a, dx * step / d, dz * step / d)


## Walkers that have barely moved for STUCK_TICKS ticks stop where they are.
func _check_stuck() -> void:
	for u in units:
		if not u.moving:
			u.stuck = 0
			continue
		var dx: int = u.x - u.px
		var dz: int = u.z - u.pz
		var expected: int = SPEED[u.kind] / 3
		if dx * dx + dz * dz < expected * expected:
			u.stuck += 1
			if u.stuck >= STUCK_TICKS:
				u.moving = false
				u.path.clear()
				u.stuck = 0
		else:
			u.stuck = 0


func _stop_if_spot_taken(u: Dictionary, min_dist: int) -> void:
	var dx: int = u.tx - u.x
	var dz: int = u.tz - u.z
	if dx * dx + dz * dz > min_dist * min_dist:
		return  # not yet up against the spot
	for other in units:
		if other.id == u.id or other.moving:
			continue
		var ox: int = other.x - u.tx
		var oz: int = other.z - u.tz
		if ox * ox + oz * oz < min_dist * min_dist:
			u.moving = false
			u.path.clear()
			return


## Whole-number square root (same result on every device).
static func _isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var x: int = n
	var y: int = (x + 1) / 2
	while y < x:
		x = y
		y = (x + n / x) / 2
	return x


# --- Setup -----------------------------------------------------------------------

## Two armies on opposite sides of the island, mirrored for fairness.
func _spawn_armies() -> void:
	var center := Vector2i(410, 410) * SCALE
	var army: Vector2i = Vector2i(-150, -40)
	if field != null:
		field.build()
		army = field.army_offset
	var bases := [center + army * SCALE, center - army * SCALE]
	for team in 2:
		var flip: int = 1 if team == 0 else -1
		for kind in 3:
			for i in UNITS_PER_KIND:
				var offset := Vector2i((i * 2 - (UNITS_PER_KIND - 1)) * 500, (kind - 1) * 1200)
				var at: Vector2i = bases[team] + offset * flip
				_add_unit(team, kind, at)


func _add_unit(team: int, kind: int, at: Vector2i) -> void:
	var u := {
		"id": _next_id, "team": team, "kind": kind,
		"x": at.x, "z": at.y, "px": at.x, "pz": at.y,
		"tx": at.x, "tz": at.y, "moving": false, "path": [], "stuck": 0,
		"hp": MAX_HP, "target": 0, "ordered": false, "next_attack": 0,
		"attack_tick": -1000, "hurt_tick": -1000, "repath": 0,
		"attack_move": false, "dest_x": at.x, "dest_z": at.y, "focus": false, "chasing": false,
		"hold": false, "orders": [], "job": "", "node": 0, "phase": "", "timer": 0, "carry": 0, "carry_res": 0,
		"work_x": 0, "work_z": 0, "work_res": 0, "tries": 0,
	}
	_next_id += 1
	units.append(u)
	_by_id[u.id] = u

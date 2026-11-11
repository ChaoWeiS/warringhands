extends RefCounted
## A computer opponent. It plays by the same rules as a person: once a
## second it looks at the game and gives orders (gather, build, train,
## attack-move) through the same commands the player uses. Everything it
## decides comes from the game state in a fixed order with whole numbers, so
## it stays in lockstep.
##
## What it does:
##   - keeps one worker on each resource (rock on stone, paper on wood,
##     scissors on metal), plus an extra one on whatever its favourite unit
##     costs;
##   - builds a quarry, a mill and a forge next to its HQ;
##   - trains units, favouring whatever beats the opponent's most common type
##     (other types only while the favourite outnumbers each of them 2 to 1);
##   - defends: sends its army at enemies near its base;
##   - attacks: sends waves at the enemy HQ, the first after FIRST_WAVE ticks,
##     each one bigger than the last.

## Think once a second.
const INTERVAL := 20
## First attack after 2.5 minutes, then every 45 s (if the army is big enough).
const FIRST_WAVE := 3000
const WAVE_GAP := 900
const FIRST_WAVE_SIZE := 6
const WAVE_GROWTH := 2
## Enemies this close to any of our buildings get attacked (sim units).
const DEFEND_RADIUS := 6000
## Only train non-favourite units with this much of their resource spare.
const RESERVE := 200
## Extra workers on the favourite unit's resource.
const EXTRA_WORKERS := 2

var team: int
var wave_size: int = FIRST_WAVE_SIZE
var next_wave: int = FIRST_WAVE
var waves_sent: int = 0


func _init(ai_team: int) -> void:
	team = ai_team


func think(sim: Node) -> void:
	if sim.winner >= 0:
		return
	var hq: Dictionary = sim.hq_of(team)
	if hq.is_empty():
		return
	var mine: Array = sim.units.filter(func(u): return u.team == team)
	var favourite: int = _counter_kind(sim)
	_keep_workers(sim, mine, hq, favourite)
	_build_factories(sim, hq, favourite)
	_train(sim, favourite)
	if not _defend(sim, mine):
		_attack(sim, mine)


## The kind that beats the opponent's most common unit type.
func _counter_kind(sim: Node) -> int:
	var counts := [0, 0, 0]
	for u in sim.units:
		if u.team != team:
			counts[u.kind] += 1
	var most := 0
	for k in 3:
		if counts[k] > counts[most]:
			most = k
	# The kind k with beats(k, most): rock(0) > scissors(2) > paper(1) > rock(0).
	for k in 3:
		if sim.beats(k, most):
			return k
	return 0


## One worker per resource, each on the resource it gathers fastest, plus
## extra workers (any kind) on the favourite unit's resource.
func _keep_workers(sim: Node, mine: Array, hq: Dictionary, favourite: int) -> void:
	for res in 3:
		var wanted: int = 1 + (EXTRA_WORKERS if res == favourite else 0)
		var have := 0
		for u in mine:
			if u.job == "gather" and sim.get_node_by_id(u.node).get("res", -1) == res:
				have += 1
		if have >= wanted:
			continue
		var node: Dictionary = _nearest_node(sim, res, hq)
		if node.is_empty():
			continue
		var pick: Dictionary = {}
		for u in mine:
			if u.job != "" or u.target != 0 or u.moving or u.attack_move:
				continue
			if u.kind == res:
				pick = u  # best: gathers its own resource fast
				break
			if pick.is_empty() and have >= 1:
				pick = u  # extra workers can be any kind
		if not pick.is_empty():
			sim.command_gather([pick.id], node.id)


func _nearest_node(sim: Node, res: int, from: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for n in sim.nodes:
		if n.res != res or n.amount <= 0:
			continue
		if best.is_empty() or sim._dist2(n, from) < sim._dist2(best, from):
			best = n
	return best


## One of each factory, the one making our favourite kind first.
func _build_factories(sim: Node, hq: Dictionary, favourite: int) -> void:
	var order: Array = [favourite, (favourite + 1) % 3, (favourite + 2) % 3]
	for kind in order:
		var btype: String = sim.FACTORY_FOR_KIND[kind]
		var owned := false
		for b in sim.buildings:
			if b.team == team and b.btype == btype:
				owned = true
				break
		if owned:
			continue
		var spec: Dictionary = sim.BUILDINGS[btype]
		if not sim.can_afford(team, spec.res, spec.cost):
			continue
		var spot: Variant = _build_spot(sim, hq, btype)
		if spot != null:
			sim.command_build(team, btype, spot)
		return  # one building per think, so we don't double-spend


## First open spot in rings around the HQ, starting on the side facing the
## island centre.
func _build_spot(sim: Node, hq: Dictionary, btype: String) -> Variant:
	var centre := Vector2(410, 410)
	var home := Vector2(hq.x, hq.z) / float(sim.SCALE)
	var facing: float = (centre - home).angle()
	for ring in [26.0, 36.0, 46.0]:
		for step in 12:
			var turn: float = (step + 1) / 2 * (PI / 6.0) * (1 if step % 2 == 0 else -1)
			var spot: Vector2 = home + Vector2.from_angle(facing + turn) * ring
			spot = Vector2(roundf(spot.x), roundf(spot.y))
			if sim.can_place(btype, spot):
				return spot
	return null


## Keep factories busy: always the favourite kind; others only when well off
## and while the favourite outnumbers them 2 to 1 (counting queued units).
func _train(sim: Node, favourite: int) -> void:
	var counts := [0, 0, 0]
	for u in sim.units:
		if u.team == team:
			counts[u.kind] += 1
	for b in sim.buildings:
		if b.team == team:
			for k in b.queue:
				counts[k] += 1
	for b in sim.buildings:
		if b.team != team or b.btype == "hq":
			continue
		var spec: Dictionary = sim.BUILDINGS[b.btype]
		if b.progress < spec.build or b.queue.size() >= 2:
			continue
		if spec.kind != favourite:
			if counts[spec.kind] * 2 >= counts[favourite]:
				continue
			if not sim.can_afford(team, spec.res, sim.UNIT_COST + RESERVE):
				continue
		elif not sim.can_afford(team, spec.res, sim.UNIT_COST):
			continue
		sim.command_train(team, b.id)
		counts[spec.kind] += 1


## Enemies near our base: send everyone who isn't gathering at them.
func _defend(sim: Node, mine: Array) -> bool:
	var intruder: Dictionary = {}
	for u in sim.units:
		if u.team == team:
			continue
		for b in sim.buildings:
			if b.team == team and sim._dist2(u, b) <= DEFEND_RADIUS * DEFEND_RADIUS:
				intruder = u
				break
		if not intruder.is_empty():
			break
	if intruder.is_empty():
		return false
	var defenders: Array = []
	for u in mine:
		if u.job == "" and u.target == 0 and not u.attack_move:
			defenders.append(u.id)
	if not defenders.is_empty():
		sim.command_attack_move(defenders, Vector3(intruder.x / float(sim.SCALE), 0, intruder.z / float(sim.SCALE)))
	return true


## Send a wave at the enemy HQ when it's time and the army is big enough.
func _attack(sim: Node, mine: Array) -> void:
	if sim.tick < next_wave:
		return
	var army: Array = []
	for u in mine:
		if u.job == "":
			army.append(u.id)
	if army.size() < wave_size:
		return
	var goal: Dictionary = sim.hq_of(1 - team)
	if goal.is_empty():
		for b in sim.buildings:
			if b.team != team:
				goal = b
				break
	if goal.is_empty():
		return
	sim.command_attack_move(army, Vector3(goal.x / float(sim.SCALE), 0, goal.z / float(sim.SCALE)))
	waves_sent += 1
	wave_size += WAVE_GROWTH
	next_wave = sim.tick + WAVE_GAP

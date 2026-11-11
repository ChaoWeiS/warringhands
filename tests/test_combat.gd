extends SceneTree
## Combat: rock-paper-scissors damage, duels, spotting enemies, orders
## coming first, group battles, lockstep, and the game reacting to deaths.
## Run: godot --headless -s res://tests/test_combat.gd

const SimScript := preload("res://scripts/sim/sim.gd")
const ROCK := 0
const PAPER := 1
const SCISSORS := 2
const NAMES := ["rock", "paper", "scissors"]

var field: Node3D
var failures := 0
var out_dir: String
## Open ground for fights (checked below).
var arena := Vector2(430, 600)


func _initialize() -> void:
	root.size = Vector2i(1920, 1200)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	create_timer(60.0).timeout.connect(func(): print("FAIL timed out"); quit(1))
	out_dir = OS.get_environment("OUT")
	root.add_child(load("res://scenes/main.tscn").instantiate())
	_run()


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


## A fresh simulation on the same island, with no units.
func new_sim() -> Node:
	var s: Node = SimScript.new()
	s.field = field
	root.add_child(s)
	s.set_process(false)
	s.clear_units()
	return s


## Runs until one side has no units left (or `limit` ticks). Returns ticks.
func fight_out(s: Node, limit: int = 3000) -> int:
	for t in limit:
		var teams := {}
		for u in s.units:
			teams[u.team] = true
		if teams.size() < 2:
			return t
		s.step_ticks(1)
	return limit


func survivors(s: Node, team: int) -> Array:
	return s.units.filter(func(u): return u.team == team)


func _run() -> void:
	await frames(5)
	field = root.get_node("Main/World/Field")
	root.get_node("Main/Sim").set_process(false)
	root.get_node("Main/Sim")._ais.clear()  # these tests drive both sides by hand
	check("arena is open ground", field.is_walkable(arena) and field.is_walkable(arena + Vector2(25, 0)))

	# Damage table.
	check("counter hits do double (rock > scissors: %d)" % SimScript.damage_for(ROCK, SCISSORS),
			SimScript.damage_for(ROCK, SCISSORS) == 20 and SimScript.damage_for(SCISSORS, PAPER) == 20
			and SimScript.damage_for(PAPER, ROCK) == 20)
	check("countered hits do half (scissors > rock: %d)" % SimScript.damage_for(SCISSORS, ROCK),
			SimScript.damage_for(SCISSORS, ROCK) == 5 and SimScript.damage_for(PAPER, SCISSORS) == 5
			and SimScript.damage_for(ROCK, PAPER) == 5)
	check("same kind does normal damage", SimScript.damage_for(PAPER, PAPER) == 10)

	# Duels: the counter always wins, losing very little health.
	for pair in [[ROCK, SCISSORS], [PAPER, ROCK], [SCISSORS, PAPER]]:
		var s := new_sim()
		var winner: int = s.add_unit(0, pair[0], arena)
		var loser: int = s.add_unit(1, pair[1], arena + Vector2(7, 0))
		var hits := {"strong": 0, "weak": 0}
		s.unit_hit.connect(func(_t, _a, _d, strength):
			if strength == 1: hits.strong += 1
			if strength == -1: hits.weak += 1)
		var ticks := fight_out(s)
		var w: Dictionary = s.get_unit(winner)
		check("%s beats %s (left with %s hp, %.1f s)" % [NAMES[pair[0]], NAMES[pair[1]],
				str(w.get("hp", 0)), ticks / 20.0],
				not w.is_empty() and s.get_unit(loser).is_empty() and w.hp >= 75)
		check("...with 5 counter hits landed", hits.strong == 5)
		s.queue_free()

	# Same kind: dead even, both hit at the same moment, both fall together.
	var even := new_sim()
	even.add_unit(0, PAPER, arena)
	even.add_unit(1, PAPER, arena + Vector2(7, 0))
	var deaths: Array = []
	even.unit_died.connect(func(id): deaths.append([id, even.tick]))
	fight_out(even)
	check("evenly matched units fall together", deaths.size() == 2 and deaths[0][1] == deaths[1][1])
	even.queue_free()

	# Spotting: an enemy within sight gets noticed and fought; one far away
	# is left alone.
	var spot := new_sim()
	var watcher: int = spot.add_unit(0, ROCK, arena)
	var near_foe: int = spot.add_unit(1, ROCK, arena + Vector2(25, 0))
	spot.step_ticks(200)
	check("idle units walk up to an enemy in sight and fight",
			spot.get_unit(watcher).get("hp", 0) < 100 or spot.get_unit(near_foe).get("hp", 0) < 100)
	spot.queue_free()
	var calm := new_sim()
	var a: int = calm.add_unit(0, ROCK, arena)
	var b: int = calm.add_unit(1, ROCK, arena + Vector2(60, 0))
	calm.step_ticks(200)
	check("enemies out of sight are left alone", calm.get_unit(a).hp == 100 and calm.get_unit(b).hp == 100
			and calm.unit_ground(a) == arena)
	calm.queue_free()

	# Orders come first: walking past an enemy, an ordered unit doesn't stop
	# to fight on the way.
	var march := new_sim()
	var marcher: int = march.add_unit(0, ROCK, arena + Vector2(-25, 0))
	march.add_unit(1, SCISSORS, arena + Vector2(0, 18))
	march.command_move([marcher], Vector3(arena.x + 25, 0, arena.y))
	var distracted := false
	for t in 200:
		march.step_ticks(1)
		var m: Dictionary = march.get_unit(marcher)
		if m.ordered and m.moving and m.target != 0:
			distracted = true
	check("units under orders don't stop to fight on the way", not distracted)
	march.queue_free()

	# Fighting back: a unit on a plain move order that gets attacked stops
	# and fights its attacker.
	var ambush := new_sim()
	var walker: int = ambush.add_unit(0, ROCK, arena + Vector2(-25, 0))
	var ambusher: int = ambush.add_unit(1, PAPER, arena + Vector2(0, 9))
	ambush.command_move([walker], Vector3(arena.x + 25, 0, arena.y))
	var hit_back := false
	for t in 400:
		ambush.step_ticks(1)
		var amb: Dictionary = ambush.get_unit(ambusher)
		if amb.is_empty() or amb.hp < 100:
			hit_back = true
			break
	check("a unit attacked on the move stops and fights back", hit_back)
	ambush.queue_free()

	# Attack-move: march past an enemy, kill it on the way, carry on to the
	# destination.
	var charge := new_sim()
	var charger: int = charge.add_unit(0, ROCK, arena + Vector2(-25, 0))
	var victim: int = charge.add_unit(1, SCISSORS, arena + Vector2(0, 14))
	var dest := arena + Vector2(25, 0)
	charge.command_attack_move([charger], Vector3(dest.x, 0, dest.y))
	charge.step_ticks(900)
	check("attack-move fights an enemy met on the way", charge.get_unit(victim).is_empty())
	check("...then carries on to the destination (%.1f away)" % charge.unit_ground(charger).distance_to(dest),
			charge.unit_ground(charger).distance_to(dest) < 1.0 and not charge.get_unit(charger).moving)
	charge.queue_free()

	# Attack order: go after one particular enemy, even far out of sight,
	# ignoring a closer one.
	var hunt := new_sim()
	var hunter: int = hunt.add_unit(0, PAPER, arena)
	var prey: int = hunt.add_unit(1, ROCK, arena + Vector2(0, -60))
	var bystander: int = hunt.add_unit(1, PAPER, arena + Vector2(0, 30))
	hunt.command_attack([hunter], prey)
	for t in 1500:
		hunt.step_ticks(1)
		if hunt.get_unit(prey).is_empty():
			break
	check("attack order hunts down a chosen enemy out of sight", hunt.get_unit(prey).is_empty()
			and not hunt.get_unit(hunter).is_empty())
	hunt.queue_free()

	# A proper charge into a mirrored army is a fair fight: attack-moving
	# together, we trade roughly evenly instead of being picked off.
	var fair := new_sim()
	var ours: Array = []
	for k in 3:
		for i in 4:
			ours.append(fair.add_unit(0, k, arena + Vector2(-40 - i * 7, (k - 1) * 10)))
			fair.add_unit(1, k, arena + Vector2(40 + i * 7, (k - 1) * 10))
	fair.command_attack_move(ours, Vector3(arena.x + 50, 0, arena.y))
	fight_out(fair, 4000)
	var kept: int = survivors(fair, 0).size()
	var lost_theirs: int = 12 - survivors(fair, 1).size()
	check("charging a mirrored army trades evenly (we killed %d, kept %d)" % [lost_theirs, kept],
			lost_theirs >= 6)
	fair.queue_free()

	# Group battle: 4 rocks against 4 scissors. Rocks win comfortably.
	var war := new_sim()
	for i in 4:
		war.add_unit(0, ROCK, arena + Vector2(-12, (i - 1.5) * 8))
		war.add_unit(1, SCISSORS, arena + Vector2(12, (i - 1.5) * 8))
	var war_ticks := fight_out(war)
	check("4 rocks beat 4 scissors (%d rocks left, %.1f s)" % [survivors(war, 0).size(), war_ticks / 20.0],
			survivors(war, 1).is_empty() and survivors(war, 0).size() >= 3)
	war.queue_free()

	# Mixed armies: the full starting armies fight; it ends with one side
	# wiped out, and nobody ever overlaps.
	# Lockstep: the same battle twice gives the identical result.
	var results: Array = []
	for run in 2:
		var s := new_sim()
		var kinds := [ROCK, PAPER, SCISSORS]
		for k in 3:
			for i in 3:
				s.add_unit(0, kinds[k], arena + Vector2(-14 - i * 7, (k - 1) * 9))
				s.add_unit(1, kinds[(k + 1) % 3], arena + Vector2(14 + i * 7, (k - 1) * 9))
		var tight: int = 1 << 30
		for t in 3000:
			s.step_ticks(1)
			for i in s.units.size():
				for j in range(i + 1, s.units.size()):
					tight = mini(tight, int(sqrt(float(SimScript._dist2(s.units[i], s.units[j])))))
			var teams := {}
			for u in s.units:
				teams[u.team] = true
			if teams.size() < 2:
				break
		var snapshot: Array = []
		for u in s.units:
			snapshot.append([u.id, u.hp, u.x, u.z])
		results.append([snapshot, s.tick, tight])
		s.queue_free()
	check("a mixed battle ends with one side wiped out (%d left, %.1f s)" % [results[0][0].size(), results[0][1] / 20.0],
			results[0][0].size() > 0 and results[0][1] < 3000)
	check("nobody overlaps during the battle (closest %.1f, bodies 6.4)" % (results[0][2] / 100.0),
			results[0][2] >= SimScript.RADIUS * 2 * 0.9)
	check("same battle twice gives identical results (lockstep)", results[0] == results[1])

	# In the game: a selected unit that dies leaves the selection, and its
	# visuals fade away.
	var sim: Node = root.get_node("Main/Sim")
	var game: Node = root.get_node("Main/Game")
	var view: Node3D = root.get_node("Main/World/Units")
	var bar: Control = root.get_node("Main/HUD/SelectionBar")
	var mine: Array = sim.units.filter(func(u): return u.team == 0).map(func(u): return u.id)
	var doomed: int = mine[11]  # the scissors at the end of its row
	game._select([doomed, mine[0]])
	var spot_d: Vector2 = sim.unit_ground(doomed)
	sim.add_unit(1, ROCK, spot_d + Vector2(7, 0))
	sim.get_unit(doomed).hp = 20
	var doomed_sprite: AnimatedSprite3D = view._views[doomed].sprite
	sim.step_ticks(60)
	check("the doomed unit fell", sim.get_unit(doomed).is_empty())
	check("it left the selection", game.selection == [mine[0]] and bar.visible)
	check("its visuals are fading out", not view._views.has(doomed))
	check("the attacker got visuals of its own (added mid-game)", view._views.size() == sim.units.size())
	var hurt: Array = sim.units.filter(func(u): return u.hp < sim.MAX_HP)
	view._update_combat_look()
	var bars_ok: bool = not hurt.is_empty()
	for u in hurt:
		bars_ok = bars_ok and view._views[u.id].hp_bg.visible
	for u in sim.units:
		if u.hp == sim.MAX_HP:
			bars_ok = bars_ok and not view._views[u.id].hp_bg.visible
	check("damaged units show an HP bar (and healthy ones don't)", bars_ok)
	check("a fallen unit plays its death animation (once)", doomed_sprite.animation == "death"
			and not doomed_sprite.sprite_frames.get_animation_loop("death"))

	# Every swing plays the attack animation once, from the wind-up.
	var swinger: Dictionary = sim.get_unit(mine[0])
	var swing_view: Dictionary = view._views[mine[0]]
	swinger.target = mine[1]  # any id; only "has a target" matters to the look
	swinger.attack_tick = sim.tick
	view._update_combat_look()
	var first_ok: bool = swing_view.sprite.animation == "attack" and swing_view.sprite.frame == 0
	swing_view.sprite.frame = 3  # mid-swing...
	swinger.attack_tick = sim.tick - 1  # ...a new swing comes in
	swinger.hurt_tick = sim.tick  # hit at the same moment: the swing still shows
	view._update_combat_look()
	check("each swing starts the attack animation from its wind-up (and beats a flinch)",
			first_ok and swing_view.sprite.animation == "attack" and swing_view.sprite.frame == 0
			and not swing_view.sprite.sprite_frames.get_animation_loop("attack"))
	swinger.target = 0
	swinger.attack_tick = -1000
	swinger.hurt_tick = -1000

	# Controls: Attack button then tap the ground = attack-move; tapping an
	# enemy with units selected = attack it.
	var cam0 = root.get_node("Main/Panes")._leaves()[0].camera
	var leaf0 = root.get_node("Main/Panes")._leaves()[0]
	var mine_now: Array = sim.units.filter(func(u): return u.team == 0).map(func(u): return u.id)
	game._select(mine_now)
	sim._pending.clear()
	bar._attack.button_pressed = true  # like tapping Attack
	check("attack button arms attack mode", bar.is_attack_armed())
	game._on_tapped(cam0, leaf0.rect.size * 0.5)
	var queued: Array = sim._pending.values()[0] if not sim._pending.is_empty() else []
	check("then tapping the ground gives an attack-move", queued.size() == 1 and queued[0].type == "attack_move")
	check("...and attack mode switches off", not bar.is_attack_armed())
	sim._pending.clear()
	var enemy_id: int = sim.units.filter(func(u): return u.team == 1).front().id
	var enemy_screen: Vector2 = cam0.unproject_position(view.world_position(enemy_id))
	game._on_tapped(cam0, enemy_screen)
	queued = sim._pending.values()[0] if not sim._pending.is_empty() else []
	check("tapping an enemy orders an attack on it", queued.size() == 1 and queued[0].type == "attack"
			and queued[0].target == enemy_id)
	sim._pending.clear()

	# A battle in the real game for the screenshot.
	if out_dir != "":
		var cam = root.get_node("Main/Panes")._leaves()[0].camera
		sim.clear_units()
		for k in 3:
			for i in 3:
				sim.add_unit(0, k, arena + Vector2(-9 - i * 7, (k - 1) * 8))
				sim.add_unit(1, (k + 1) % 3, arena + Vector2(9 + i * 7, (k - 1) * 8))
		await frames(2)
		cam.target = Vector3(arena.x, 0, arena.y)
		cam.units_per_pixel = 0.05
		cam.refit()
		for t in 75:
			sim.step_ticks(1)
			view._update_hops(0.05)
			await process_frame
		root.get_texture().get_image().save_png(out_dir + "/battle.png")

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)

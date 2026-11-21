extends RefCounted
## The campaign: the tutorial as chapters, each a short lesson on the
## island that builds on the last. Played by tutorial.gd.
##
## Each chapter: title, a line for the chapter list, an optional "setup"
## (a tutorial.gd method run before the first step) and its steps.
## Each step: text, and how it's done:
##   "on": player actions (game_controller `did`), or
##   "poll": a tutorial.gd method checked every frame, or
##   "next": a Next button (a tip to read).
## Optional: "enter" (a method run when the step starts), "point" (what the
## arrows point at, see tutorial.gd `_resolve`), "picture" (shown on the
## card: "hq", "rps", "gather", "factories", "balance").
## The last step of every chapter has "end": true.
## A chapter plays on "map" (default: the small training island) and only
## shows the buttons it has taught so far ("tools": "minimap", "attack",
## "hold", "queue", "build", "build_hq", "panes").

const PROGRESS_KEY := "campaign_done"

const CHAPTERS := [
	{
		"title": "Getting around",
		"blurb": "The camera, the map and picking your hands.",
		"setup": "_setup_basic",
		"tools": ["minimap"],
		"steps": [
			{"text": "Welcome to Warring Hands!\nFor the best experience, hold your device sideways (landscape).", "next": true},
			{"text": "This is your HQ, your town hall. Everything starts here, and if it falls, you lose.", "next": true,
				"picture": "hq", "point": ["hq"]},
			{"text": "Move the camera: drag with one finger, like a map.\n(Mouse: drag with the right button.)", "poll": "_camera_panned",
				"enter": "_note_cameras"},
			{"text": "Zoom in and out: pinch with two fingers.\n(Mouse: the scroll wheel.)", "poll": "_camera_zoomed",
				"enter": "_note_cameras"},
			{"text": "The minimap in the corner shows the whole island. Tap somewhere on it to look there.",
				"poll": "_camera_jumped", "enter": "_note_cameras", "point": ["ui:minimap"]},
			{"text": "These are your hands. Tap one to select it.", "on": ["select", "select_kind", "lasso"],
				"enter": "_go_home", "point": ["kind:0"]},
			{"text": "Select a group, with two fingers:\n1. Keep one finger pressed on the Group button (where the arrow points).\n2. With another finger, draw a loop around your hands, like the dashed one.\n(Mouse: just drag a loop around them.)",
				"holding_text": "Keep holding Group, and with another finger draw a loop around your hands, like the dashed one.",
				"on": ["lasso"], "point": ["ui:group", "army"]},
			{"text": "Send them to the circle: tap inside it.", "enter": "_mark_move_spot", "poll": "_reached_mark",
				"point": ["mark:0"]},
			{"text": "Double tap a hand: every hand of that kind on screen gets picked.", "on": ["select_kind"],
				"point": ["kind:1"]},
			{"text": "Tap a selected hand again to let go of just that one. To unselect everything, tap the screen with two fingers at once.\n(Mouse: right click.)",
				"on": ["unselect", "unselect_one"]},
			{"text": "Chapter complete!\nYou can find your way around and pick your hands.", "end": true},
		],
	},
	{
		"title": "Rock, paper, scissors",
		"blurb": "Which hand beats which, and your first fights.",
		"setup": "_setup_basic",
		"tools": ["minimap", "attack"],
		"steps": [
			{"text": "Every hand is rock, paper or scissors, like the game you know.\nRock beats scissors, scissors beat paper, paper beats rock. A hand hits what it beats for 20, but only 5 the other way round. Two of a kind hit each other for 10.",
				"next": true, "picture": "rps"},
			{"text": "Enemy scissors are here! Rock beats scissors.\nDouble tap one of your rocks to pick them all, then tap an enemy to attack.",
				"enter": "_wave_scissors", "poll": "_enemies_beaten", "point": ["kind:0", "enemies"]},
			{"text": "Enemy papers now. What beats paper? Scissors!\nPick your scissors and attack.",
				"enter": "_wave_papers", "poll": "_enemies_beaten", "point": ["kind:2", "enemies"]},
			{"text": "Enemy rocks! Paper wraps rock: send your papers.",
				"enter": "_wave_rocks", "poll": "_enemies_beaten", "point": ["kind:1", "enemies"]},
			{"text": "A mixed group. Select all your hands (hold Group and loop them), tap the sword button, then tap near the enemies: your hands fight everything they meet on the way.",
				"enter": "_wave_mixed", "poll": "_enemies_beaten", "point": ["ui:group", "ui:attack", "enemies", "army"]},
			{"text": "Chapter complete!\nSend the right hand to each fight and you win with fewer losses.", "end": true},
		],
	},
	{
		"title": "Resources and factories",
		"blurb": "Gathering, and where to build your factories.",
		"setup": "_setup_resources",
		"tools": ["minimap", "attack", "build"],
		"steps": [
			{"text": "Hands also gather. Your stone, wood and metal are at the top right.\nEach hand is fastest at its own: rocks dig stone, papers cut wood, scissors mine metal.",
				"next": true, "picture": "gather", "point": ["ui:resources"]},
			{"text": "This is a stone pile. Double tap one of your rocks, then tap the pile.",
				"poll": "_gathering_stone", "point": ["node:0", "kind:0"]},
			{"text": "Each load goes back to your HQ. Watch the stone come in at the top right.",
				"poll": "_stone_at_hq", "point": ["hq", "ui:resources"]},
			{"text": "Factories make new hands. Each one is also a drop-off for one resource, so it works like a farm when it's built right next to it.",
				"next": true, "picture": "factories"},
			{"text": "Build a Quarry right beside the stone pile: tap the hammer, pick Quarry, then put it where the arrow points.",
				"poll": "_quarry_near", "point": ["ui:build:quarry", "spot:0"]},
			{"text": "Distance matters! Once the Quarry is finished, your rocks drop their stone there instead of walking all the way to the HQ. Shorter trips bring in more stone.",
				"poll": "_stone_at_quarry", "point": ["building:quarry"]},
			{"text": "Now wood: pick your papers and tap the lumber camp.",
				"poll": "_gathering_wood", "point": ["node:1", "kind:1"]},
			{"text": "Build a Paper Mill right beside it.",
				"poll": "_mill_near", "point": ["ui:build:mill", "spot:1"]},
			{"text": "And metal: pick your scissors and tap the crystals.",
				"poll": "_gathering_metal", "point": ["node:2", "kind:2"]},
			{"text": "Build a Forge right beside the crystals.",
				"poll": "_forge_near", "point": ["ui:build:forge", "spot:2"]},
			{"text": "Chapter complete!\nEvery resource has a drop-off right beside it now.", "end": true},
		],
	},
	{
		"title": "Making hands",
		"blurb": "Training, and gatherers versus fighters.",
		"setup": "_setup_economy",
		"tools": ["minimap", "attack", "build"],
		"steps": [
			{"text": "Tap your Quarry, then press + to make a rock. It costs 60 stone.",
				"on": ["train"], "point": ["ui:train", "building:quarry"]},
			{"text": "Training takes 5 seconds. New hands go straight to gathering, so more hands bring in more.",
				"poll": "_new_rock", "point": ["building:quarry"]},
			{"text": "Make a paper at the Paper Mill and a scissors at the Forge too.",
				"poll": "_new_paper_and_scissors", "point": ["building:mill", "building:forge"]},
			{"text": "Your gatherers are also your army. A hand sent to fight stops gathering, and a hand that gathers isn't fighting.\nKeep a balance: too few gatherers and you can't afford new hands; too few fighters and you can't defend.",
				"next": true, "picture": "balance"},
			{"text": "Enemies are coming! Send just a few hands to stop them, and leave the rest gathering.",
				"enter": "_wave_raid", "poll": "_enemies_beaten", "point": ["enemies"]},
			{"text": "Now send your fighters back to work: select them and tap a resource, or tap your HQ and each goes to its best one.",
				"on": ["gather", "harvest"]},
			{"text": "Chapter complete!\nYou can grow your army and keep it fed.", "end": true},
		],
	},
	{
		"title": "Repairs",
		"blurb": "Fixing damaged buildings.",
		"setup": "_setup_repairs",
		"tools": ["minimap", "attack", "build", "build_hq"],
		"steps": [
			{"text": "Your Paper Mill has been damaged. The bar above it shows its health.",
				"next": true, "point": ["building:mill"]},
			{"text": "Double tap the Paper Mill: your hands nearby walk over and repair it, for free.",
				"on": ["repair"], "point": ["building:mill"]},
			{"text": "Green numbers show the health coming back. Wait until it's whole.",
				"poll": "_mill_repaired", "point": ["building:mill"]},
			{"text": "One more thing: the hammer's HQ option makes another HQ anywhere on the island (150 of each resource). Use it as a forward base, or as a drop-off by far-away resources.",
				"next": true, "point": ["ui:build"]},
			{"text": "Chapter complete!\nKeep your buildings standing and your base can grow anywhere.", "end": true},
		],
	},
	{
		"title": "Battle tricks",
		"blurb": "Hold, plans in a queue, and split screens.",
		"setup": "_setup_basic",
		"tools": ["minimap", "attack", "hold", "queue", "build", "build_hq", "panes"],
		"steps": [
			{"text": "Select your hands and send them to the circle.", "enter": "_mark_move_spot", "poll": "_reached_mark",
				"point": ["mark:0"]},
			{"text": "Hold: press the stop-sign button. Your hands stop and stay put, and only fight what comes within reach.",
				"on": ["hold"], "point": ["ui:hold"]},
			{"text": "Queue a route: keep a finger on the 1-2-3 button (or hold Shift) and tap circle 1, then 2, then 3. Your hands walk to each in turn. (Hold cancels a plan.)",
				"enter": "_mark_queue_spots", "poll": "_queue_route_done", "point": ["ui:queue", "mark:0", "mark:1", "mark:2"]},
			{"text": "Split the screen: grab the white tab on a side of the screen and swipe across.\nEach pane has its own camera, so you can watch two places at once.",
				"poll": "_split_done"},
			{"text": "Drag the divider between the panes all the way to an edge to merge them again.",
				"poll": "_merged_done"},
			{"text": "Chapter complete!\nYou know every trick. Time for a real battle.", "end": true},
		],
	},
	{
		"title": "First battle",
		"blurb": "Everything together, against the computer (Easy).",
		"setup": "_setup_battle",
		"enemies": true,
		"map": "island",
		"tools": ["minimap", "attack", "hold", "queue", "build", "build_hq", "panes"],
		"steps": [
			{"text": "Your first real battle, against the computer on Easy.\nGather, build factories by your resources, train hands, and destroy the blue HQ. Good luck!",
				"next": true, "point": ["hq"]},
			{"text": "", "poll": "_battle_won", "enter": "_tuck_card"},
			{"text": "Campaign complete!\nYou beat the computer. Try Normal or Hard from Play vs Computer, or play a friend online.", "end": true},
		],
	},
]


## The map a chapter plays on.
static func map_of(chapter: int) -> String:
	return CHAPTERS[clampi(chapter, 0, CHAPTERS.size() - 1)].get("map", "training")


## Which chapters are done (indexes), as saved on this device.
static func done() -> Array:
	var Settings = load("res://scripts/settings.gd")
	var saved: String = Settings.get_choice(PROGRESS_KEY, "")
	var out: Array = []
	for part in saved.split(",", false):
		out.append(int(part))
	return out


static func mark_done(chapter: int) -> void:
	var list: Array = done()
	if chapter in list:
		return
	list.append(chapter)
	list.sort()
	var Settings = load("res://scripts/settings.gd")
	Settings.set_choice(PROGRESS_KEY, ",".join(list.map(func(i): return str(i))))


## The first chapter not done yet (or the last one).
static func next_up() -> int:
	var list: Array = done()
	for i in CHAPTERS.size():
		if not i in list:
			return i
	return CHAPTERS.size() - 1

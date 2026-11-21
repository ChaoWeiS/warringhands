extends RefCounted
## What's new, newest first, as players read it (the start menu's "What's
## new" window). Add an entry at the top for each update worth telling; its
## `id` must be new, so the window pops up once for everyone who hasn't
## seen it.

const ENTRIES := [
	{
		"id": "2026-11-21-campaign2",
		"date": "21 Nov 2026",
		"title": "A clearer campaign",
		"items": [
			"A spotlight: the screen dims except for what each step is about.",
			"When a new step starts, the camera glides over to it if you've wandered off.",
			"Moving, Hold and Queue lessons have marked circles to send your hands to (Queue: 1, then 2, then 3).",
			"Finish a step to move on: Skip only appears if you've been stuck for a minute.",
			"Menu asks before leaving the campaign, so you can't quit by accident.",
			"Full screen on iPhone and iPad: if Safari can't do it, the button explains how to add the game to your home screen, which opens it full screen.",
		],
	},
	{
		"id": "2026-11-21-controls",
		"date": "21 Nov 2026",
		"title": "Easier controls",
		"items": [
			"Move the camera with one finger, like a map.",
			"New Group button (left, under Queue): keep a finger on it and draw a loop with another to select a group. On a computer, just drag a loop.",
			"Tap a selected hand again to let it go; tap another hand to pick just that one.",
			"All the buttons are in one column on the left: Build above the screen-cutting tab, Attack, Hold, Queue and Group below it. Your selected hands show in a row along the bottom, out of the way.",
			"Health bars go green, then yellow, then red, and get bigger when you zoom out, like the damage numbers.",
			"Stronger red and blue team colours, so it's easy to tell the sides apart.",
			"Online: if the game server is asleep, the game waits for it to wake up (up to a minute) instead of saying it can't reach it.",
			"The online server has moved to Singapore, for less lag in Asia.",
		],
	},
	{
		"id": "2026-11-20-campaign",
		"date": "20 Nov 2026",
		"title": "Campaign",
		"items": [
			"The tutorial is now a Campaign: seven short chapters on a small Training Island, from moving the camera to your first real battle.",
			"Arrows point at what each step is about, with pictures for the HQ, the rock-paper-scissors circle and the factories.",
			"Learn which factory takes which resource and makes which hand, and why building it right beside the resource matters.",
			"Only the buttons you've learned show, so there's less to get lost in. Each chapter ends with a Victory.",
			"Already know how to play? Open Campaign and tap Skip tutorial: battle!",
		],
	},
	{
		"id": "2026-11-18-world",
		"date": "18 Nov 2026",
		"title": "A livelier island",
		"items": [
			"New map colours.",
			"The sea fades from turquoise shallows to deep blue, with foam and waves rolling onto the beach.",
			"Beaches change width around the island, from narrow strips to wide sandy coves.",
			"Hillsides blend softly into the grass and hilltops.",
			"Grass tufts, flowers and bushes grow across the grassland.",
		],
	},
	{
		"id": "2026-11-18-lasso",
		"date": "18 Nov 2026",
		"title": "Smoother lasso",
		"items": [
			"The lasso stays a smooth curve even when a busy battle slows the game down.",
		],
	},
	{
		"id": "2026-11-12-queue",
		"date": "12 Nov 2026",
		"title": "Plan ahead",
		"items": [
			"Queue: keep a finger on the new 1-2-3 button (or hold Shift) and tap a few places: your hands walk to each in turn, then attack or gather. Hold cancels the plan.",
			"What's new: this window, so you can see what changed.",
		],
	},
	{
		"id": "2026-11-12-hills",
		"date": "12 Nov 2026",
		"title": "Hills, maps and polish",
		"items": [
			"Hills: some raised ground now has broad grassy hillsides you can walk up; the rest is cliff. Some hills have a second tier on top.",
			"Trees, resources and buildings can sit on hilltops.",
			"Three maps to choose from: Hand Island, Twin Lakes and Deep Woods.",
			"Play vs Computer: Easy, Normal or Hard.",
			"3, 2, 1, Fight! before every match.",
			"A minimap in the corner of every pane (turn it off in Settings). Tap it to look there.",
			"Hold button: hands stop and stand their ground.",
			"Surrender (the white flag), with a check first.",
			"Rematch or Quit to menu when a match ends. Online, your opponent is asked.",
			"Online games start together and no longer stutter on slow connections.",
			"Unselect with a two-finger tap, or right click on a computer.",
			"Cancel a building while it's going up (all back) or sell it (half back).",
			"New logo, Victory and Defeat signs, chunkier buttons, bolder damage numbers, softer shadows.",
		],
	},
	{
		"id": "2026-11-11-sound",
		"date": "11 Nov 2026",
		"title": "Sound and settings",
		"items": [
			"Music on the start screen and in battle.",
			"Your hands talk: they answer when picked, cheer orders, shout in fights.",
			"Building sounds when you lay down and finish a building.",
			"Settings (the gear): music and sound volumes.",
		],
	},
	{
		"id": "2026-11-11-online",
		"date": "11 Nov 2026",
		"title": "Play a friend",
		"items": [
			"Online play: create a game and share the 4-digit code, or join with your friend's.",
			"Tutorial mode to learn the basics.",
			"Build more HQs anywhere on the map.",
			"Install the game from your browser, and play full screen.",
		],
	},
	{
		"id": "2026-11-11-first",
		"date": "11 Nov 2026",
		"title": "The first battles",
		"items": [
			"Rock, paper and scissors hands that gather, build and fight.",
			"Cut the screen into panes to watch several places at once; merge them back.",
			"Lasso to select, double tap to pick every hand of a type.",
			"A computer opponent to beat.",
		],
	},
]


static func latest_id() -> String:
	return ENTRIES[0].id

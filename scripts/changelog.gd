extends RefCounted
## What's new, newest first, as players read it (the start menu's "What's
## new" window). Add an entry at the top for each update worth telling; its
## `id` must be new, so the window pops up once for everyone who hasn't
## seen it.

const ENTRIES := [
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

extends RefCounted
## The maps. Each is an island in an 820 x 820 sea, described as offsets
## from the centre; field.gd places every feature twice, turned 180° around
## the centre, so both players always get exactly the same ground.
##
##   coast:    [frequency, amplitude, phase] wobbles of the coastline
##             (even frequencies only, so the island looks the same turned);
##   lakes: [offset, radius x, radius z, rotation];
##   plateaus (hills): [offset, radius x, radius z, rotation, hillsides,
##             level]: each hillside is where round team 0's copy it faces
##             (degrees, 0 = +x, 90 = +z) or {"at", "span"} (how wide round the
##             hill, degrees; default 70). There the edge is a broad grassy
##             slope down to the ground; elsewhere, cliff. Each gives a
##             hillside there and one on the far side (the twin's are turned
##             with it); none = solid scenery.
##             Level 2 sits on a level 1 plateau, twice as high (default 1);
##   forests:  [offset, radius, seed];
##   stones / woods / metals: resource spots (offsets);
##   hq:       team 0's HQ (team 1's is mirrored); army: where its hands start.

const ORDER := ["island", "pass", "woods"]

const MAPS := {
	"island": {
		"name": "Hand Island",
		"blurb": "The classic: lakes and woods, room to grow.",
		"radius": 330.0,
		"coast": [[2, 0.10, 0.6], [4, 0.07, 2.1], [6, 0.04, 4.0], [8, 0.025, 1.3], [12, 0.012, 5.2]],
		"lakes": [[Vector2(0, 0), 58.0, 34.0, 0.5], [Vector2(-50, 185), 32.0, 22.0, -0.4]],
		"forests": [[Vector2(-70, -110), 34.0, 11], [Vector2(-215, 100), 28.0, 12], [Vector2(-15, 95), 20.0, 13]],
		"plateaus": [[Vector2(-120, 85), 46.0, 32.0, 0.15, [{"at": 100.0, "span": 80.0}]],
				[Vector2(-104, 89), 16.0, 8.5, 0.15, [{"at": 0.0, "span": 60.0}], 2],
				[Vector2(-110, -185), 22.0, 17.0, -0.6, []]],
		"stones": [Vector2(-170, -170), Vector2(170, 170)],
		"woods": [Vector2(-170, 170), Vector2(170, -170)],
		"metals": [Vector2(0, -125), Vector2(0, 125), Vector2(-230, 0), Vector2(230, 0)],
		"hq": Vector2i(-200, -30),
		"army": Vector2i(-150, -40),
	},
	"pass": {
		"name": "Twin Lakes",
		"blurb": "Two big lakes; the fight is for the middle pass.",
		"radius": 350.0,
		"coast": [[2, 0.16, 0.0], [4, 0.05, 1.2], [6, 0.03, 2.6], [10, 0.015, 0.7]],
		"lakes": [[Vector2(10, -135), 95.0, 42.0, 0.15], [Vector2(-160, 205), 30.0, 20.0, 0.6]],
		"forests": [[Vector2(-235, -150), 32.0, 21], [Vector2(-280, 70), 24.0, 22], [Vector2(-60, 220), 26.0, 23]],
		"plateaus": [[Vector2(0, 0), 62.0, 34.0, 0.0, [{"at": 180.0, "span": 60.0}, {"at": 90.0, "span": 40.0}]],
				[Vector2(0, 0), 24.0, 13.0, 0.0, [{"at": 0.0, "span": 60.0}], 2],
				[Vector2(-150, -60), 18.0, 14.0, 0.2, []]],
		"stones": [Vector2(-230, -55), Vector2(-120, 125), Vector2(-40, 14)],
		"woods": [Vector2(-200, 135)],
		"metals": [Vector2(-80, 30), Vector2(-300, -10), Vector2(90, -230)],
		"hq": Vector2i(-230, 30),
		"army": Vector2i(-180, 10),
	},
	"woods": {
		"name": "Deep Woods",
		"blurb": "A small, wooded island. Fights come quickly.",
		"radius": 290.0,
		"coast": [[2, 0.06, 1.1], [4, 0.09, 0.3], [6, 0.05, 2.2], [8, 0.03, 4.4]],
		"lakes": [[Vector2(-40, -150), 26.0, 18.0, 0.9]],
		"forests": [[Vector2(0, 0), 40.0, 31], [Vector2(-120, -110), 30.0, 32], [Vector2(-100, 140), 28.0, 33],
				[Vector2(-235, 40), 22.0, 34], [Vector2(80, -175), 22.0, 35], [Vector2(-50, 76), 15.0, 36]],
		"plateaus": [[Vector2(-62, 74), 42.0, 26.0, -0.25, [{"at": 160.0, "span": 90.0}]]],
		"stones": [Vector2(-200, -90), Vector2(40, 120)],
		"woods": [Vector2(-170, 120)],
		"metals": [Vector2(-215, -10), Vector2(-20, -95), Vector2(150, 40)],
		"hq": Vector2i(-160, -10),
		"army": Vector2i(-115, -20),
	},
}


static func get_map(id: String) -> Dictionary:
	return MAPS.get(id, MAPS.island)

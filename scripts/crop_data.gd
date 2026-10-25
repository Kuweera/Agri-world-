extends RefCounted
# Crop catalogue. All numbers live here so they are easy to change.
# grow_seconds is short on purpose for testing.
# visual.stages: each stage starts at progress "from" (0.0 to 1.0).
# The thresholds match crop_models.gd STAGE_FROM (a test checks it). Only "ripe" can be harvested.

# Fertilizer: bought per unit, one unit treats one tile. A fertilized tile gives
# yield_bonus extra crop (0.5 means +50%) when harvested.
const FERTILIZER := {"name": "Fertilizer", "price": 5, "yield_bonus": 0.5}

const CROPS := {
	"maize": {
		"name": "Maize",
		"seed_cost": 20,
		"grow_seconds": 40.0,
		"yield": 4,
		"sell_price": 15,
		"color": Color(0.95, 0.85, 0.2),
		"visual": {
			"archetype": "cereal",
			"stages": [
				{"name": "sprout", "from": 0.0},
				{"name": "young", "from": 0.2},
				{"name": "growing", "from": 0.45},
				{"name": "maturing", "from": 0.75},
				{"name": "ripe", "from": 1.0},
			],
		},
	},
	"beans": {
		"name": "Beans",
		"seed_cost": 12,
		"grow_seconds": 30.0,
		"yield": 3,
		"sell_price": 14,
		"color": Color(0.55, 0.3, 0.15),
		"visual": {
			"archetype": "legume_bush",
			"stages": [
				{"name": "sprout", "from": 0.0},
				{"name": "young", "from": 0.2},
				{"name": "growing", "from": 0.45},
				{"name": "maturing", "from": 0.75},
				{"name": "ripe", "from": 1.0},
			],
		},
	},
}

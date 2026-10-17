extends RefCounted
# Crop catalogue. All numbers live here so they are easy to change.
# grow_seconds is short on purpose for testing.

const CROPS := {
	"maize": {
		"name": "Maize",
		"seed_cost": 20,
		"grow_seconds": 40.0,
		"yield": 4,
		"sell_price": 15,
		"color": Color(0.95, 0.85, 0.2),
	},
	"beans": {
		"name": "Beans",
		"seed_cost": 12,
		"grow_seconds": 30.0,
		"yield": 3,
		"sell_price": 14,
		"color": Color(0.55, 0.3, 0.15),
	},
}

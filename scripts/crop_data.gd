extends RefCounted

# Realistic Multi-Stage Crop Config Data
const CROPS := {
	"maize": {
		"name": "Maize",
		"seed_cost": 20,
		"sell_price": 15,
		"yield": 4,
		"grow_seconds": 40.0,
		"visual": {
			"archetype": "cereal",
			"plants_per_tile": 4,
			"atlas": {"leaf": "maize_leaf", "fruit": "maize_cob"},
			"stages": [
				{"name": "sprout",     "from": 0.00},
				{"name": "vegetative", "from": 0.25},
				{"name": "mature",     "from": 0.60},
				{"name": "ripe",       "from": 1.00}
			]
		}
	},
	"beans": {
		"name": "Beans",
		"seed_cost": 12,
		"sell_price": 14,
		"yield": 3,
		"grow_seconds": 30.0,
		"visual": {
			"archetype": "legume_bush",
			"plants_per_tile": 6,
			"atlas": {"leaf": "bean_leaf", "fruit": "bean_pod"},
			"stages": [
				{"name": "sprout",     "from": 0.00},
				{"name": "vegetative", "from": 0.30},
				{"name": "mature",     "from": 0.70},
				{"name": "ripe",       "from": 1.00}
			]
		}
	}
}

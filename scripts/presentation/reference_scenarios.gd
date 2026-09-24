class_name ReferenceScenarios
extends RefCounted
## ReferenceScenarios
##
## The twelve deterministic commercial reference scenarios required by the M2
## commercial capture boundary. Each scenario has a stable machine-readable
## ID, a human-readable title, and a category identifying which visual moment
## it exercises. The runtime probe stages the game world into the scenario
## and emits a JSON receipt to stdout so tooling can capture, score, or A/B
## the vector versus baked path without playing a full campaign.

const SCENARIO_HEADLIGHT_REVEAL: String = "headlight_reveal"
const SCENARIO_STANDARD_DEFENSE: String = "standard_defense"
const SCENARIO_HEAVY_CANNON: String = "heavy_cannon"
const SCENARIO_FLAK: String = "flak"
const SCENARIO_FOCUS: String = "focus"
const SCENARIO_WARD_SHATTER: String = "ward_shatter"
const SCENARIO_REPAIR: String = "repair"
const SCENARIO_DETACHMENT: String = "detachment"
const SCENARIO_LONGSHADOW_VEIL: String = "longshadow_veil"
const SCENARIO_LONGSHADOW_TETHER: String = "longshadow_tether"
const SCENARIO_LONGSHADOW_CHARGE: String = "longshadow_charge"
const SCENARIO_DAWN: String = "dawn"

const ORDERED_IDS: Array[String] = [
	SCENARIO_HEADLIGHT_REVEAL,
	SCENARIO_STANDARD_DEFENSE,
	SCENARIO_HEAVY_CANNON,
	SCENARIO_FLAK,
	SCENARIO_FOCUS,
	SCENARIO_WARD_SHATTER,
	SCENARIO_REPAIR,
	SCENARIO_DETACHMENT,
	SCENARIO_LONGSHADOW_VEIL,
	SCENARIO_LONGSHADOW_TETHER,
	SCENARIO_LONGSHADOW_CHARGE,
	SCENARIO_DAWN
]

const CATEGORIES: Dictionary = {
	SCENARIO_HEADLIGHT_REVEAL: "world",
	SCENARIO_STANDARD_DEFENSE: "enemies",
	SCENARIO_HEAVY_CANNON: "enemies",
	SCENARIO_FLAK: "enemies",
	SCENARIO_FOCUS: "world",
	SCENARIO_WARD_SHATTER: "enemies",
	SCENARIO_REPAIR: "train",
	SCENARIO_DETACHMENT: "train",
	SCENARIO_LONGSHADOW_VEIL: "longshadow",
	SCENARIO_LONGSHADOW_TETHER: "longshadow",
	SCENARIO_LONGSHADOW_CHARGE: "longshadow",
	SCENARIO_DAWN: "world"
}

const TITLES: Dictionary = {
	SCENARIO_HEADLIGHT_REVEAL: "Headlight reveal of a Pursuer",
	SCENARIO_STANDARD_DEFENSE: "Standard Defense Platform firing",
	SCENARIO_HEAVY_CANNON: "Heavy Cannon recoil and impact",
	SCENARIO_FLAK: "Flak tracking and aerial burst",
	SCENARIO_FOCUS: "Focus charge, compression, contact, and recovery",
	SCENARIO_WARD_SHATTER: "Shadow Ward fracture and shatter",
	SCENARIO_REPAIR: "Workshop repair and train recovery",
	SCENARIO_DETACHMENT: "Real-car coupling break and detachment",
	SCENARIO_LONGSHADOW_VEIL: "Longshadow Veil transformation",
	SCENARIO_LONGSHADOW_TETHER: "Longshadow Tether transformation",
	SCENARIO_LONGSHADOW_CHARGE: "Longshadow Charge transformation",
	SCENARIO_DAWN: "Dawn Beacon arrival and release"
}

const CAPTURE_POINTS: Dictionary = {
	SCENARIO_HEADLIGHT_REVEAL: [
		{"label": "dark", "time": 0.0},
		{"label": "cone_contact", "time": 0.35},
		{"label": "full_reveal", "time": 0.7},
		{"label": "hold", "time": 1.0}
	],
	SCENARIO_STANDARD_DEFENSE: [
		{"label": "anticipation", "time": 0.0},
		{"label": "fire", "time": 0.16},
		{"label": "contact", "time": 0.3},
		{"label": "recovery", "time": 0.58}
	],
	SCENARIO_HEAVY_CANNON: [
		{"label": "anticipation", "time": 0.0},
		{"label": "muzzle", "time": 0.22},
		{"label": "impact", "time": 0.42},
		{"label": "recoil_recovery", "time": 0.82}
	],
	SCENARIO_FLAK: [
		{"label": "tracking", "time": 0.0},
		{"label": "burst", "time": 0.22},
		{"label": "contact", "time": 0.44},
		{"label": "settle", "time": 0.72}
	],
	SCENARIO_FOCUS: [
		{"label": "charge", "time": 0.0},
		{"label": "compression", "time": 0.35},
		{"label": "contact", "time": 0.7},
		{"label": "recovery", "time": 1.15}
	],
	SCENARIO_WARD_SHATTER: [
		{"label": "intact", "time": 0.0},
		{"label": "crack", "time": 0.16},
		{"label": "shatter", "time": 0.32},
		{"label": "fragments", "time": 0.64}
	],
	SCENARIO_REPAIR: [
		{"label": "damaged", "time": 0.0},
		{"label": "tool_contact", "time": 0.25},
		{"label": "restore", "time": 0.55},
		{"label": "settle", "time": 0.9}
	],
	SCENARIO_DETACHMENT: [
		{"label": "coupled", "time": 0.0},
		{"label": "release", "time": 0.12},
		{"label": "separation", "time": 0.4},
		{"label": "clear", "time": 0.9}
	],
	SCENARIO_LONGSHADOW_VEIL: [
		{"label": "pre_entry", "time": 0.0},
		{"label": "form", "time": 0.75},
		{"label": "silhouette", "time": 1.5},
		{"label": "lock", "time": 3.0}
	],
	SCENARIO_LONGSHADOW_TETHER: [
		{"label": "pre_shift", "time": 0.0},
		{"label": "transform_start", "time": 0.25},
		{"label": "midpoint", "time": 1.25},
		{"label": "lock", "time": 2.5}
	],
	SCENARIO_LONGSHADOW_CHARGE: [
		{"label": "pre_shift", "time": 0.0},
		{"label": "transform_start", "time": 0.25},
		{"label": "midpoint", "time": 1.25},
		{"label": "lock", "time": 2.5}
	],
	SCENARIO_DAWN: [
		{"label": "night", "time": 0.0},
		{"label": "first_light", "time": 0.5},
		{"label": "beacon", "time": 1.2},
		{"label": "release", "time": 2.0}
	]
}


static func is_valid(id: String) -> bool:
	return ORDERED_IDS.has(id)


static func category(id: String) -> String:
	return String(CATEGORIES.get(id, "unknown"))


static func title(id: String) -> String:
	return String(TITLES.get(id, ""))


static func capture_points(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for point_variant in CAPTURE_POINTS.get(id, []):
		result.append((point_variant as Dictionary).duplicate(true))
	return result


static func all_receipts_shell() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id_variant in ORDERED_IDS:
		var id: String = id_variant
		result.append({
			"id": id,
			"title": title(id),
			"category": category(id),
			"capture_points": capture_points(id)
		})
	return result

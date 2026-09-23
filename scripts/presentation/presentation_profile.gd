class_name PresentationProfile
extends RefCounted

const AUTO: String = "auto"
const HIGH: String = "high"
const MEDIUM: String = "medium"
const LOW: String = "low"
const VECTOR_FALLBACK: String = "vector_fallback"

const VALID_SETTINGS: Array[String] = [
	AUTO,
	HIGH,
	MEDIUM,
	LOW,
	VECTOR_FALLBACK
]


static func normalize(value: Variant) -> String:
	var requested := String(value).strip_edges().to_lower()
	return requested if requested in VALID_SETTINGS else AUTO


static func resolve(
	configured: Variant,
	touchscreen_available: bool,
	platform_name: String
) -> String:
	var normalized := normalize(configured)
	if normalized != AUTO:
		return normalized
	if touchscreen_available or platform_name in ["Android", "iOS"]:
		return MEDIUM
	return HIGH


static func features(profile_name: Variant) -> Dictionary:
	var profile := normalize(profile_name)
	if profile == AUTO:
		profile = HIGH
	match profile:
		MEDIUM:
			return {
				"baked_art": true,
				"high_resolution_art": true,
				"normal_maps": false,
				"shadow_lights": false,
				"particle_scale": 0.5,
				"parallax_layers": 3,
				"live_3d": false,
				"vector_fallback": false
			}
		LOW:
			return {
				"baked_art": true,
				"high_resolution_art": false,
				"normal_maps": false,
				"shadow_lights": false,
				"particle_scale": 0.25,
				"parallax_layers": 1,
				"live_3d": false,
				"vector_fallback": false
			}
		VECTOR_FALLBACK:
			return {
				"baked_art": false,
				"high_resolution_art": false,
				"normal_maps": false,
				"shadow_lights": false,
				"particle_scale": 0.25,
				"parallax_layers": 1,
				"live_3d": false,
				"vector_fallback": true
			}
		_:
			return {
				"baked_art": true,
				"high_resolution_art": true,
				"normal_maps": true,
				"shadow_lights": true,
				"particle_scale": 1.0,
				"parallax_layers": 4,
				"live_3d": true,
				"vector_fallback": false
			}

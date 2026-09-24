class_name PresentationRouter
extends RefCounted
## PresentationRouter
##
## Decides, per visual category, whether a rendered category should use the
## v0.7 vector fallback path or the new sprite-view placeholder path.
##
## Per-category baked flags default OFF (M2 has no production art). QA can
## enable them independently through environment variables. The
## `vector_fallback` presentation profile always forces every category back to
## the vector renderer. `high`/`medium`/`low` allow baked art per feature
## flags, but M2 keeps them off by default because no atlases exist yet.

const CATEGORY_TRAIN: StringName = &"train"
const CATEGORY_WORLD: StringName = &"world"
const CATEGORY_ENEMIES: StringName = &"enemies"
const CATEGORY_LONGSHADOW: StringName = &"longshadow"
const CATEGORY_EFFECTS: StringName = &"effects"

const ALL_CATEGORIES: Array[StringName] = [
	CATEGORY_TRAIN,
	CATEGORY_WORLD,
	CATEGORY_ENEMIES,
	CATEGORY_LONGSHADOW,
	CATEGORY_EFFECTS
]

const ENV_KEYS: Dictionary = {
	CATEGORY_TRAIN: "LANTERN_BAKED_TRAIN",
	CATEGORY_WORLD: "LANTERN_BAKED_WORLD",
	CATEGORY_ENEMIES: "LANTERN_BAKED_ENEMIES",
	CATEGORY_LONGSHADOW: "LANTERN_BAKED_LONGSHADOW",
	CATEGORY_EFFECTS: "LANTERN_BAKED_EFFECTS"
}

var _profile: String = PresentationProfile.HIGH
var _features: Dictionary = {}
var _forced_off: bool = false
var _category_flags: Dictionary = {
	CATEGORY_TRAIN: false,
	CATEGORY_WORLD: false,
	CATEGORY_ENEMIES: false,
	CATEGORY_LONGSHADOW: false,
	CATEGORY_EFFECTS: false
}


func _init(profile: String = PresentationProfile.HIGH, features: Dictionary = {}) -> void:
	apply_profile(profile, features)


func apply_profile(profile: String, features: Dictionary) -> void:
	_profile = PresentationProfile.normalize(profile)
	_features = features
	_forced_off = (
		_profile == PresentationProfile.VECTOR_FALLBACK
		or not bool(features.get("baked_art", false))
	)
	_apply_environment_overrides()


func set_category_enabled(category: StringName, enabled: bool) -> void:
	if not _category_flags.has(category):
		return
	_category_flags[category] = enabled


func is_category_baked(category: StringName) -> bool:
	if _forced_off:
		return false
	if not _category_flags.has(category):
		return false
	return bool(_category_flags[category])


func is_vector_fallback() -> bool:
	return _profile == PresentationProfile.VECTOR_FALLBACK


func profile() -> String:
	return _profile


func features() -> Dictionary:
	return _features.duplicate(true)


func category_snapshot() -> Dictionary:
	var result: Dictionary = {
		"profile": _profile,
		"vector_fallback": is_vector_fallback(),
		"forced_off": _forced_off
	}
	for category_variant in ALL_CATEGORIES:
		var category: StringName = category_variant
		result[String(category)] = is_category_baked(category)
	return result


func _apply_environment_overrides() -> void:
	if is_vector_fallback():
		for category_variant in ALL_CATEGORIES:
			_category_flags[category_variant] = false
		return
	for category_variant in ALL_CATEGORIES:
		var category: StringName = category_variant
		var env_key: String = String(ENV_KEYS.get(category, ""))
		if env_key.is_empty():
			continue
		if not OS.has_environment(env_key):
			continue
		var raw: String = OS.get_environment(env_key).strip_edges().to_lower()
		if raw in ["1", "true", "on", "yes"]:
			_category_flags[category] = true
		elif raw in ["0", "false", "off", "no"]:
			_category_flags[category] = false

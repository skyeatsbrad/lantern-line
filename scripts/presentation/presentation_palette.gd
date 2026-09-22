class_name PresentationPalette
extends RefCounted

const NIGHT_VOID: Color = Color(0.031, 0.043, 0.067)
const COAL: Color = Color(0.067, 0.09, 0.129)
const IRON: Color = Color(0.125, 0.165, 0.212)
const SLATE: Color = Color(0.208, 0.267, 0.333)
const BONE: Color = Color(0.91, 0.875, 0.776)
const BRASS: Color = Color(0.839, 0.627, 0.31)
const EMBER: Color = Color(0.949, 0.635, 0.298)
const FLAME: Color = Color(0.875, 0.392, 0.22)
const COLD_SIGNAL: Color = Color(0.424, 0.651, 0.776)
const SHADOW_VEIL: Color = Color(0.486, 0.235, 0.471)
const GROWTH: Color = Color(0.494, 0.639, 0.42)
const DANGER: Color = Color(0.941, 0.333, 0.239)
const PURSUER_RUST: Color = Color(0.663, 0.298, 0.267)
const BOARDER_OCHRE: Color = Color(0.722, 0.537, 0.247)
const DRAINER_GLOW: Color = Color(0.365, 0.584, 0.667)

const COLORS: Dictionary = {
	&"night_void": NIGHT_VOID,
	&"coal": COAL,
	&"iron": IRON,
	&"slate": SLATE,
	&"bone": BONE,
	&"brass": BRASS,
	&"ember": EMBER,
	&"flame": FLAME,
	&"cold_signal": COLD_SIGNAL,
	&"shadow_veil": SHADOW_VEIL,
	&"growth": GROWTH,
	&"danger": DANGER,
	&"pursuer_rust": PURSUER_RUST,
	&"boarder_ochre": BOARDER_OCHRE,
	&"drainer_glow": DRAINER_GLOW
}


static func color(token: StringName, high_contrast: bool = false) -> Color:
	var base: Color = COLORS.get(token, BONE)
	if not high_contrast:
		return base
	match token:
		&"night_void":
			return Color(0.008, 0.01, 0.016)
		&"coal":
			return Color(0.025, 0.03, 0.045)
		&"iron":
			return Color(0.14, 0.17, 0.22)
		&"slate":
			return Color(0.32, 0.39, 0.48)
		&"bone":
			return Color.WHITE
		&"brass", &"ember":
			return Color(1.0, 0.82, 0.28)
		&"danger":
			return Color(1.0, 0.27, 0.18)
		&"growth":
			return Color(0.46, 1.0, 0.56)
		&"cold_signal", &"drainer_glow":
			return Color(0.42, 0.86, 1.0)
		&"shadow_veil":
			return Color(0.86, 0.42, 0.86)
		_:
			return base.lightened(0.16)


static func with_alpha(token: StringName, alpha: float, high_contrast: bool = false) -> Color:
	var result: Color = color(token, high_contrast)
	result.a = clampf(alpha, 0.0, 1.0)
	return result


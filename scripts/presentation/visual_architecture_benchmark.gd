class_name VisualArchitectureBenchmark
extends Node2D

const MODE_SPRITE: String = "sprite"
const MODE_HYBRID: String = "hybrid"
const MODE_RUNTIME_3D: String = "runtime_3d"
const VALID_MODES: Array[String] = [
	MODE_SPRITE,
	MODE_HYBRID,
	MODE_RUNTIME_3D
]

var _mode: String = MODE_SPRITE
var _view_size: Vector2 = Vector2(1280.0, 720.0)
var _enemy_count: int = 12
var _boss_active: bool = false
var _elapsed: float = 0.0
var _sprite_movers: Array[Node2D] = []
var _mesh_movers: Array[Node3D] = []
var _flicker_lights_2d: Array[PointLight2D] = []
var _flicker_lights_3d: Array[OmniLight3D] = []
var _texture_cache: Dictionary = {}
var _mesh_cache: Dictionary = {}
var _material_cache: Dictionary = {}


func setup(
	view_size: Vector2,
	mode: String,
	enemy_count: int,
	boss_active: bool
) -> void:
	_view_size = view_size
	_mode = mode if mode in VALID_MODES else MODE_SPRITE
	_enemy_count = clampi(enemy_count, 0, 16)
	_boss_active = boss_active
	match _mode:
		MODE_RUNTIME_3D:
			_build_runtime_3d()
		MODE_HYBRID:
			_build_hybrid()
		_:
			_build_sprite_scene(true)
	_build_effect_overlay()
	set_process(true)


func metadata() -> Dictionary:
	return {
		"mode": _mode,
		"enemy_count": _enemy_count,
		"boss_active": _boss_active,
		"cars": RunState.MAX_SLOT_CAPACITY
	}


func _process(delta: float) -> void:
	_elapsed += delta
	for index in range(_sprite_movers.size()):
		var mover: Node2D = _sprite_movers[index]
		var origin: Vector2 = mover.get_meta("benchmark_origin")
		var phase := _elapsed * (1.8 + float(index % 4) * 0.16)
		mover.position = origin + Vector2(
			sin(phase * 0.37) * 3.0,
			sin(phase) * (2.0 + float(index % 3))
		)
		mover.rotation = sin(phase * 0.73) * 0.015
	for index in range(_mesh_movers.size()):
		var mover: Node3D = _mesh_movers[index]
		var origin: Vector3 = mover.get_meta("benchmark_origin")
		var phase := _elapsed * (1.45 + float(index % 5) * 0.12)
		mover.position = origin + Vector3(
			sin(phase * 0.31) * 0.08,
			sin(phase) * 0.08,
			cos(phase * 0.43) * 0.05
		)
		mover.rotation.y = sin(phase * 0.57) * 0.08
	for index in range(_flicker_lights_2d.size()):
		_flicker_lights_2d[index].energy = (
			0.78 + sin(_elapsed * 4.0 + float(index)) * 0.08
		)
	for index in range(_flicker_lights_3d.size()):
		_flicker_lights_3d[index].omni_range = (
			3.8 + sin(_elapsed * 3.5 + float(index)) * 0.25
		)


func _build_sprite_scene(
	add_background: bool,
	include_boss: bool = true
) -> void:
	if add_background:
		_add_sprite(
			self,
			_solid_texture(
				"sky",
				Vector2i(64, 64),
				PresentationPalette.NIGHT_VOID
			),
			_view_size * 0.5,
			_view_size / 64.0,
			-120
		)
		for index in range(8):
			var haze := _add_sprite(
				self,
				_solid_texture(
					"haze",
					Vector2i(256, 24),
					PresentationPalette.with_alpha(&"slate", 0.16)
				),
				Vector2(
					128.0 + float(index % 4) * 330.0,
					120.0 + float(index / 4) * 135.0
				),
				Vector2.ONE,
				-110
			)
			haze.skew = -0.18
		for index in range(18):
			_add_sprite(
				self,
				_solid_texture(
					"landmark_%d" % (index % 3),
					Vector2i(18 + (index % 3) * 8, 80 + (index % 4) * 28),
					PresentationPalette.IRON.darkened(0.1)
				),
				Vector2(
					40.0 + float(index) * (_view_size.x / 17.0),
					355.0 - float(index % 4) * 14.0
				),
				Vector2.ONE,
				-100
			)
	_build_sprite_rails()
	_build_sprite_train()
	_build_sprite_enemies()
	if _boss_active and include_boss:
		_build_sprite_boss()
	_build_sprite_lights()


func _build_sprite_rails() -> void:
	var rail_texture := _solid_texture(
		"rail",
		Vector2i(1024, 5),
		PresentationPalette.SLATE
	)
	for index in range(4):
		_add_sprite(
			self,
			rail_texture,
			Vector2(_view_size.x * 0.5, 526.0 + float(index) * 14.0),
			Vector2(_view_size.x / 1024.0, 1.0),
			-20
		)
	var tie_texture := _solid_texture(
		"tie",
		Vector2i(12, 54),
		PresentationPalette.IRON
	)
	for index in range(42):
		_add_sprite(
			self,
			tie_texture,
			Vector2(float(index) * 34.0, 548.0),
			Vector2.ONE,
			-21
		).rotation = -0.16


func _build_sprite_train() -> void:
	var body_texture := _solid_texture(
		"car_body",
		Vector2i(118, 54),
		PresentationPalette.IRON
	)
	var roof_texture := _solid_texture(
		"car_roof",
		Vector2i(102, 16),
		PresentationPalette.SLATE
	)
	var trim_texture := _solid_texture(
		"car_trim",
		Vector2i(106, 6),
		PresentationPalette.BRASS
	)
	var window_texture := _solid_texture(
		"car_window",
		Vector2i(16, 14),
		PresentationPalette.EMBER
	)
	var wheel_texture := _radial_texture(
		"wheel",
		24,
		PresentationPalette.COAL,
		PresentationPalette.SLATE
	)
	for index in range(RunState.MAX_SLOT_CAPACITY):
		var car := Node2D.new()
		car.position = Vector2(590.0 - float(index) * 122.0, 492.0)
		car.set_meta("benchmark_origin", car.position)
		add_child(car)
		_sprite_movers.append(car)
		_add_sprite(car, body_texture, Vector2.ZERO, Vector2.ONE, 0)
		_add_sprite(car, roof_texture, Vector2(0.0, -34.0), Vector2.ONE, 1)
		_add_sprite(car, trim_texture, Vector2(0.0, 13.0), Vector2.ONE, 2)
		for window_index in range(4):
			_add_sprite(
				car,
				window_texture,
				Vector2(-34.0 + float(window_index) * 23.0, -7.0),
				Vector2.ONE,
				3
			)
		for wheel_x in [-38.0, 38.0]:
			_add_sprite(
				car,
				wheel_texture,
				Vector2(wheel_x, 34.0),
				Vector2.ONE,
				1
			)


func _build_sprite_enemies() -> void:
	var body_colors: Array[Color] = [
		PresentationPalette.PURSUER_RUST,
		PresentationPalette.BOARDER_OCHRE,
		PresentationPalette.DRAINER_GLOW
	]
	var eye_texture := _radial_texture(
		"enemy_eye",
		12,
		PresentationPalette.EMBER,
		Color.TRANSPARENT
	)
	for index in range(_enemy_count):
		var kind_index := index % body_colors.size()
		var enemy := Node2D.new()
		enemy.position = Vector2(
			720.0 + float(index % 6) * 92.0,
			470.0 - float(index / 6) * 112.0 - float(index % 2) * 28.0
		)
		enemy.set_meta("benchmark_origin", enemy.position)
		add_child(enemy)
		_sprite_movers.append(enemy)
		var aura_texture := _radial_texture(
			"enemy_aura_%d" % kind_index,
			82,
			PresentationPalette.with_alpha(&"shadow_veil", 0.34),
			Color.TRANSPARENT
		)
		var body_texture := _radial_texture(
			"enemy_body_%d" % kind_index,
			52,
			body_colors[kind_index],
			PresentationPalette.COAL
		)
		_add_sprite(enemy, aura_texture, Vector2.ZERO, Vector2.ONE, -1)
		_add_sprite(enemy, body_texture, Vector2.ZERO, Vector2.ONE, 0)
		_add_sprite(enemy, eye_texture, Vector2(11.0, -7.0), Vector2.ONE, 1)
		for limb_index in range(3):
			var limb := _add_sprite(
				enemy,
				_solid_texture(
					"enemy_limb_%d" % kind_index,
					Vector2i(8, 34),
					body_colors[kind_index].darkened(0.22)
				),
				Vector2(-14.0 + float(limb_index) * 14.0, 30.0),
				Vector2.ONE,
				-1
			)
			limb.rotation = -0.28 + float(limb_index) * 0.28


func _build_sprite_boss() -> void:
	var boss := Node2D.new()
	boss.position = Vector2(_view_size.x * 0.78, 285.0)
	boss.set_meta("benchmark_origin", boss.position)
	add_child(boss)
	_sprite_movers.append(boss)
	for index in range(9):
		var radius := 210 - index * 18
		var color := (
			PresentationPalette.with_alpha(&"shadow_veil", 0.2 + index * 0.055)
			if index % 2 == 0
			else PresentationPalette.with_alpha(&"coal", 0.65)
		)
		var layer := _add_sprite(
			boss,
			_radial_texture("boss_%d" % index, radius, color, Color.TRANSPARENT),
			Vector2(sin(float(index)) * 18.0, cos(float(index)) * 11.0),
			Vector2.ONE,
			index
		)
		layer.rotation = float(index) * 0.17
	for eye_x in [-38.0, 38.0]:
		_add_sprite(
			boss,
			_radial_texture(
				"boss_eye",
				22,
				PresentationPalette.DANGER,
				Color.TRANSPARENT
			),
			Vector2(eye_x, -20.0),
			Vector2.ONE,
			12
		)


func _build_sprite_lights() -> void:
	var light_texture := _radial_texture(
		"light_falloff",
		256,
		Color.WHITE,
		Color.TRANSPARENT
	)
	for index in range(4):
		var light := PointLight2D.new()
		light.texture = light_texture
		light.position = Vector2(
			315.0 + float(index) * 245.0,
			420.0 - float(index % 2) * 80.0
		)
		light.color = (
			PresentationPalette.EMBER
			if index < 2
			else PresentationPalette.COLD_SIGNAL
		)
		light.energy = 0.78
		light.texture_scale = 1.5
		light.range_z_min = -50
		light.range_z_max = 50
		add_child(light)
		_flicker_lights_2d.append(light)


func _build_hybrid() -> void:
	_build_3d_viewport(true, 0.5)
	_build_sprite_scene(false, false)


func _build_runtime_3d() -> void:
	_build_3d_viewport(false, 1.0)


func _build_3d_viewport(environment_only: bool, resolution_scale: float) -> void:
	var viewport := SubViewport.new()
	viewport.name = "Benchmark3DViewport"
	viewport.size = Vector2i(
		maxi(320, int(round(_view_size.x * resolution_scale))),
		maxi(180, int(round(_view_size.y * resolution_scale)))
	)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	add_child(viewport)

	var world := Node3D.new()
	world.name = "Benchmark3DWorld"
	viewport.add_child(world)
	_build_3d_environment(world, environment_only)
	if not environment_only:
		_build_3d_train(world)
		_build_3d_enemies(world)
	if _boss_active:
		_build_3d_boss(world)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.8
	camera.position = Vector3(0.6, 7.2, 14.0)
	world.add_child(camera)
	camera.look_at(Vector3(0.6, 0.8, 0.0))
	camera.current = true

	var viewport_sprite := Sprite2D.new()
	viewport_sprite.texture = viewport.get_texture()
	viewport_sprite.position = _view_size * 0.5
	viewport_sprite.scale = Vector2(
		_view_size.x / float(viewport.size.x),
		_view_size.y / float(viewport.size.y)
	)
	viewport_sprite.z_index = -115
	add_child(viewport_sprite)


func _build_3d_environment(world: Node3D, hybrid: bool) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = PresentationPalette.NIGHT_VOID
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = PresentationPalette.COLD_SIGNAL
	environment.ambient_light_energy = 0.28
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	key_light.light_color = PresentationPalette.BONE
	key_light.light_energy = 1.2
	key_light.shadow_enabled = true
	world.add_child(key_light)

	for index in range(3):
		var light := OmniLight3D.new()
		light.position = Vector3(-3.0 + float(index) * 3.2, 2.5, 1.5)
		light.light_color = (
			PresentationPalette.EMBER
			if index < 2
			else PresentationPalette.COLD_SIGNAL
		)
		light.light_energy = 2.3
		light.omni_range = 3.8
		light.shadow_enabled = index == 0 and not hybrid
		world.add_child(light)
		_flicker_lights_3d.append(light)

	_add_box_3d(
		world,
		Vector3(24.0, 0.18, 12.0),
		Vector3(0.0, -0.35, 0.0),
		_material_3d("ground", PresentationPalette.COAL, 0.05, 0.9)
	)
	for rail_z in [-0.72, -0.32, 0.32, 0.72]:
		_add_box_3d(
			world,
			Vector3(18.0, 0.09, 0.08),
			Vector3(-0.5, -0.16, rail_z),
			_material_3d("rail", PresentationPalette.SLATE, 0.8, 0.25)
		)
	for index in range(28):
		_add_box_3d(
			world,
			Vector3(0.08, 0.08, 2.3),
			Vector3(-8.0 + float(index) * 0.62, -0.2, 0.0),
			_material_3d("tie", PresentationPalette.IRON, 0.15, 0.8)
		)
	for index in range(18):
		var height := 1.5 + float(index % 5) * 0.65
		_add_box_3d(
			world,
			Vector3(0.35 + float(index % 3) * 0.12, height, 0.55),
			Vector3(-8.0 + float(index) * 0.92, height * 0.5, -3.4),
			_material_3d(
				"landmark_%d" % (index % 3),
				PresentationPalette.IRON.darkened(0.12),
				0.35,
				0.75
			)
		)


func _build_3d_train(world: Node3D) -> void:
	var body_material := _material_3d(
		"car_body",
		PresentationPalette.IRON,
		0.75,
		0.32
	)
	var roof_material := _material_3d(
		"car_roof",
		PresentationPalette.SLATE,
		0.68,
		0.26
	)
	var wheel_material := _material_3d(
		"wheel",
		PresentationPalette.COAL,
		0.8,
		0.3
	)
	var glow_material := _material_3d(
		"window",
		PresentationPalette.EMBER,
		0.15,
		0.35,
		true
	)
	for index in range(RunState.MAX_SLOT_CAPACITY):
		var car := Node3D.new()
		car.position = Vector3(-3.7 + float(index) * 1.55, 0.58, 0.0)
		car.set_meta("benchmark_origin", car.position)
		world.add_child(car)
		_mesh_movers.append(car)
		_add_box_3d(
			car,
			Vector3(1.38, 0.62, 1.0),
			Vector3.ZERO,
			body_material
		)
		_add_box_3d(
			car,
			Vector3(1.2, 0.22, 0.92),
			Vector3(0.0, 0.42, 0.0),
			roof_material
		)
		for window_x in [-0.42, -0.14, 0.14, 0.42]:
			_add_box_3d(
				car,
				Vector3(0.16, 0.2, 0.04),
				Vector3(window_x, 0.08, 0.52),
				glow_material
			)
		for wheel_x in [-0.45, 0.45]:
			for wheel_z in [-0.51, 0.51]:
				_add_cylinder_3d(
					car,
					0.18,
					0.12,
					Vector3(wheel_x, -0.38, wheel_z),
					Vector3(90.0, 0.0, 0.0),
					wheel_material
				)


func _build_3d_enemies(world: Node3D) -> void:
	var enemy_materials: Array[StandardMaterial3D] = [
		_material_3d(
			"enemy_rust",
			PresentationPalette.PURSUER_RUST,
			0.35,
			0.55
		),
		_material_3d(
			"enemy_ochre",
			PresentationPalette.BOARDER_OCHRE,
			0.25,
			0.62
		),
		_material_3d(
			"enemy_cold",
			PresentationPalette.DRAINER_GLOW,
			0.2,
			0.4
		)
	]
	var eye_material := _material_3d(
		"enemy_eye",
		PresentationPalette.DANGER,
		0.0,
		0.2,
		true
	)
	for index in range(_enemy_count):
		var enemy := Node3D.new()
		enemy.position = Vector3(
			2.2 + float(index % 6) * 0.72,
			0.55 + float(index / 6) * 0.72,
			-1.8 + float(index % 4) * 1.18
		)
		enemy.set_meta("benchmark_origin", enemy.position)
		world.add_child(enemy)
		_mesh_movers.append(enemy)
		var material: StandardMaterial3D = enemy_materials[index % 3]
		_add_sphere_3d(
			enemy,
			0.34,
			Vector3.ZERO,
			Vector3(1.0, 1.45, 0.9),
			material
		)
		_add_sphere_3d(
			enemy,
			0.08,
			Vector3(0.14, 0.08, 0.29),
			Vector3.ONE,
			eye_material
		)
		for limb_index in range(3):
			_add_cylinder_3d(
				enemy,
				0.055,
				0.62,
				Vector3(-0.2 + float(limb_index) * 0.2, -0.42, 0.0),
				Vector3(0.0, 0.0, -15.0 + float(limb_index) * 15.0),
				material
			)


func _build_3d_boss(world: Node3D) -> void:
	var boss := Node3D.new()
	boss.position = Vector3(4.2, 2.4, -1.0)
	boss.set_meta("benchmark_origin", boss.position)
	world.add_child(boss)
	_mesh_movers.append(boss)
	var veil_material := _material_3d(
		"boss_veil",
		PresentationPalette.SHADOW_VEIL,
		0.2,
		0.45,
		true
	)
	var core_material := _material_3d(
		"boss_core",
		PresentationPalette.COAL,
		0.55,
		0.32
	)
	for index in range(10):
		var angle := TAU * float(index) / 10.0
		var lobe := _add_sphere_3d(
			boss,
			0.58 - float(index % 3) * 0.06,
			Vector3(cos(angle) * 0.82, sin(angle) * 0.5, sin(angle) * 0.45),
			Vector3(1.0, 1.3, 0.8),
			veil_material if index % 2 == 0 else core_material
		)
		lobe.rotation = Vector3(angle * 0.25, angle, angle * 0.16)
	_add_sphere_3d(
		boss,
		0.74,
		Vector3.ZERO,
		Vector3(1.0, 1.45, 0.9),
		core_material
	)
	var eye_material := _material_3d(
		"boss_eye",
		PresentationPalette.DANGER,
		0.0,
		0.18,
		true
	)
	for eye_x in [-0.24, 0.24]:
		_add_sphere_3d(
			boss,
			0.11,
			Vector3(eye_x, 0.16, 0.67),
			Vector3.ONE,
			eye_material
		)


func _build_effect_overlay() -> void:
	var spark_texture := _radial_texture(
		"spark",
		18,
		PresentationPalette.EMBER,
		Color.TRANSPARENT
	)
	for index in range(28):
		var spark := _add_sprite(
			self,
			spark_texture,
			Vector2(
				180.0 + float(index % 14) * 78.0,
				410.0 - float(index / 14) * 145.0 - float(index % 3) * 17.0
			),
			Vector2.ONE * (0.55 + float(index % 4) * 0.14),
			80
		)
		spark.set_meta("benchmark_origin", spark.position)
		_sprite_movers.append(spark)


func _add_sprite(
	parent: Node,
	texture: Texture2D,
	position: Vector2,
	scale: Vector2,
	z_index: int
) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = position
	sprite.scale = scale
	sprite.z_index = z_index
	parent.add_child(sprite)
	return sprite


func _solid_texture(key: String, size: Vector2i, color: Color) -> Texture2D:
	var cache_key := "%s:%dx%d:%s" % [
		key,
		size.x,
		size.y,
		color.to_html()
	]
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key] as Texture2D
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	var texture := ImageTexture.create_from_image(image)
	_texture_cache[cache_key] = texture
	return texture


func _radial_texture(
	key: String,
	size: int,
	center_color: Color,
	edge_color: Color
) -> Texture2D:
	var cache_key := "%s:%d:%s:%s" % [
		key,
		size,
		center_color.to_html(),
		edge_color.to_html()
	]
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key] as Texture2D
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(float(size - 1), float(size - 1)) * 0.5
	var radius := maxf(1.0, float(size) * 0.5)
	for y in range(size):
		for x in range(size):
			var ratio := clampf(
				Vector2(float(x), float(y)).distance_to(center) / radius,
				0.0,
				1.0
			)
			image.set_pixel(x, y, center_color.lerp(edge_color, ratio))
	var texture := ImageTexture.create_from_image(image)
	_texture_cache[cache_key] = texture
	return texture


func _material_3d(
	key: String,
	color: Color,
	metallic: float,
	roughness: float,
	emissive: bool = false
) -> StandardMaterial3D:
	if _material_cache.has(key):
		return _material_cache[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.0
	_material_cache[key] = material
	return material


func _add_box_3d(
	parent: Node,
	size: Vector3,
	position: Vector3,
	material: StandardMaterial3D
) -> MeshInstance3D:
	var key := "box_%.3f_%.3f_%.3f" % [size.x, size.y, size.z]
	var mesh: BoxMesh
	if _mesh_cache.has(key):
		mesh = _mesh_cache[key] as BoxMesh
	else:
		mesh = BoxMesh.new()
		mesh.size = size
		_mesh_cache[key] = mesh
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _add_cylinder_3d(
	parent: Node,
	radius: float,
	height: float,
	position: Vector3,
	rotation_degrees: Vector3,
	material: StandardMaterial3D
) -> MeshInstance3D:
	var key := "cylinder_%.3f_%.3f" % [radius, height]
	var mesh: CylinderMesh
	if _mesh_cache.has(key):
		mesh = _mesh_cache[key] as CylinderMesh
	else:
		mesh = CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = 10
		mesh.rings = 1
		_mesh_cache[key] = mesh
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.rotation_degrees = rotation_degrees
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _add_sphere_3d(
	parent: Node,
	radius: float,
	position: Vector3,
	scale: Vector3,
	material: StandardMaterial3D
) -> MeshInstance3D:
	var key := "sphere_%.3f" % radius
	var mesh: SphereMesh
	if _mesh_cache.has(key):
		mesh = _mesh_cache[key] as SphereMesh
	else:
		mesh = SphereMesh.new()
		mesh.radius = radius
		mesh.height = radius * 2.0
		mesh.radial_segments = 12
		mesh.rings = 6
		_mesh_cache[key] = mesh
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.scale = scale
	instance.material_override = material
	parent.add_child(instance)
	return instance

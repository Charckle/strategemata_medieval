extends Node2D

## Client-local cloud-shadow weather. Re-rolls on season change.
## Also hosts the seasonal balloon easter egg (independent of show_weather).
## Rain = world-space MultiMesh streaks. Snow = screen-space CPUParticles2D.

const CLOUD_SCENE := preload("res://weather/clouds_object/cloud_object.tscn")
const BALLOON_SCENE := preload("res://weather/balloon_object/balloon_object.tscn")
const RAIN_TEXTURE := preload("res://weather/sprites/rain.png")
const SPAWN_MARGIN := 400.0
const BALLOON_EDGE_MARGIN := 100.0
## Ongoing spawn rate calibrated at density 90 (3 clouds / 0.45s).
const REF_DENSITY := 90.0
const REF_CLOUDS_PER_SPAWN := 3.0
const SPAWN_INTERVAL := 0.45

## Cloud density range by season (WINTER..AUTUMN). Every season has clouds;
## amount is rolled uniformly in [min, max] inclusive.
const DENSITY_RANGE := {
	0: Vector2i(50, 90),  # winter
	1: Vector2i(10, 40),  # spring
	2: Vector2i(0, 20),   # summer
	3: Vector2i(20, 70),  # autumn
}

## Precip chance by season (only rolls when cloud density > 0).
## Winter uses the same chance but spawns snow instead of rain.
const RAIN_CHANCE := {
	0: 0.30,  # winter (snow)
	1: 0.25,  # spring
	2: 0.05,  # summer
	3: 0.40,  # autumn
}
const RAIN_DENSITY_BUMP := 1.25
const SNOW_DENSITY_BUMP_LIGHT := 1.15
const SNOW_DENSITY_BUMP_STORM := 1.45

const RAIN_MAX_DROPS := 200
const RAIN_TARGET_DROPS := 140
const RAIN_CAMERA_PAD := 360.0
const RAIN_SPAWN_INTERVAL := 0.12
const RAIN_DROPS_PER_BATCH := 20
const RAIN_FALL_SPEED := 300.0
const RAIN_LIFETIME := 1.5

## Snow particle presets (light / storm). Rolled 50/50 each winter precip.
const SNOW_LIGHT := {
	"amount": 140,
	"lifetime": 6.0,
	"velocity_min": 35.0,
	"velocity_max": 70.0,
	"gravity_y": 18.0,
	"spread": 12.0,
	"wind": 0.18,
	"scale_min": 0.12,
	"scale_max": 0.32,
}
const SNOW_STORM := {
	"amount": 320,
	"lifetime": 3.8,
	"velocity_min": 90.0,
	"velocity_max": 170.0,
	"gravity_y": 55.0,
	"spread": 28.0,
	"wind": 0.55,
	"scale_min": 0.16,
	"scale_max": 0.42,
}

## Balloon spawn chance each season (deterministic roll).
const BALLOON_CHANCE := 0.01

@onready var _cloud_timer: Timer = $cloud_Timer

var map_root: Node2D
var weather_objects: Node2D
var _camera: Camera2D

var cloud_create_x: float = 0.0
var cloud_destroy_x: float = 0.0
var cloud_create_y_min: float = 0.0
var cloud_create_y_max: float = 0.0
var map_rect: Rect2 = Rect2()

var current_mode: String = "sunny"  # "sunny" | "clouds"
var _density: int = 0
var _spawn_accum: float = 0.0
var _bounds_ready := false
var _weather_was_visible := true
var _cloud_timer_was_running := false
var _balloon: Node2D = null

# --- Rain (world-space MultiMesh) ---
var rain_is_active := false
var rain_was_active := false
var precip_is_snow := false
var precip_is_storm := false
var rain_direction := Vector2(0.15, 1.0).normalized()
var rain_positions := PackedVector2Array()
var rain_speeds := PackedFloat32Array()
var rain_lifetimes := PackedFloat32Array()
var rain_active_count := 0
var rain_spawn_accumulator := 0.0
var rain_multi_mesh_instance: MultiMeshInstance2D

# --- Snow (screen-space CPUParticles2D on CanvasLayer) ---
var _snow_canvas: CanvasLayer
var _snow_particles: CPUParticles2D
var _snow_flake_tex: Texture2D
var _snow_wind_x := 0.2
var _snow_base_scale_min := 0.12
var _snow_base_scale_max := 0.32
var _last_snow_view_size := Vector2.ZERO
var _last_snow_zoom := -1.0


func _ready() -> void:
	map_root = get_parent() as Node2D
	weather_objects = map_root.get_node_or_null("weather_objects") as Node2D
	_camera = map_root.get_node_or_null("Camera2D") as Camera2D
	_cloud_timer.wait_time = SPAWN_INTERVAL
	_cloud_timer.one_shot = false
	_weather_was_visible = _is_weather_enabled()
	_setup_rain_multimesh()
	_setup_snow_particles()


func _process(delta: float) -> void:
	var weather_visible := _is_weather_enabled()

	if not weather_visible and _weather_was_visible:
		_cloud_timer_was_running = not _cloud_timer.is_stopped()
		rain_was_active = rain_is_active
		if _cloud_timer_was_running:
			_cloud_timer.stop()
		_clear_clouds()
		_stop_precip_visuals()
		if weather_objects != null:
			weather_objects.visible = false

	if weather_visible and not _weather_was_visible:
		if weather_objects != null:
			weather_objects.visible = true
		if current_mode == "clouds" and _density > 0:
			_start_clouds(true)
		if rain_was_active:
			rain_is_active = true
			_start_precip_visuals()

	_weather_was_visible = weather_visible

	if weather_visible and rain_is_active and not precip_is_snow:
		_process_rain(delta)
	elif weather_visible and rain_is_active and precip_is_snow:
		_layout_snow_emitter_if_needed()


func setup_and_roll(season: int) -> void:
	_compute_map_bounds()
	roll_weather_for_season(season)


func roll_weather_for_season(season: int) -> void:
	if not _bounds_ready:
		_compute_map_bounds()
	_clear_clouds()
	_cloud_timer.stop()
	_stop_precip_visuals()
	rain_is_active = false
	precip_is_snow = false
	precip_is_storm = false

	# Balloon is independent of the weather toggle; always re-roll on season change.
	roll_balloon_for_season()

	if not _is_weather_enabled():
		current_mode = "sunny"
		_density = 0
		return

	_density = _roll_density(int(season))
	if _density > 0:
		var rain_chance: float = float(RAIN_CHANCE.get(int(season), 0.1))
		if randf() < rain_chance:
			rain_is_active = true
			precip_is_snow = int(season) == 0
			if precip_is_snow:
				precip_is_storm = randf() < 0.5
				var bump: float = SNOW_DENSITY_BUMP_STORM if precip_is_storm else SNOW_DENSITY_BUMP_LIGHT
				_density = clampi(int(ceil(float(_density) * bump)), 1, 120)
				_snow_wind_x = (-1.0 if randf() < 0.5 else 1.0) * randf_range(
					0.12 if not precip_is_storm else 0.35,
					0.3 if not precip_is_storm else 0.7
				)
			else:
				_density = clampi(int(ceil(float(_density) * RAIN_DENSITY_BUMP)), 1, 120)
				_roll_rain_wind()
		current_mode = "clouds"
		_start_clouds(true)
		if rain_is_active:
			_start_precip_visuals()
	else:
		current_mode = "sunny"


func roll_balloon_for_season() -> void:
	_clear_balloon()
	if not _bounds_ready:
		_compute_map_bounds()
	if not _bounds_ready or map_root == null:
		return

	# Seed from turn only — season is always turn%4, so XOR-ing both cancels out.
	var turn := int(map_root.turn)
	var base_seed := hash(turn) ^ 0x42414C4C  # "BALL"
	var rng := RandomNumberGenerator.new()
	rng.seed = base_seed
	if rng.randf() >= BALLOON_CHANCE:
		return

	var instance := BALLOON_SCENE.instantiate()
	map_root.add_child(instance)
	# Derived seed so path samples don't depend on the chance draw.
	instance.setup(map_rect, BALLOON_EDGE_MARGIN, hash(turn) ^ 0x50415448)  # "PATH"
	_balloon = instance
	instance.tree_exiting.connect(_on_balloon_exiting)


func _on_balloon_exiting() -> void:
	_balloon = null


func _clear_balloon() -> void:
	if _balloon != null and is_instance_valid(_balloon):
		if _balloon.tree_exiting.is_connected(_on_balloon_exiting):
			_balloon.tree_exiting.disconnect(_on_balloon_exiting)
		_balloon.queue_free()
	_balloon = null


func _roll_density(season: int) -> int:
	var range_v: Vector2i = DENSITY_RANGE.get(season, Vector2i(20, 50))
	return randi_range(range_v.x, range_v.y)


func _start_clouds(fill_map: bool) -> void:
	if weather_objects == null or not _bounds_ready or _density <= 0:
		return
	_spawn_accum = 0.0
	if fill_map:
		for _i in range(_density):
			create_cloud(true)
	_cloud_timer.start()


func create_cloud(all_map: bool = false) -> void:
	if weather_objects == null or not _bounds_ready:
		return
	var instance := CLOUD_SCENE.instantiate()
	var start_y := randf_range(cloud_create_y_min, cloud_create_y_max)
	var x_spawn := cloud_create_x
	if all_map:
		x_spawn = randf_range(cloud_create_x, cloud_destroy_x)
	instance.position = Vector2(x_spawn, start_y)
	instance.position_x_todestroy_itself = cloud_destroy_x
	weather_objects.add_child(instance)


func _on_cloud_timer_timeout() -> void:
	if current_mode != "clouds" or not _is_weather_enabled() or _density <= 0:
		return
	# Scale edge spawn rate with density so summer stays thin and winter stays thick.
	_spawn_accum += REF_CLOUDS_PER_SPAWN * (float(_density) / REF_DENSITY)
	while _spawn_accum >= 1.0:
		_spawn_accum -= 1.0
		create_cloud(false)


func _clear_clouds() -> void:
	if weather_objects == null:
		return
	for child in weather_objects.get_children():
		if child == rain_multi_mesh_instance:
			continue
		child.queue_free()


func _is_weather_enabled() -> bool:
	return int(GlobalSet.settings.get("show_weather", 1)) != 0


func _start_precip_visuals() -> void:
	if precip_is_snow:
		_stop_rain_visuals()
		_start_snow_particles()
	else:
		_stop_snow_particles()
		_ensure_rain_multimesh_parented()
		_fill_rain_in_pad()


func _stop_precip_visuals() -> void:
	_stop_rain_visuals()
	_stop_snow_particles()


# --- Snow (CPUParticles2D) --------------------------------------------------

func _make_soft_flake_texture() -> Texture2D:
	var size := 12
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2((size - 1) * 0.5, (size - 1) * 0.5)
	var r := size * 0.45
	for y in range(size):
		for x in range(size):
			var d := Vector2(x, y).distance_to(c) / r
			if d <= 1.0:
				var a := clampf(1.0 - d * d, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _snow_host() -> Node:
	if map_root != null and is_instance_valid(map_root) and map_root.is_inside_tree():
		return map_root
	if is_inside_tree():
		var scene := get_tree().current_scene
		if scene != null and is_instance_valid(scene):
			return scene
		return get_tree().root
	return self


func _ensure_snow_canvas_hosted() -> void:
	if _snow_canvas == null or not is_instance_valid(_snow_canvas):
		_snow_canvas = CanvasLayer.new()
		_snow_canvas.name = "SnowOverlay"
		_snow_canvas.visible = false
	# Below BasebottomGUI (default CanvasLayer layer 1).
	_snow_canvas.layer = 0
	var host := _snow_host()
	if _snow_canvas.get_parent() != host:
		if _snow_canvas.get_parent() != null:
			_snow_canvas.get_parent().remove_child(_snow_canvas)
		host.add_child(_snow_canvas)
	# If we somehow still aren't in-tree, fall back to the root viewport.
	if not _snow_canvas.is_inside_tree() and is_inside_tree():
		if _snow_canvas.get_parent() != null:
			_snow_canvas.get_parent().remove_child(_snow_canvas)
		get_tree().root.add_child(_snow_canvas)


func _setup_snow_particles() -> void:
	if _snow_flake_tex == null:
		_snow_flake_tex = _make_soft_flake_texture()

	_ensure_snow_canvas_hosted()

	if _snow_particles == null or not is_instance_valid(_snow_particles):
		_snow_particles = CPUParticles2D.new()
		_snow_particles.name = "SnowParticles"
		_snow_particles.texture = _snow_flake_tex
		_snow_particles.emitting = false
		_snow_particles.one_shot = false
		_snow_particles.explosiveness = 0.0
		_snow_particles.randomness = 0.65
		_snow_particles.local_coords = true
		_snow_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		_snow_particles.direction = Vector2(0.2, 1.0)
		_snow_particles.spread = 15.0
		_snow_particles.gravity = Vector2(0, 25)
		_snow_particles.color = Color(1, 1, 1, 0.95)
		_snow_particles.z_index = 10
		_snow_canvas.add_child(_snow_particles)


func _start_snow_particles() -> void:
	_setup_snow_particles()
	_ensure_snow_canvas_hosted()
	var preset: Dictionary = SNOW_STORM if precip_is_storm else SNOW_LIGHT
	_snow_particles.amount = int(preset["amount"])
	_snow_particles.lifetime = float(preset["lifetime"])
	_snow_particles.preprocess = float(preset["lifetime"]) * 0.85
	_snow_particles.speed_scale = 1.0
	_snow_particles.initial_velocity_min = float(preset["velocity_min"])
	_snow_particles.initial_velocity_max = float(preset["velocity_max"])
	_snow_particles.gravity = Vector2(0.0, float(preset["gravity_y"]))
	_snow_particles.spread = float(preset["spread"])
	_snow_base_scale_min = float(preset["scale_min"])
	_snow_base_scale_max = float(preset["scale_max"])
	_snow_particles.scale_amount_min = _snow_base_scale_min
	_snow_particles.scale_amount_max = _snow_base_scale_max
	_snow_particles.direction = Vector2(_snow_wind_x, 1.0).normalized()
	_snow_particles.angular_velocity_min = -40.0
	_snow_particles.angular_velocity_max = 40.0
	_last_snow_zoom = -1.0
	_layout_snow_emitter()
	_snow_canvas.visible = true
	_snow_particles.emitting = true
	_snow_particles.restart()


func _stop_snow_particles() -> void:
	if _snow_particles != null and is_instance_valid(_snow_particles):
		_snow_particles.emitting = false
	if _snow_canvas != null and is_instance_valid(_snow_canvas):
		_snow_canvas.visible = false
	_last_snow_view_size = Vector2.ZERO


func _camera_zoom_factor() -> float:
	if _camera == null or not is_instance_valid(_camera):
		if map_root != null:
			_camera = map_root.get_node_or_null("Camera2D") as Camera2D
	if _camera == null:
		return 1.0
	return maxf(_camera.zoom.x, 0.05)


func _layout_snow_emitter_if_needed() -> void:
	var view := get_viewport().get_visible_rect().size
	var zoom := _camera_zoom_factor()
	if view != _last_snow_view_size or not is_equal_approx(zoom, _last_snow_zoom):
		_layout_snow_emitter()


func _layout_snow_emitter() -> void:
	if _snow_particles == null or not is_instance_valid(_snow_particles):
		return
	var view := get_viewport().get_visible_rect().size
	if view.x <= 1.0 or view.y <= 1.0:
		return
	var zoom := _camera_zoom_factor()
	_last_snow_view_size = view
	_last_snow_zoom = zoom
	# Screen-space emitter; node scale tracks camera zoom so flakes grow/shrink with it.
	# Compensate emission extents so coverage stays full-screen after scaling.
	_snow_particles.position = view * 0.5
	_snow_particles.scale = Vector2(zoom, zoom)
	_snow_particles.emission_rect_extents = (view * 0.5 + Vector2(40, 40)) / zoom
	# Keep per-particle size in the tuned range; zoom is applied via node scale.
	_snow_particles.scale_amount_min = _snow_base_scale_min
	_snow_particles.scale_amount_max = _snow_base_scale_max


# --- Rain -------------------------------------------------------------------

func _setup_rain_multimesh() -> void:
	rain_positions.resize(RAIN_MAX_DROPS)
	rain_speeds.resize(RAIN_MAX_DROPS)
	rain_lifetimes.resize(RAIN_MAX_DROPS)

	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_2D
	multi_mesh.instance_count = RAIN_MAX_DROPS
	multi_mesh.visible_instance_count = 0

	var tex_size := RAIN_TEXTURE.get_size()
	var quad := QuadMesh.new()
	quad.size = tex_size
	multi_mesh.mesh = quad

	rain_multi_mesh_instance = MultiMeshInstance2D.new()
	rain_multi_mesh_instance.name = "RainMultiMesh"
	rain_multi_mesh_instance.multimesh = multi_mesh
	rain_multi_mesh_instance.texture = RAIN_TEXTURE
	rain_multi_mesh_instance.z_index = 500
	_ensure_rain_multimesh_parented()


func _ensure_rain_multimesh_parented() -> void:
	if rain_multi_mesh_instance == null:
		return
	if weather_objects == null and map_root != null:
		weather_objects = map_root.get_node_or_null("weather_objects") as Node2D
	if weather_objects == null:
		return
	if rain_multi_mesh_instance.get_parent() != weather_objects:
		var parent := rain_multi_mesh_instance.get_parent()
		if parent != null:
			parent.remove_child(rain_multi_mesh_instance)
		weather_objects.add_child(rain_multi_mesh_instance)


func _roll_rain_wind() -> void:
	var wind_x := -1.0 if randf() < 0.5 else 1.0
	var wind_strength := randf_range(0.05, 0.35)
	rain_direction = Vector2(wind_x * wind_strength, 1.0).normalized()


func _stop_rain_visuals() -> void:
	rain_active_count = 0
	rain_spawn_accumulator = 0.0
	if rain_multi_mesh_instance != null and is_instance_valid(rain_multi_mesh_instance):
		rain_multi_mesh_instance.multimesh.visible_instance_count = 0


func _fill_rain_in_pad() -> void:
	_stop_rain_visuals()
	if rain_multi_mesh_instance == null:
		_setup_rain_multimesh()
	var pad := _camera_pad_rect()
	if pad.size.x <= 0.0 or pad.size.y <= 0.0:
		return
	for _i in range(RAIN_TARGET_DROPS):
		_spawn_rain_drop(pad)
	_sync_rain_transforms()


func _process_rain(delta: float) -> void:
	if rain_multi_mesh_instance == null or not is_instance_valid(rain_multi_mesh_instance):
		return
	var pad := _camera_pad_rect()

	rain_spawn_accumulator += delta
	while rain_spawn_accumulator >= RAIN_SPAWN_INTERVAL:
		rain_spawn_accumulator -= RAIN_SPAWN_INTERVAL
		if rain_active_count < RAIN_TARGET_DROPS:
			for _j in range(RAIN_DROPS_PER_BATCH):
				if rain_active_count >= RAIN_TARGET_DROPS:
					break
				_spawn_rain_drop(pad)

	var i := 0
	while i < rain_active_count:
		rain_lifetimes[i] -= delta
		rain_positions[i] += rain_direction * rain_speeds[i] * delta
		if rain_lifetimes[i] <= 0.0 or not pad.has_point(rain_positions[i]):
			rain_active_count -= 1
			rain_positions[i] = rain_positions[rain_active_count]
			rain_speeds[i] = rain_speeds[rain_active_count]
			rain_lifetimes[i] = rain_lifetimes[rain_active_count]
			continue
		i += 1

	_sync_rain_transforms()


func _sync_rain_transforms() -> void:
	var mm := rain_multi_mesh_instance.multimesh
	for i in range(rain_active_count):
		mm.set_instance_transform_2d(i, Transform2D(0.0, rain_positions[i]))
	mm.visible_instance_count = rain_active_count


func _spawn_rain_drop(pad: Rect2) -> void:
	if rain_active_count >= RAIN_MAX_DROPS:
		return
	if pad.size.x <= 0.0 or pad.size.y <= 0.0:
		return
	var idx := rain_active_count
	rain_positions[idx] = Vector2(
		randf_range(pad.position.x, pad.position.x + pad.size.x),
		randf_range(pad.position.y, pad.position.y + pad.size.y)
	)
	rain_speeds[idx] = RAIN_FALL_SPEED + randf_range(-30.0, 30.0)
	rain_lifetimes[idx] = RAIN_LIFETIME
	rain_active_count += 1


func _camera_pad_rect() -> Rect2:
	if _camera == null or not is_instance_valid(_camera):
		if map_root != null:
			_camera = map_root.get_node_or_null("Camera2D") as Camera2D
	if _camera == null:
		return Rect2()
	var view_size := get_viewport().get_visible_rect().size
	var zoom := _camera.zoom
	if zoom.x == 0.0 or zoom.y == 0.0:
		return Rect2()
	var world_size := Vector2(view_size.x / zoom.x, view_size.y / zoom.y)
	var center := _camera.get_screen_center_position()
	var rect := Rect2(center - world_size * 0.5, world_size)
	return rect.grow(RAIN_CAMERA_PAD)


func _compute_map_bounds() -> void:
	if map_root == null:
		map_root = get_parent() as Node2D
	if weather_objects == null and map_root != null:
		weather_objects = map_root.get_node_or_null("weather_objects") as Node2D
	if _camera == null and map_root != null:
		_camera = map_root.get_node_or_null("Camera2D") as Camera2D

	var ml: TileMapLayer = null
	if map_root != null and map_root.get("pathfinding") != null:
		ml = map_root.pathfinding.map_layer as TileMapLayer
	if ml == null and map_root != null:
		var tilemap := map_root.get_node_or_null("tilemap")
		if tilemap != null:
			for child in tilemap.get_children():
				if child is TileMapLayer and child.tile_set != null and child.name != "roads":
					ml = child as TileMapLayer
					break

	if ml == null:
		_bounds_ready = false
		return

	var used := ml.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		_bounds_ready = false
		return

	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	var corners: Array[Vector2i] = [
		used.position,
		used.position + Vector2i(used.size.x - 1, 0),
		used.position + Vector2i(0, used.size.y - 1),
		used.position + Vector2i(used.size.x - 1, used.size.y - 1),
	]
	for cell in corners:
		var world: Vector2 = ml.to_global(ml.map_to_local(cell))
		min_x = minf(min_x, world.x)
		max_x = maxf(max_x, world.x)
		min_y = minf(min_y, world.y)
		max_y = maxf(max_y, world.y)

	cloud_create_x = min_x - SPAWN_MARGIN
	cloud_destroy_x = max_x + SPAWN_MARGIN
	cloud_create_y_min = min_y
	cloud_create_y_max = max_y
	map_rect = Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
	_bounds_ready = true

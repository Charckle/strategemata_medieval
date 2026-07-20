extends Node2D

## Client-local cloud-shadow weather. Re-rolls on season change.
## Also hosts the seasonal balloon easter egg (independent of show_weather).

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

## Rain chance by season (only rolls when cloud density > 0).
const RAIN_CHANCE := {
	0: 0.30,  # winter
	1: 0.25,  # spring
	2: 0.05,  # summer
	3: 0.40,  # autumn
}
const RAIN_DENSITY_BUMP := 1.25

const RAIN_MAX_DROPS := 200
const RAIN_TARGET_DROPS := 140
const RAIN_CAMERA_PAD := 360.0
const RAIN_SPAWN_INTERVAL := 0.12
const RAIN_DROPS_PER_BATCH := 20
const RAIN_FALL_SPEED := 300.0
const RAIN_LIFETIME := 1.5

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

# --- Rain (world-space MultiMesh, camera-padded) ---
var rain_is_active := false
var rain_was_active := false
var rain_direction := Vector2(0.15, 1.0).normalized()
var rain_positions := PackedVector2Array()
var rain_speeds := PackedFloat32Array()
var rain_lifetimes := PackedFloat32Array()
var rain_active_count := 0
var rain_spawn_accumulator := 0.0
var rain_multi_mesh_instance: MultiMeshInstance2D


func _ready() -> void:
	map_root = get_parent() as Node2D
	weather_objects = map_root.get_node_or_null("weather_objects") as Node2D
	_camera = map_root.get_node_or_null("Camera2D") as Camera2D
	_cloud_timer.wait_time = SPAWN_INTERVAL
	_cloud_timer.one_shot = false
	_weather_was_visible = _is_weather_enabled()
	_setup_rain_multimesh()


func _process(delta: float) -> void:
	var weather_visible := _is_weather_enabled()

	if not weather_visible and _weather_was_visible:
		_cloud_timer_was_running = not _cloud_timer.is_stopped()
		rain_was_active = rain_is_active
		if _cloud_timer_was_running:
			_cloud_timer.stop()
		_clear_clouds()
		_stop_rain_visuals()
		if weather_objects != null:
			weather_objects.visible = false

	if weather_visible and not _weather_was_visible:
		if weather_objects != null:
			weather_objects.visible = true
		if current_mode == "clouds" and _density > 0:
			_start_clouds(true)
		if rain_was_active:
			rain_is_active = true
			_fill_rain_in_pad()

	_weather_was_visible = weather_visible

	if weather_visible and rain_is_active:
		_process_rain(delta)


func setup_and_roll(season: int) -> void:
	_compute_map_bounds()
	roll_weather_for_season(season)


func roll_weather_for_season(season: int) -> void:
	if not _bounds_ready:
		_compute_map_bounds()
	_clear_clouds()
	_cloud_timer.stop()
	_stop_rain_visuals()
	rain_is_active = false

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
			_density = clampi(int(ceil(float(_density) * RAIN_DENSITY_BUMP)), 1, 120)
			_roll_rain_wind()
		current_mode = "clouds"
		_start_clouds(true)
		if rain_is_active:
			_fill_rain_in_pad()
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
	if weather_objects != null:
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


func _process_rain(delta: float) -> void:
	if rain_multi_mesh_instance == null or not is_instance_valid(rain_multi_mesh_instance):
		return
	var mm := rain_multi_mesh_instance.multimesh
	var pad := _camera_pad_rect()

	# Spawn into the pad so newly revealed areas fill as the camera pans.
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
		# Despawn when lifetime ends or the drop leaves the padded view (world-space).
		if rain_lifetimes[i] <= 0.0 or not pad.has_point(rain_positions[i]):
			rain_active_count -= 1
			rain_positions[i] = rain_positions[rain_active_count]
			rain_speeds[i] = rain_speeds[rain_active_count]
			rain_lifetimes[i] = rain_lifetimes[rain_active_count]
			continue
		mm.set_instance_transform_2d(i, Transform2D(0.0, rain_positions[i]))
		i += 1

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

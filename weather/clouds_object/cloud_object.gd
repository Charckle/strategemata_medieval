extends Node2D

var position_x_todestroy_itself: float = 0.0

var speed := 19.5
var speed_multiplier := 0.0
## World-size multiplier relative to the source sprite (1.0 = native).
const WORLD_SCALE := 0.25

var shadow: Sprite2D

var cloud_sprites: Array[Texture2D] = [
	preload("res://weather/sprites/oblak_01.png"),
	preload("res://weather/sprites/oblak_02.png"),
	preload("res://weather/sprites/oblak_03.png"),
	preload("res://weather/sprites/oblak_04.png"),
	preload("res://weather/sprites/oblak_05.png"),
	preload("res://weather/sprites/oblak_06.png"),
	preload("res://weather/sprites/oblak_07.png"),
]


func _ready() -> void:
	speed_multiplier = randf_range(-9.75, 9.75)
	var chosen_texture: Texture2D = cloud_sprites[randi() % cloud_sprites.size()]
	$cloud.texture = chosen_texture
	$cloud.visible = false  # Shadows only; render via the viewport.

	shadow = Sprite2D.new()
	shadow.texture = chosen_texture
	shadow.material = load("res://weather/shaders/black_shadow.tres")
	# Hide until positioned — otherwise it flashes at (0,0) / viewport corner.
	shadow.visible = false

	var map_root := get_parent().get_parent()
	var viewport := map_root.get_node_or_null("CloudShadowsViewport")
	if viewport != null:
		viewport.add_child(shadow)
		_sync_shadow()
		shadow.visible = true


func _exit_tree() -> void:
	if shadow != null and is_instance_valid(shadow):
		shadow.queue_free()


func _process(delta: float) -> void:
	position.x += (speed + speed_multiplier) * delta
	_sync_shadow()

	if position.x > position_x_todestroy_itself:
		queue_free()


func _sync_shadow() -> void:
	if shadow == null or not is_instance_valid(shadow):
		return
	# Project world → screen, and scale by zoom so cloud world-size stays fixed
	# (zoom in → larger on screen, zoom out → smaller).
	var canvas_transform := get_viewport().get_canvas_transform()
	shadow.position = canvas_transform * global_position
	var cam := get_viewport().get_camera_2d()
	var zoom := cam.zoom if cam != null else Vector2.ONE
	shadow.scale = zoom * WORLD_SCALE

extends Sprite2D

# Called by the settlement's setup_building(); do not set color in _ready().


@export_range(0.0, 0.3) var wave_amplitude: float = 0.15
@export_range(0.0, 30.0) var wave_frequency: float = 5.0
@export_range(0.0, 10.0) var wave_speed: float = 4.0

var _shader_res := preload("res://shaders/flag_wave/flag_wave.gdshader")


func _color_from_rgb(r: int, g: int, b: int) -> Vector4:
	return Vector4(r / 255.0, g / 255.0, b / 255.0, 1.0)


func _set_flag_color_rgb(r: int, g: int, b: int) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = _shader_res
	mat.set_shader_parameter("transparentColor", _color_from_rgb(255, 0, 255))
	mat.set_shader_parameter("useTransparentColor", true)
	mat.set_shader_parameter("replaceColor", _color_from_rgb(255, 255, 0))
	mat.set_shader_parameter("withColor", _color_from_rgb(r, g, b))
	mat.set_shader_parameter("wave_amplitude", wave_amplitude)
	mat.set_shader_parameter("wave_frequency", wave_frequency)
	mat.set_shader_parameter("wave_speed", wave_speed)
	material = mat

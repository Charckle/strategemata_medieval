shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(1.0, 0.9, 0.2, 1.0);
uniform float outline_width : hint_range(0.0, 5.0) = 1.0;
uniform float outline_threshold : hint_range(0.0, 1.0) = 0.1;

void fragment() {
	vec2 ps = TEXTURE_PIXEL_SIZE;
	float a = texture(TEXTURE, UV).a;
	float outline = 0.0;
	outline += step(outline_threshold, texture(TEXTURE, UV + vec2( outline_width * ps.x, 0.0)).a);
	outline += step(outline_threshold, texture(TEXTURE, UV + vec2(-outline_width * ps.x, 0.0)).a);
	outline += step(outline_threshold, texture(TEXTURE, UV + vec2(0.0,  outline_width * ps.y)).a);
	outline += step(outline_threshold, texture(TEXTURE, UV + vec2(0.0, -outline_width * ps.y)).a);
	outline = min(outline, 1.0);

	vec4 col = texture(TEXTURE, UV);
	if (outline > 0.0 && a < outline_threshold) {
		COLOR = outline_color;
	} else {
		COLOR = col;
	}
}

shader_type canvas_item;
// 受击闪白 + 霸体金边。
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 outline_color : source_color = vec4(1.0, 0.85, 0.2, 1.0);
uniform float outline = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (outline > 0.5 && c.a < 0.5) {
		vec2 px = TEXTURE_PIXEL_SIZE;
		float a = texture(TEXTURE, UV + vec2(px.x, 0.0)).a + texture(TEXTURE, UV - vec2(px.x, 0.0)).a
			+ texture(TEXTURE, UV + vec2(0.0, px.y)).a + texture(TEXTURE, UV - vec2(0.0, px.y)).a;
		if (a > 0.5) {
			c = outline_color;
		}
	}
	c.rgb = mix(c.rgb, vec3(1.0), flash * c.a);
	COLOR = c * COLOR;
}

// Control-room glass over a picture: pulls the scene toward the terminal's
// low-light palette, then lays monitor scanlines and a soft vignette on top.
// It reads the screen behind it, so whatever is drawn underneath (map,
// region scene) is treated alike without touching its own palette.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float desaturate : hint_range(0.0, 1.0) = 0.45;
uniform float dim : hint_range(0.0, 1.0) = 0.72;
uniform float scanline : hint_range(0.0, 1.0) = 0.22;
uniform float vignette : hint_range(0.0, 1.0) = 0.35;
uniform vec3 tint = vec3(0.96, 0.93, 0.84);

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l) * tint, desaturate) * dim;
	// One dark row in three, at screen pixels so it never shimmers on resize.
	float row = mod(floor(FRAGCOORD.y), 3.0);
	c *= row < 1.0 ? 1.0 - scanline : 1.0;
	vec2 d = UV - 0.5;
	c *= 1.0 - vignette * dot(d, d) * 2.0;
	COLOR = vec4(c, 1.0);
}

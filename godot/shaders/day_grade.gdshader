// Grades the night-painted city into day, over the finished frame (it reads
// the screen, so lamps, haze and overlays are graded together). The scene is
// authored at night; by day dark surfaces lift, the night sky opens into a
// pale day sky, distant ridges turn hazy blue, and warm window and lamp
// light fades into daylight.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float daylight = 0.0;
uniform sampler2D sky_mask : filter_nearest;   // per scene column: sky bottom / height
uniform float horizon_v = 0.5;   // scene-relative y of the horizon
uniform float water_v = 2.0;   // scene-relative y where water begins
uniform vec4 scene_rect = vec4(0.0, 0.0, 1.0, 1.0);   // the scene inside this rect, in UV

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 day = clamp(c * 1.9 + 0.035, 0.0, 1.0);
	vec2 sp = (UV - scene_rect.xy) / scene_rect.zw;
	float bottom = texture(sky_mask, vec2(sp.x, 0.5)).r;
	float sky = step(sp.y, bottom - 0.004);
	// Day sky, paler toward the horizon; cloud and moon keep some shape.
	vec3 sky_col = mix(vec3(0.36, 0.53, 0.74), vec3(0.72, 0.79, 0.84), clamp(sp.y / horizon_v, 0.0, 1.0));
	day = mix(day, sky_col + (c - vec3(0.06, 0.07, 0.12)) * 0.8, sky);
	if (sp.y > water_v) {
		day = mix(day, vec3(0.22, 0.36, 0.48) + (c - vec3(0.03, 0.06, 0.10)) * 1.2, 0.85);
	}
	float glow = step(0.6, l) * step(c.b + 0.25, c.r);
	day = mix(day, vec3(0.42, 0.40, 0.36), glow * 0.7);
	// Soft shoulder: the lift brightens shadows, never blows pale walls to white.
	float peak = max(day.r, max(day.g, day.b));
	day *= mix(1.0, 0.84 / max(peak, 0.001), smoothstep(0.7, 1.0, peak));
	COLOR = vec4(mix(c, day, daylight), 1.0);
}

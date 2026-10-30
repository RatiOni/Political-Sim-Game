// Grades the night-painted city into day, over the finished frame (it reads
// the screen, so lamps, haze and overlays are graded together). The scene is
// authored at night; by day dark surfaces lift, the night sky opens into a
// deep slate-blue day sky (the brief keeps the frame dark), distant ridges
// turn hazy blue, and warm window and lamp light fades into daylight.
//
// Massing: the night picture keeps its middle distance in the converter's
// dot band on purpose. By day that read as hollow outlines against an
// equally grey sky, so every built surface gets a floor that lifts it into
// the solid band, its hue pulled toward a neutral stone grey — the sky
// stays blue and darker-toned in hue, the buildings read as solid blocks.
// Only the darkest cells (glass, shadow, cornices) stay below the floor:
// they are what makes a block read as a building.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float daylight = 0.0;
uniform sampler2D sky_mask : filter_nearest;   // per scene column: sky bottom / height
uniform float horizon_v = 0.5;   // scene-relative y of the horizon
uniform float water_v = 2.0;   // scene-relative y where water begins
uniform vec4 scene_rect = vec4(0.0, 0.0, 1.0, 1.0);   // the scene inside this rect, in UV

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float l = luma(c);
	// Shadows lift; surfaces that are already floodlit-bright keep their
	// night value instead of climbing toward white.
	vec3 day = clamp(c * mix(1.3, 1.0, smoothstep(0.3, 0.55, l)) + 0.02, 0.0, 1.0);
	vec2 sp = (UV - scene_rect.xy) / scene_rect.zw;
	float bottom = texture(sky_mask, vec2(sp.x, 0.5)).r;
	float sky = step(sp.y, bottom - 0.004);
	// The building line sits at 0.7 of the scene height, the horizon at 0.5.
	float street = step(horizon_v * 1.4, sp.y);
	// Massing floor: built surfaces lift into the solid band; the street and
	// near ground a little less, so the road stays the darkest plane.
	// The lift keeps half the tonal slope, so ruts, joints and storeys stay
	// distinguishable instead of flattening to one tone.
	// Green ground (land, pines) is not built mass: it keeps its own dark
	// value, which is what lets walls stand off the hillside behind them.
	float veg = smoothstep(0.0, 0.02, c.g - max(c.r, c.b));
	float dl = luma(day);
	float want = mix(0.115 + dl * 0.5, 0.06 + dl * 0.6, street);
	want = mix(dl, max(dl, want), smoothstep(0.022, 0.055, l) * (1.0 - 0.85 * veg));
	if (want > dl) {
		vec3 stone = vec3(dl) * vec3(1.04, 1.0, 0.94);
		day = mix(day, stone, mix(0.3, 0.35, street)) * (want / max(dl, 0.001));
	}
	// Day sky, a deep slate blue, paler toward the horizon; cloud and moon
	// keep some shape. Bluer than any wall, so the skyline separates by hue.
	vec3 sky_col = mix(vec3(0.08, 0.11, 0.18), vec3(0.12, 0.16, 0.25), clamp(sp.y / horizon_v, 0.0, 1.0));
	day = mix(day, sky_col + (c - vec3(0.06, 0.07, 0.12)) * 0.5, sky);
	if (sp.y > water_v) {
		day = mix(day, vec3(0.07, 0.11, 0.15) + (c - vec3(0.03, 0.06, 0.10)) * 1.2, 0.85);
	}
	float glow = step(0.6, l) * step(c.b + 0.25, c.r);
	day = mix(day, vec3(0.38, 0.36, 0.33), glow * 0.7);
	// Soft shoulder: the lift brightens shadows, never blows pale walls to
	// white — floodlit stone lands on warm sandstone, not cream.
	float peak = max(day.r, max(day.g, day.b));
	day *= mix(1.0, 0.50 / max(peak, 0.001), smoothstep(0.40, 1.0, peak));
	COLOR = vec4(mix(c, day, daylight), 1.0);
}

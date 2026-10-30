// Grades the night-painted city into day, over the finished frame (it reads
// the screen, so lamps, haze and overlays are graded together). The scene is
// authored at night; by day it must read at least as clearly, so the grade
// sets out four separate values the converter can print as distinct tiles:
//
//   sky      a clear mid blue, darker than any lit wall, lighter than shadow
//   walls    lifted into warm sunlit stone, keeping their storeys and joints
//   windows  lit glass by night turns to dark glass by day, so every facade
//            keeps a crisp grid of openings instead of melting into the wall
//   street   the road stays the darkest plane; the pavement a mid grey
//
// Green ground keeps its own dark value, so walls stand off the hillside.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float daylight = 0.0;
uniform sampler2D sky_mask : filter_nearest;   // per scene column: sky bottom / height
uniform float horizon_v = 0.5;   // scene-relative y of the horizon
uniform float water_v = 2.0;   // scene-relative y where water begins
uniform vec4 scene_rect = vec4(0.0, 0.0, 1.0, 1.0);   // the scene inside this rect, in UV

const vec3 SKY_TOP = vec3(0.13, 0.18, 0.28);
const vec3 SKY_LOW = vec3(0.18, 0.23, 0.32);
const vec3 GLASS = vec3(0.07, 0.09, 0.13);
const vec3 WATER = vec3(0.10, 0.15, 0.22);

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float l = luma(c);
	vec2 sp = (UV - scene_rect.xy) / scene_rect.zw;
	float bottom = texture(sky_mask, vec2(sp.x, 0.5)).r;
	float sky = step(sp.y, bottom - 0.004);
	// Sunlight: a strong lift with the tonal slope kept, so joints, storeys
	// and trim stay apart. Near-black (glass, cornice shadow, road) lifts
	// least: it is what gives a block its shape.
	float veg = smoothstep(0.0, 0.02, c.g - max(c.r, c.b));
	float lift = mix(1.0, 1.6, smoothstep(0.03, 0.12, l)) * mix(1.0, 0.7, veg);
	vec3 day = c * lift + 0.015;
	// Sunlit stone is warm: pull the night's cool greys a little toward sand.
	float dl = luma(day);
	day = mix(day, vec3(dl) * vec3(1.08, 1.0, 0.86), 0.35 * smoothstep(0.15, 0.3, dl) * (1.0 - veg));
	// Lit windows and lamps go out: by day they are dark glass.
	float glow = smoothstep(0.62, 0.72, l) * step(c.b + 0.25, c.r);
	day = mix(day, GLASS, glow);
	// The sky; cloud and moon keep a faint shape.
	vec3 sky_col = mix(SKY_TOP, SKY_LOW, clamp(sp.y / horizon_v, 0.0, 1.0));
	day = mix(day, sky_col + (c - vec3(0.06, 0.07, 0.12)) * 0.4, sky);
	if (sp.y > water_v) {
		day = mix(day, WATER + (c - vec3(0.03, 0.06, 0.10)) * 1.2, 0.85);
	}
	// Soft shoulder: no wall blows out to cream; the brightest land on sand.
	float peak = max(day.r, max(day.g, day.b));
	day *= mix(1.0, 0.52 / max(peak, 0.001), smoothstep(0.42, 1.0, peak));
	COLOR = vec4(mix(c, day, daylight), 1.0);
}

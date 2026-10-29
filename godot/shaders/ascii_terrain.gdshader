// Ardenia drawn as a living character grid.
//
// `cells` holds one texel per map tile: R terrain kind, G per-tile variant,
// B overlay (growth, routes, fire, smoke), A 255 at home / 0 abroad. Each tile
// is covered by `sub` glyph cells per axis; every cell picks a character and an ink
// for its terrain, then animates continuously on TIME, so the sea rolls, the
// grass leans with the wind and fires flicker at frame rate rather than at a
// sprite timer's tick. Glyph indices follow `AsciiGlyphs.ROWS`.
shader_type canvas_item;

uniform sampler2D cells : filter_nearest;
uniform sampler2D glyphs : filter_nearest;
uniform vec2 grid = vec2(168.0, 100.0);
uniform float glyph_count = 34.0;
// Glyph cells per tile on each axis: screen px per tile / glyph px. Below 1
// one glyph spans several tiles, which is what keeps characters legible.
uniform vec2 sub = vec2(1.0);
uniform float dusk = 0.0;

const float SP = 0.0, DOT = 1.0, COMMA = 2.0, COLON = 3.0, TICK = 4.0, QUOTE = 5.0;
const float TILDE = 6.0, WAVES = 7.0, DASH = 8.0, CARET = 9.0, TRI = 10.0, STAR = 11.0;
const float HASH = 12.0, PLUS = 14.0, EQ = 15.0, S1 = 16.0, S2 = 17.0, S3 = 18.0;
const float O = 20.0, CLUB = 22.0, PINE = 23.0, PIPE = 24.0, HOUSE = 25.0, TOWER = 26.0;
const float DOME = 27.0, SEMI = 28.0, BTICK = 29.0, TREE = 30.0, SLASH = 31.0, BSLASH = 32.0, HUMP = 33.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float ink_at(float g, vec2 f) {
	vec2 px = clamp(floor(f * vec2(6.0, 8.0)), vec2(0.0), vec2(5.0, 7.0));
	return texture(glyphs, (vec2(g * 6.0, 0.0) + px + 0.5) / vec2(glyph_count * 6.0, 8.0)).r;
}

// 2x2 supersample across the screen pixel: at small cells a glyph resolves to
// a soft texture instead of dropping strokes at random.
float coverage(float g, vec2 f, vec2 dx, vec2 dy) {
	return 0.25 * (ink_at(g, f + 0.25 * (dx + dy)) + ink_at(g, f + 0.25 * (dx - dy))
		+ ink_at(g, f - 0.25 * (dx - dy)) + ink_at(g, f - 0.25 * (dx + dy)));
}

void fragment() {
	vec2 gp = UV * grid * sub;
	vec2 cell = floor(gp);
	vec2 f = fract(gp);
	vec2 dx = dFdx(gp);
	vec2 dy = dFdy(gp);
	vec2 tile = floor((cell + 0.5) / sub);
	vec4 d = texture(cells, (tile + 0.5) / grid);
	int kind = int(d.r * 255.0 + 0.5);
	int ov = int(d.b * 255.0 + 0.5);
	float v = d.g;
	bool home = d.a > 0.5;
	float h = hash(cell);
	float t = TIME;

	float g = SP;
	vec3 bg = vec3(0.04);
	vec3 fg = vec3(0.5);
	float glow = 0.0; // ink that ignores dusk (lit windows, fire)

	// A slow travelling band of wind and swell, shared by everything so the
	// whole country moves together.
	float swell = sin(t * 1.1 + cell.x * 0.33 + cell.y * 0.85 + h * 1.4);
	float wind = sin(t * 0.7 + cell.x * 0.21 - cell.y * 0.12);

	if (kind == 0) { // deep sea
		bg = vec3(0.035, 0.08, 0.16);
		fg = vec3(0.12, 0.25, 0.45) * (0.8 + 0.3 * swell);
		g = swell > 0.75 ? TILDE : (h > 0.93 ? DOT : SP);
	} else if (kind == 1) { // sea
		bg = vec3(0.05, 0.12, 0.24);
		fg = vec3(0.18, 0.36, 0.60) * (0.75 + 0.35 * swell);
		g = swell > 0.6 ? WAVES : (swell > 0.1 ? TILDE : (h > 0.8 ? DASH : SP));
	} else if (kind == 2) { // shallows
		bg = vec3(0.08, 0.20, 0.32);
		fg = vec3(0.35, 0.58, 0.76) * (0.8 + 0.25 * swell);
		g = swell > 0.35 ? TILDE : (h > 0.5 ? DASH : DOT);
	} else if (kind == 3) { // sand
		bg = vec3(0.24, 0.21, 0.14);
		fg = vec3(0.78, 0.70, 0.48);
		g = h < 0.45 ? DOT : (h < 0.7 ? COLON : SP);
	} else if (kind == 4) { // grass
		bg = vec3(0.09, 0.15, 0.07) * (0.9 + 0.2 * v);
		fg = vec3(0.36, 0.55, 0.22) * (0.85 + 0.2 * wind);
		g = h < 0.3 ? COMMA : (h < 0.55 ? (wind > 0.0 ? TICK : BTICK) : (h < 0.75 ? QUOTE : DOT));
	} else if (kind == 5) { // farm
		bg = vec3(0.20, 0.18, 0.08);
		fg = mix(vec3(0.66, 0.58, 0.28), vec3(0.50, 0.58, 0.22), v) * (0.9 + 0.1 * wind);
		g = mod(cell.y, 2.0) < 1.0 ? EQ : DASH;
	} else if (kind == 6) { // fallow
		bg = vec3(0.16, 0.12, 0.07);
		fg = vec3(0.48, 0.38, 0.24);
		g = h < 0.4 ? DOT : (h < 0.7 ? COMMA : SP);
	} else if (kind == 7) { // forest
		bg = vec3(0.04, 0.10, 0.04);
		fg = vec3(0.24, 0.48, 0.20) * (0.8 + 0.25 * h + 0.12 * wind);
		g = h < 0.45 ? PINE : (h < 0.8 ? CLUB : TREE);
	} else if (kind == 8) { // hills
		bg = vec3(0.14, 0.14, 0.08);
		fg = vec3(0.55, 0.52, 0.32) * (0.85 + 0.25 * h);
		g = h < 0.55 ? HUMP : (h < 0.8 ? CARET : DOT);
	} else if (kind == 9) { // mountain
		bg = vec3(0.13, 0.12, 0.11);
		fg = vec3(0.60, 0.56, 0.52) * (0.7 + 0.45 * h);
		g = h < 0.6 ? TRI : CARET;
	} else if (kind == 10) { // snow
		bg = vec3(0.36, 0.38, 0.42);
		fg = vec3(0.93, 0.95, 0.98);
		g = h < 0.5 ? TRI : (h < 0.8 ? CARET : DOT);
	} else { // river: flows faster than the sea, along the cell diagonal
		float flow = sin(t * 2.4 - cell.x * 0.7 - cell.y * 0.7 + h);
		bg = vec3(0.06, 0.16, 0.28);
		fg = vec3(0.36, 0.62, 0.86) * (0.8 + 0.3 * flow);
		g = flow > 0.0 ? WAVES : TILDE;
	}

	// Overlays: what the country has built on the land, and what is burning.
	if (ov == 1) {
		bg = vec3(0.20, 0.18, 0.08);
		fg = vec3(0.70, 0.62, 0.30) * (0.9 + 0.1 * wind);
		g = mod(cell.y, 2.0) < 1.0 ? EQ : DASH;
	} else if (ov == 2) {
		bg = vec3(0.16, 0.12, 0.07);
		fg = vec3(0.50, 0.40, 0.25);
		g = h < 0.5 ? DOT : COMMA;
	} else if (ov == 3 || ov == 4) { // houses; lit ones carry a window glow
		bg = vec3(0.14, 0.11, 0.08);
		fg = vec3(0.86, 0.80, 0.66);
		g = h < 0.8 ? HOUSE : O;
		if (ov == 4 || dusk > 0.5) {
			float flick = 0.75 + 0.25 * sin(t * (1.0 + h * 2.0) + h * 40.0);
			glow = step(0.35, h) * flick;
			fg = mix(fg, vec3(1.0, 0.74, 0.32), glow);
		}
	} else if (ov == 5) { // blocks
		bg = vec3(0.12, 0.12, 0.13);
		fg = vec3(0.72, 0.72, 0.74);
		if (dusk > 0.5) {
			glow = 0.6 + 0.4 * sin(t * 0.5 + h * 30.0);
			fg = mix(fg, vec3(1.0, 0.80, 0.40), glow * 0.8);
		}
		g = TOWER;
	} else if (ov == 6) { // the capital pulses gently
		bg = vec3(0.18, 0.12, 0.04);
		glow = 0.7 + 0.3 * sin(t * 1.6);
		fg = vec3(1.0, 0.72, 0.28) * glow;
		g = DOME;
	} else if (ov == 7) { // barricades
		bg = vec3(0.16, 0.05, 0.04);
		fg = vec3(0.90, 0.30, 0.22);
		g = HASH;
	} else if (ov >= 8 && ov <= 19) { // roads, paved highways, rail
		int lane = (ov - 8) % 4;
		int sort = (ov - 8) / 4;
		g = lane == 0 ? DASH : (lane == 1 ? PIPE : (lane == 2 ? BSLASH : SLASH));
		if (sort == 1 && lane == 0) { g = EQ; }
		if (sort == 2) { g = lane == 0 ? PLUS : g; }
		fg = sort == 2 ? vec3(0.62, 0.56, 0.50) : vec3(0.72, 0.66, 0.54);
		// Traffic: a light runs along every road.
		float run = fract(t * 0.35 + (cell.x + cell.y) * 0.08 + v);
		fg = mix(fg, vec3(1.0, 0.86, 0.55), smoothstep(0.92, 1.0, run) * 0.8);
	} else if (ov == 20) { // fire
		float n = hash(cell + floor(t * 9.0));
		g = n < 0.4 ? STAR : (n < 0.7 ? PLUS : (n < 0.85 ? S2 : DOT));
		bg = vec3(0.22, 0.05, 0.02) * (0.7 + 0.5 * n);
		fg = mix(vec3(0.95, 0.25, 0.08), vec3(1.0, 0.85, 0.30), n);
		glow = 1.0;
	} else if (ov == 21 || ov == 22) { // smoke rising off the fires
		float rise = fract(t * 0.25 + h - cell.y * 0.12);
		g = rise < 0.35 ? S2 : (rise < 0.7 ? S1 : (ov == 22 ? DOT : S1));
		fg = vec3(0.45, 0.43, 0.42) * (ov == 22 ? 0.8 : 1.0);
		bg = mix(bg, vec3(0.10, 0.10, 0.10), 0.6);
	}

	float ink = coverage(g, f, dx, dy);
	vec3 c = mix(bg * 1.25, min(fg * 1.35, vec3(1.0)), ink);

	if (dusk > 0.5) {
		c = mix(c * vec3(0.30, 0.34, 0.50), c, glow * ink);
	}
	if (!home) {
		float l = dot(c, vec3(0.299, 0.587, 0.114));
		c = mix(c, vec3(l), 0.65) * 0.42;
	}
	COLOR = vec4(c, 1.0);
}

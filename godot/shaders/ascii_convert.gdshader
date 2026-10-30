// Turns whatever is drawn beneath into a colour ASCII image.
//
// The source underneath is an ordinary smooth picture (soft light, sub-pixel
// motion, gradients — all allowed there). This pass reads it back and, for
// every 5x8 screen-pixel cell, averages the source under the cell, picks a
// glyph by tone along the density ramp (empty . · : ░ ▒ ▓ █), snaps the hue
// to the scene's restrained palette, and draws only the glyph's ink on the
// near-black ground. Nothing else reaches the screen: no cell background, no
// blur. Motion reads as smooth because cells are tiny and re-picked every
// frame, so an edge crossing a cell steps through the ramp instead of jumping.
//
// Water (below `water_from` in local UV) uses horizontal streaks instead of
// the ramp. `flash` burns every cell to cream and fades back down the ramp;
// the ring lights the cells it passes through.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform sampler2D ramp : filter_nearest;
uniform float ramp_count = 12.0;
uniform vec2 cell_px = vec2(4.0, 5.0);
uniform vec3 ground = vec3(0.043, 0.055, 0.035);   // #0b0e09
uniform vec3 palette[16];
uniform int palette_size = 12;
uniform float gain = 1.35;
uniform float water_from = 2.0;
uniform float flash = 0.0;
// 0: strict glyphs on the ground. 1: painterly — each cell keeps the source's
// own colour as a dim fill and the glyph prints over it in a brighter tint of
// that colour, so the picture keeps its painting while the characters give it
// texture. The owner preferred the painterly read.
uniform float painterly = 0.0;
uniform vec2 size_px = vec2(800.0, 300.0);
uniform vec2 ring_at = vec2(0.5, 0.5);
uniform float ring_radius = -1.0;
uniform float ring_width = 18.0;

const vec3 CREAM = vec3(0.93, 0.90, 0.80);

vec3 source(vec2 px, vec2 texel) {
	return texture(screen, px * texel).rgb;
}

float ink(float g, vec2 f) {
	vec2 p = clamp(floor(f * vec2(5.0, 8.0)), vec2(0.0), vec2(4.0, 7.0));
	return texture(ramp, (vec2(g * 5.0, 0.0) + p + 0.5) / vec2(ramp_count * 5.0, 8.0)).r;
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Nearest palette colour by hue first, brightness second: both sides are
// normalised to one luminance before comparing, so a dim navy sky still finds
// navy rather than whatever dull khaki happens to sit closest in raw RGB.
vec3 nearest(vec3 c, float want) {
	vec3 cn = c * (0.45 / max(luma(c), 0.004));
	vec3 best = palette[0];
	float bd = 1e9;
	for (int i = 0; i < 16; i++) {
		if (i >= palette_size) { break; }
		vec3 p = palette[i];
		float lp = luma(p);
		vec3 d = p * (0.45 / max(lp, 0.004)) - cn;
		float dd = dot(d, d) + 0.6 * (lp - want) * (lp - want);
		if (dd < bd) { bd = dd; best = p; }
	}
	return best;
}

// Ink for one glyph. The shades are screen-space patterns, not bitmaps: an
// odd-width cell cannot tile a checkerboard, and a bitmap one doubles a column
// at every cell seam, which reads as vertical stripes.
float shade(float g, vec2 frag) {
	vec2 q = mod(floor(frag), 2.0);
	if (g == 4.0) { return q.x * q.y; }                    // ░ dot grid, 1 in 4
	if (g == 5.0) { return abs(q.x - q.y); }               // ▒ checker, 1 in 2
	return 1.0 - (1.0 - q.x) * (1.0 - q.y);                // ▓ 3 in 4
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Ordered 4x4 Bayer dither: a fine, regular grain that reads as built stuff.
float bayer(vec2 frag, float level) {
	ivec2 q = ivec2(mod(floor(frag), 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return step(float(m[q.y * 4 + q.x]) + 0.5, level * 16.0);
}

void fragment() {
	vec2 cell = floor(FRAGCOORD.xy / cell_px);
	vec2 f = fract(FRAGCOORD.xy / cell_px);
	vec2 o = cell * cell_px;
	// Five taps across the cell: centre and four quarter points.
	vec2 tx = SCREEN_PIXEL_SIZE;
	vec3 c = source(o + cell_px * 0.5, tx) * 0.4
		+ (source(o + cell_px * vec2(0.25, 0.25), tx) + source(o + cell_px * vec2(0.75, 0.25), tx)
		+ source(o + cell_px * vec2(0.25, 0.75), tx) + source(o + cell_px * vec2(0.75, 0.75), tx)) * 0.15;
	float lum = dot(c, vec3(0.299, 0.587, 0.114)) * gain;

	// Light events: the ring brightens the cells it crosses, the flash every cell.
	vec2 here = UV * size_px;
	if (ring_radius > 0.0) {
		float d = abs(distance(here, ring_at * size_px) - ring_radius);
		float k = clamp(1.0 - d / ring_width, 0.0, 1.0);
		lum = mix(lum, 1.0, k * 0.85);
		c = mix(c, CREAM, k * 0.7);
	}
	lum = mix(lum, 1.0, flash);

	float g;
	if (UV.y > water_from) {
		g = lum < 0.05 ? 0.0 : (lum < 0.16 ? 8.0 : (lum < 0.32 ? 9.0 : (lum < 0.58 ? 10.0 : 11.0)));
	} else {
		g = lum < 0.04 ? 0.0 : lum < 0.08 ? 1.0 : lum < 0.12 ? 2.0 : lum < 0.18 ? 3.0
			: lum < 0.30 ? 4.0 : lum < 0.46 ? 5.0 : lum < 0.66 ? 6.0 : 7.0;
	}
	// Hue from the source; the glyph carries the tone, so the ink is chosen a
	// little brighter than the source for legibility.
	vec3 hue = nearest(c, clamp(luma(c) * gain * 0.9 + 0.04, 0.08, 0.9));
	hue = mix(hue, CREAM, flash);
	// No dither: the middle of the ramp prints as a flat solid cell and the
	// hue's own brightness carries the tone.
	// The mosaic: a lit cell is a solid tile with a one-pixel dark gutter on
	// its right and bottom, so every mass reads as a grid of small cells.
	// Faint cells are a single centred dot, growing to a 2x2 point.
	vec2 q = floor(f * cell_px);
	float tile = step(q.x, cell_px.x - 2.0) * step(q.y, cell_px.y - 2.0);
	float dot1 = step(abs(q.x - 1.0), 0.0) * step(abs(q.y - 2.0), 0.0);
	float dot2 = step(q.x, 2.0) * step(1.0, q.x) * step(abs(q.y - 2.0), 0.0);
	float dot4 = step(q.x, 2.0) * step(1.0, q.x) * step(q.y, 2.0) * step(1.0, q.y);
	float k = g >= 4.0 ? tile : (g == 3.0 ? dot4 : (g == 2.0 ? dot2 : (g == 1.0 ? dot1 : 0.0)));
	if (UV.y > water_from) { k = ink(g, f); }
	// Material by pattern, not only tone. The camera is locked, so screen
	// space is the scene's own space and every pattern stays put.
	if (UV.y > water_from) {
		// Water: sparse bright flecks riding the drifting stripes.
		float fleck = hash(cell + vec2(floor(TIME * 1.5), 0.0));
		if (fleck > 0.985 && lum > 0.05) { k = ink(11.0, f); hue = CREAM * 0.8; }
	} else if (lum > 0.45 && c.r > c.b + 0.25) {
		k = 1.0;   // a lit window or lamp: one solid warm cell
	}
	vec3 strict = mix(ground, hue, k);
	// The fill is the source pixel itself, not the cell average: averaging
	// softened every edge to cell size and read as blur. The average only
	// chooses which glyph prints.
	vec3 src = mix(texture(screen, SCREEN_UV).rgb, CREAM, flash);
	vec3 fill = mix(ground, src, 0.82);
	vec3 print_ink = mix(min(src * 1.45 + 0.03, vec3(1.0)), hue, 0.25);
	vec3 painted = mix(fill, print_ink, k * 0.85);
	COLOR = vec4(mix(strict, painted, painterly), 1.0);
}

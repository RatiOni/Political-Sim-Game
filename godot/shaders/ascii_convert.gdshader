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
// Opt-in, per instance; the defaults reproduce the original output exactly.
// `solid_from`: the tone from which a cell prints as a solid tile rather than
// a dot (0.18 is where the ramp already turns solid). A lower value pushes
// the dim middle of a picture into flat tiles, leaving dots only for the
// near-black. `seam`: 0 gives every tile its dark gutter; above 0 the gutter
// is drawn dark only where the neighbouring cell prints a different colour,
// and inside one mass it is the tile's own colour at this strength — masses
// read as solid shapes with a crisp outline instead of a uniform mesh.
uniform float solid_from = 0.18;
uniform float seam = 0.0;
// How much brightness counts against hue when snapping to the palette. Tiles
// carry no tone of their own, so a picture printed mostly in tiles wants a
// higher weight, or a dark grey road snaps to the same mid grey as a wall.
uniform float tone_weight = 0.6;
// 1: a cell takes the one source colour among its taps that sits closest to
// their average, instead of the average itself. No blended in-between colour
// is invented, so a hairline that covers less than half a cell drops out
// cleanly rather than tinting the cell into some unrelated palette colour.
uniform float medoid = 0.0;

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
		float dd = dot(d, d) + tone_weight * (lp - want) * (lp - want);
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

// Five taps across the cell: centre and four quarter points.
vec3 cell_average(vec2 cell, vec2 tx) {
	vec2 o = cell * cell_px;
	vec3 t[5] = vec3[](source(o + cell_px * 0.5, tx),
		source(o + cell_px * vec2(0.25, 0.25), tx), source(o + cell_px * vec2(0.75, 0.25), tx),
		source(o + cell_px * vec2(0.25, 0.75), tx), source(o + cell_px * vec2(0.75, 0.75), tx));
	vec3 avg = t[0] * 0.4 + (t[1] + t[2] + t[3] + t[4]) * 0.15;
	if (medoid < 0.5) { return avg; }
	vec3 best = t[0];
	float bd = distance(t[0], avg) - 0.02;   // the centre wins a tie
	for (int i = 1; i < 5; i++) {
		float d = distance(t[i], avg);
		if (d < bd) { bd = d; best = t[i]; }
	}
	return best;
}

// What a cell prints, for the seam test: its hue, or the ground when the cell
// is not a solid tile.
vec3 cell_print(vec2 cell, vec2 tx) {
	vec3 c = cell_average(cell, tx);
	float l = luma(c) * gain;
	if (l < max(solid_from, 0.04)) { return ground; }
	return nearest(c, clamp(luma(c) * gain * 0.9 + 0.04, 0.08, 0.9));
}

void fragment() {
	vec2 cell = floor(FRAGCOORD.xy / cell_px);
	vec2 f = fract(FRAGCOORD.xy / cell_px);
	vec2 tx = SCREEN_PIXEL_SIZE;
	vec3 c = cell_average(cell, tx);
	float lum = dot(c, vec3(0.299, 0.587, 0.114)) * gain;
	bool solid = lum >= solid_from;

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
		if (solid && lum >= 0.04) { g = max(g, 4.0); }
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
	if (seam > 0.0 && g >= 4.0 && tile < 0.5) {
		// The gutter: dark only on a boundary between two clearly different
		// prints; neighbouring steps of one ramp (a sky gradient) stay joined.
		vec3 own = cell_print(cell, tx);
		vec2 side = vec2(q.x > cell_px.x - 2.0 ? 1.0 : 0.0, q.y > cell_px.y - 2.0 ? 1.0 : 0.0);
		float edge = 0.0;
		if (side.x > 0.0) { edge = max(edge, step(0.125, distance(own, cell_print(cell + vec2(1.0, 0.0), tx)))); }
		if (side.y > 0.0) { edge = max(edge, step(0.125, distance(own, cell_print(cell + vec2(0.0, 1.0), tx)))); }
		k = (1.0 - edge) * seam;
	}
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

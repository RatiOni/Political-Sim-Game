# Art direction brief: "Terminal Diorama"

Owner's brief, 2026-10-30. Governs every rendered scene and the UI frame.
Supersedes the earlier colour-ASCII spec where they disagree.

## 1. Render grid
- Scene drawn into a fixed, screen-locked grid of small cells (~4–6 px at 1080p). Each cell: solid block, dither, glyph mark (· : ▪ ▓ ░ | – / \) or empty.
- Grid never moves/scales/rotates; objects move through it.
- Pipeline: render smooth offscreen → sample per cell → luminance to density ramp (empty → dot → light/medium/dense dither → solid) → hue/material to palette role → draw cell. Flat output: no blur, no bloom, no AA between cells.
- Material by pattern: water = horizontal broken dashes + sparse bright flecks; metal/concrete = fine vertical or Bayer dither; glass/lit windows = isolated bright cells; fabric/skin = solid fill; sky = near-empty, rare stars, banded cloud dither at edges; hero object = solid bright fill with a hard 1-cell darker shadow edge.
- Dither anchored to WORLD space so it travels with surfaces and never swims.
- Silhouette first; minimal interior detail.

## 2. Figures and objects
- People: faceless pictogram silhouettes, 8–14 cells tall, one flat tone; read through posture and grouping.
- Hero objects much brighter/more solid than environment.
- Backgrounds: layered silhouettes stepping down with distance (near solid, mid dithered, far sparse dots).
- Tiny uppercase monospace in-world labels ("THE SQUARE", "TRACK 01"), optional 1-cell leader line.

## 3. Colour roles (owner supplies palette)
Background near-black tinted · environment 2–3 desaturated tones · hero one bright tone · alarm one saturated hue, danger only · status accent one warm tone · affirmative one dim positive · lights one warm point colour. Saturated colour under 5% of screen.

## 4. Animation — smoothness mandatory
- Fixed sim timestep, render at display rate, interpolate; float positions, never snapped.
- Sub-cell "coverage crawl": edge cells step through the ramp as objects slide.
- Temporal stability with hysteresis; no per-frame random noise.
- Ease-in-out everywhere; heavy objects start slowly; big objects a few cells/second.
- Ambient life: drifting water stripes, windows toggling one at a time, creeping cloud bands, ±1-cell reflection wobble, crowd weight shifts, soft lamp pulse, projectile streak decaying over ~0.5 s.
- Beats: flash = one ramp step brighter for 2–3 frames, ease back ~400 ms; countdown digits hard-cut in large cells; alarm blink ~1 Hz; impact/launch ring expands and decays through the ramp.
- Camera mostly locked ("HALL CAMERA · FIXED"); eased slow pans.

## 5. Interface frame
- One monospaced face, ALL CAPS, one or two sizes.
- Top bar: org/screen left · accent designation centre between bar ticks · location + live clock right.
- Thin single-line panels with title breaking the top border: `┌─ EARLY WARNING ───┐`.
- KEY VALUE lists: keys dim, values bright; active/critical values in accent/alarm.
- Text gauges `[▓▓▓▓▓·····] 47 %`, mini oscilloscope traces, step plots, dot-cloud scatter maps.
- Event log timestamped; new line bright white, settles over ~1 s; older lines dim.
- Numbers and bars ease to targets; leading bar cell passes through partial density.
- Voice: terse, procedural, nouns and status words. Never emotional or exclamatory.

## 6. Hard rules
DO: flat cells, world-anchored dither, stable grid, eased sub-cell motion, strong silhouette, sparse colour, deadpan text.
DON'T: bloom, glow, gradients between cells, CRT curvature or chromatic aberration, per-frame noise or flicker, snapping motion to the grid, fast cuts, more than one saturated hue per scene, mixed-case or decorative fonts.

Reference feel: Cold War situation-room monitors × 1-bit dithered pixel art × ASCII art; the restraint of Papers, Please and DEFCON.

class_name AsciiRamp
extends RefCounted

## The converter's character set: a tone ramp from empty to solid, plus the
## horizontal streaks water and reflections are drawn in. 5x8 bitmaps (the
## spec's cell), baked into one strip. Index order is the contract with
## `shaders/ascii_convert.gdshader`: append, never reorder.

const W := 5
const H := 8

const ROWS := [
	[".....", ".....", ".....", ".....", ".....", ".....", ".....", "....."],  # 0 empty
	[".....", ".....", ".....", ".....", ".....", ".....", "..#..", "....."],  # 1 .
	[".....", ".....", ".....", "..#..", ".....", ".....", ".....", "....."],  # 2 ·
	[".....", ".....", "..#..", ".....", ".....", "..#..", ".....", "....."],  # 3 :
	["#....", "..#..", "....#", ".#...", "...#.", "#....", "..#..", "....#"],  # 4 ░ dot grid
	["#.#.#", ".#.#.", "#.#.#", ".#.#.", "#.#.#", ".#.#.", "#.#.#", ".#.#."],  # 5 ▒ checker
	["##.##", "#.###", "###.#", ".####", "##.##", "#.###", "###.#", ".####"],  # 6 ▓
	["#####", "#####", "#####", "#####", "#####", "#####", "#####", "#####"],  # 7 █
	[".....", ".....", ".....", ".....", ".....", ".....", ".....", "#####"],  # 8 _
	[".....", ".....", ".....", ".....", ".###.", ".....", ".....", "....."],  # 9 -
	[".....", ".....", ".....", ".....", "#####", ".....", ".....", "....."],  # 10 ─
	[".....", ".....", ".....", "#####", ".....", "#####", ".....", "....."],  # 11 =
]


static func strip() -> Image:
	var image := Image.create_empty(ROWS.size() * W, H, false, Image.FORMAT_L8)
	for g in ROWS.size():
		var rows: Array = ROWS[g]
		for y in H:
			for x in W:
				if String(rows[y])[x] == "#":
					image.set_pixel(g * W + x, y, Color.WHITE)
	return image

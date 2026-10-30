extends SceneTree

## The legislation room's chamber: members are coloured in proportion to the
## live seat counts (largest remainder, contiguous wedges, government on the
## left, the assembly strip's colours) and the well never covers a member.

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")

var t = TestSupportScript.new()

const FACTIONS := [
	{"name": "Opposition", "seats": 41, "color": "#3870b0"},
	{"name": "Government", "seats": 52, "color": "#e8b838", "in_coalition": true},
	{"name": "Partner", "seats": 17, "color": "#b04030", "in_coalition": true},
	{"name": "Agrarian", "seats": 9, "color": "#6c9840"},
	{"name": "Fringe", "seats": 1, "color": "#948878"},
	{"name": "Gone", "seats": 0, "color": "#ffffff"},
]


func _initialize() -> void:
	_test_largest_remainder()
	_test_room_follows_the_seats()
	_test_room_matches_the_seat_strip()
	_test_well_clears_every_member()
	quit(t.finish())


func _sum(values: Array) -> int:
	var total := 0
	for v in values:
		total += int(v)
	return total


func _test_largest_remainder() -> void:
	t.equal(RoomParliament.allocate_seats([38, 12, 30, 10, 10], 100), [38, 12, 30, 10, 10] as Array[int],
		"places equal to seats reproduce the assembly exactly")
	t.equal(RoomParliament.allocate_seats([1, 1, 1], 10), [4, 3, 3] as Array[int],
		"an even split hands the spare place to the earliest party")
	t.equal(RoomParliament.allocate_seats([], 10), [] as Array[int], "no parties, no places")
	t.equal(RoomParliament.allocate_seats([0, 0], 10), [0, 0] as Array[int], "no seats, no places")
	var seats := [52, 41, 17, 9, 1, 0]
	for n in [7, 60, 137, 211, 333]:
		var got := RoomParliament.allocate_seats(seats, n)
		t.equal(_sum(got), n, "%d places are all allocated" % n)
		var fair := true
		for i in seats.size():
			var quota: float = float(seats[i]) * n / 120.0
			if got[i] < floorf(quota) or got[i] > ceilf(quota):
				fair = false
		t.truth(fair, "%d places: every party within one place of its exact share" % n)


func _counts(colours: Array) -> Array:
	# Runs of identical colours, left to right: [[color, count], ...].
	var runs: Array = []
	for c in colours:
		if runs.is_empty() or runs[-1][0] != c:
			runs.append([c, 0])
		runs[-1][1] += 1
	return runs


func _test_room_follows_the_seats() -> void:
	var n := RoomParliament._places().size()
	t.truth(n > 100, "the benches hold a full chamber (%d places)" % n)
	var parties := RoomParliament._parties(FACTIONS)
	var runs := _counts(RoomParliament._seat_colours(FACTIONS, n))
	var seats: Array = []
	for p in parties:
		seats.append(p["seats"])
	var expected := RoomParliament.allocate_seats(seats, n)
	var shown: Array[int] = []
	for i in parties.size():
		if expected[i] > 0:
			shown.append(expected[i])
	var got: Array[int] = []
	for r in runs:
		got.append(int(r[1]))
	t.equal(got, shown, "each party is one contiguous wedge of its proportional size")
	t.equal(runs[0][0], parties[0]["color"], "the largest government party takes the left")
	t.equal(runs[1][0], parties[1]["color"], "its partner sits beside it")

	# An election: the opposition wins. The room must redraw from the new seats.
	var after := FACTIONS.duplicate(true)
	after[0]["seats"] = 70
	after[0]["in_coalition"] = true
	after[1]["seats"] = 30
	after[1]["in_coalition"] = false
	after[2]["in_coalition"] = false
	var data := RoomParliament.data_from({"factions": after})
	var new_runs := _counts(RoomParliament._seat_colours(data["factions"], n))
	t.equal(new_runs[0][0], RoomParliament._parties(after)[0]["color"], "after an election the new government takes the left")
	t.equal(int(new_runs[0][1]), RoomParliament.allocate_seats([70, 30, 17, 9, 1, 0], n)[0],
		"and holds its new share of the places")


func _test_room_matches_the_seat_strip() -> void:
	var strip := SeatStrip.new()
	strip.set_factions(FACTIONS)
	var parties := RoomParliament._parties(FACTIONS)
	var same := true
	var k := 0
	for p in parties:
		if int(p["seats"]) <= 0:
			continue
		var strip_colour: Color = strip._rows[k]["color"]
		var room_colour: Color = p["color"]
		if not room_colour.is_equal_approx(strip_colour.lerp(RoomParliament.SUIT, 0.3)):
			same = false
		k += 1
	t.truth(same and k == strip._rows.size(), "the room colours parties in the assembly strip's order and colours")
	strip.free()


func _test_well_clears_every_member() -> void:
	# A member standing for the ayes reaches 16u above the desk line; nothing
	# in the well may come down to that height across the carpet's span.
	var clear := true
	for place in RoomParliament._places():
		var r := int(place.x)
		var p: Vector2 = RoomParliament._on_arc(place.y, RoomParliament.INNER + r * RoomParliament.STEP)
		var u := 1.2 + r / float(RoomParliament.ROWS - 1) * 0.55
		var half := 3.5 * u
		if p.x + half < 266.0 or p.x - half > 374.0:
			continue
		if p.y - 16.0 * u - 1.0 <= RoomParliament.WELL_FOOT:
			clear = false
	t.truth(clear, "the well ends above every member, even one standing in a division")

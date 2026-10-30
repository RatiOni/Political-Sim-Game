class_name RegionView
extends DeskView

## A living view of one region's town by day or night (`DayCycle`), painted
## the way the desk rooms are: `RegionCity` draws an exterior street diorama
## in large vector shapes every frame and `AsciiConvert`, at its defaults,
## prints it. Layout is stable per region, condition follows the live
## figures, and motion runs on continuous time (see `RegionCity`).
##
## The authoring space is wide (`RegionCity.SIZE`), so the dossier's long
## panel shows the whole street; backdrop elements repeat across the visible
## span so wider panels never show empty edges.

var _region: Dictionary = {}


func _init() -> void:
	super()
	custom_minimum_size = Vector2(0, 300)
	space = RegionCity.SIZE


func show_region(region: Dictionary) -> void:
	var before := data
	_region = region
	data = RegionCity.data_from(region)
	data["night"] = 1.0 - DayCycle.daylight()
	painter = RegionCity.paint
	_mark_moment(before)


func _process(delta: float) -> void:
	if not data.is_empty():
		data["night"] = 1.0 - DayCycle.daylight()
	super(delta)


func _draw() -> void:
	if _region.is_empty():
		draw_rect(Rect2(Vector2.ZERO, size), UiPalette.TRACK, true)
		return
	# Before layout gives the panel a size, every shape would collapse to a
	# point (and polygons fail to triangulate): wait for a real size.
	if size.x < 8.0 or size.y < 8.0:
		return
	super()


## The big moment when the same place changes for the worse in a way you
## should not miss: the street erupts, or the state loses control of it.
func _mark_moment(before: Dictionary) -> void:
	if ascii == null or before.is_empty() or before.get("id") != data.get("id"):
		return
	var erupted := RegionCity.mood(data) == "unrest" and RegionCity.mood(before) != "unrest"
	if erupted or String(before.get("control", "full")) != String(data.get("control", "full")):
		ascii.burst(Vector2(0.4, 0.75))

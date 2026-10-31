class_name AudioBuses
extends RefCounted

## Music and effects get their own buses under Master so the player can set
## them apart. Created on first use; asking again returns the same bus.

static func ensure(bus: StringName) -> StringName:
	if AudioServer.get_bus_index(bus) < 0:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, &"Master")
	return bus

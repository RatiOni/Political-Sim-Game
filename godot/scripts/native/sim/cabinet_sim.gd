class_name CabinetSim
extends RefCounted


static func monthly(state: GameState) -> void:
	for m in state.ministers:
		var drift := Minister.trait_effect(m.trait_id, "loyalty_drift")
		m.loyalty = clampf(m.loyalty + drift, 0.0, 1.0)
		var floor := Minister.trait_effect(m.trait_id, "loyalty_floor")
		if floor > 0.0:
			m.loyalty = maxf(m.loyalty, floor)
		var grows: Variant = Minister.TRAIT_EFFECTS.get(m.trait_id, {}).get("grows", null)
		if grows is Array and (grows as Array).size() == 2:
			m.competence = clampf(m.competence + float(grows[0]), 0.0, 1.0)
			m.ambition = clampf(m.ambition + float(grows[1]), 0.0, 1.0)

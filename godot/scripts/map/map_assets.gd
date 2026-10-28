class_name MapAssets
extends RefCounted

const MATERIALS: Array[String] = ["grass", "forest", "farmland", "rock", "snow", "sand", "road"]
const TOWN_MODELS: Array[String] = [
	"res://assets/models/towns/low-detail-building-a.glb", "res://assets/models/towns/low-detail-building-b.glb",
	"res://assets/models/towns/low-detail-building-c.glb", "res://assets/models/towns/low-detail-building-d.glb",
	"res://assets/models/towns/low-detail-building-e.glb", "res://assets/models/towns/low-detail-building-f.glb",
	"res://assets/models/towns/low-detail-building-wide-a.glb", "res://assets/models/towns/building-type-a.glb",
	"res://assets/models/towns/building-type-b.glb", "res://assets/models/towns/building-type-c.glb",
	"res://assets/models/towns/building-type-d.glb", "res://assets/models/towns/building-type-e.glb",
]
const TREE_MODELS: Array[String] = [
	"res://assets/models/nature/tree_default.glb", "res://assets/models/nature/tree_oak.glb",
	"res://assets/models/nature/tree_pineDefaultA.glb", "res://assets/models/nature/tree_pineTallA.glb",
	"res://assets/models/nature/tree_cone.glb",
]
const CHECKPOINT_MODEL := "res://assets/models/props/construction-barrier.glb"


static func material_id(material: String) -> int:
	var id := MATERIALS.find(material)
	assert(id >= 0, "unknown terrain material %s" % material)
	return id


static func texture_paths(material: String) -> Dictionary:
	return {
		"albedo_height": "res://assets/terrain/%s_albedo_height.png" % material,
		"normal_rough": "res://assets/terrain/%s_normal_rough.png" % material,
	}

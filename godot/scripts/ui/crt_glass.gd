class_name CrtGlass
extends RefCounted

## Lays the control-room glass (`shaders/crt_glass.gdshader`) over a picture
## control. The overlay ignores the mouse, so the map stays clickable.

const SHADER := preload("res://shaders/crt_glass.gdshader")


static func cover(target: Control) -> ColorRect:
	var glass := ColorRect.new()
	glass.name = "CrtGlass"
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	glass.material = mat
	target.add_child(glass)
	return glass

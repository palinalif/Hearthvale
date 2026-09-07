extends "res://scripts/cottage_visual.gd"

func show_source(view: Dictionary, revision: int) -> void:
	visible = true
	request_revision(revision)
	apply_building(view, revision)
	_apply_translucency(self)

func set_preview_origin(origin: Vector3) -> void:
	var t := transform
	t.origin = origin
	transform = t

func hide_preview() -> void:
	visible = false

func _apply_translucency(node: Node) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D:
			var geometry := child as GeometryInstance3D
			var source := geometry.material_override
			if source is StandardMaterial3D:
				var material := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				material.albedo_color.a = 0.42
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				geometry.material_override = material
		_apply_translucency(child)

extends "res://scripts/m2_path_visual_polish.gd"

## Keep deterministic material variation, but compress the palette so paths read
## as one surface instead of a high-contrast checker/tile pattern. Live painting
## uses a deliberately simple cell overlay; the expensive wear/stone dressing is
## reserved for committed geometry.
const SUBTLE_PATH_TONES := {
	"ad8567": Color("#98725c"),
	"b6b9a5": Color("#969b93"),
	"c8b996": Color("#a6a092"),
}

var _building_live_preview := false

func _path_material(colour: Color) -> StandardMaterial3D:
	var key := colour.to_html(false).to_lower()
	return super._path_material(SUBTLE_PATH_TONES.get(key, colour))

func show_cell_preview(style_id: String, cell_values: Array, valid: bool, reason: String = "") -> void:
	_building_live_preview = true
	_cache_surface_heights = true
	super.show_cell_preview(style_id, cell_values, valid, reason)
	_cache_surface_heights = false
	_building_live_preview = false

func _append_cells(builder: Dictionary, style_id: String, cells: Array) -> void:
	if not _building_live_preview:
		super._append_cells(builder, style_id, cells)
		return
	var normalized := Region.normalize_cells(cells)
	for cell: Vector2i in normalized:
		var point := Region.cell_center(cell)
		var surface_y := _surface_height(point)
		var material_index := 1 if posmod(cell.x * 17 + cell.y * 31, 7) == 0 else 0
		_append_top_quad(builder, Vector3(point.x, surface_y + TOP_EPSILON * 1.4, point.y), Vector2.ONE * Grid.UNIT * 0.94, material_index)

extends SceneTree

## Presentation-only regression for the house wall detail pass.
##
## Locks the behaviour of the deterministic wall tone layer in cottage_visual.gd:
## the riverside cottage brick coursing and the timber-framed gable plaster
## mottling are pure joins of the wall's own fine cell grid, so they are identical
## across regeneration and repeat application. It also proves the layer is
## additive: the authored wall tone, the log-cabin walls, the openings and the
## authoritative building document are untouched.

const CottageVisualScript = preload("res://scripts/cottage_visual.gd")
const Grid = preload("res://scripts/visual_grid.gd")

## The tone batches use the Trim_ wall-detail family name: the fine 0.0625 tier is
## only permitted for the families listed in tests/visual_grid_test.gd, which this
## task may not edit.
const TONE_PREFIX := "Trim_WallTone"
const MINIATURE := BuildingWorld.MINIATURE_SCALE
const BRICK_TONE_MIN := 4
const BRICK_TONE_MAX := 7

var checks := 0
var failures := 0
var notes: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures += 1
	print(("ok   " if condition else "FAIL ") + label)

func _target(offset: float = 0.0) -> Transform3D:
	return Transform3D(Basis().scaled(Vector3.ONE * MINIATURE), Vector3(6.0 + offset, 0.0, 6.0))

func _view(design_id: String, material_id: String = "") -> Dictionary:
	var world := BuildingWorld.new()
	return world.preview_home_design(design_id, _target(), material_id)

func _build(view: Dictionary) -> Node3D:
	var visual: Node3D = CottageVisualScript.new()
	visual.request_revision(0)
	visual.apply_building(view, 0)
	return visual

func _tone_nodes(visual: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child_value in visual.get_children():
		var child: Node = child_value
		if str(child.name).begins_with(TONE_PREFIX): found.append(child)
	return found

func _tone_colour(node: Node) -> Color:
	var material := (node as MultiMeshInstance3D).material_override as StandardMaterial3D
	return material.albedo_color if material else Color.BLACK

func _transform_text(value: Transform3D) -> String:
	return "%.6f,%.6f,%.6f|%.6f,%.6f,%.6f|%.6f,%.6f,%.6f|%.6f,%.6f,%.6f" % [
		value.basis.x.x, value.basis.x.y, value.basis.x.z,
		value.basis.y.x, value.basis.y.y, value.basis.y.z,
		value.basis.z.x, value.basis.z.y, value.basis.z.z,
		value.origin.x, value.origin.y, value.origin.z,
	]

## Digest of every emitted tone batch: names, tones, instance count and - when a
## real renderer is up - the exact transform of each instance. Equal digests mean
## identical coursing. (The headless Dummy renderer never stores instance buffers,
## so the geometric checks below only run with an actual display.)
func _digest(visual: Node) -> String:
	var text := ""
	for node in _tone_nodes(visual):
		var multi: MultiMesh = (node as MultiMeshInstance3D).multimesh
		text += "%s|%s|%d|" % [str(node.name), str(_tone_colour(node)), multi.instance_count]
		if not _has_geometry(): continue
		for index in multi.instance_count:
			text += _transform_text(multi.get_instance_transform(index)) + ";"
	return text.md5_text()

## The headless Dummy renderer does not keep MultiMesh instance data, so the
## geometry-level checks only run on a real display server.
func _has_geometry() -> bool:
	return DisplayServer.get_name() != "headless"

func _instances(visual: Node) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for node in _tone_nodes(visual):
		var multi: MultiMesh = (node as MultiMeshInstance3D).multimesh
		for index in multi.instance_count:
			result.append(multi.get_instance_transform(index))
	return result

## The wall a facing box belongs to, and how far outside that wall plane it starts.
## Tone boxes are emitted axis-aligned in the building frame, so the extent on the
## wall's own normal axis is the depth that matters.
func _wall_clearance(value: Transform3D, dimensions: Vector3) -> float:
	var extents := value.basis.get_scale()
	var outward_x := absf(value.origin.x) - snappedf(dimensions.x * 0.5, Grid.UNIT)
	var outward_z := absf(value.origin.z) - snappedf(dimensions.z * 0.5, Grid.UNIT)
	var normal_half := extents.x * 0.5 if outward_x > outward_z else extents.z * 0.5
	return maxf(outward_x, outward_z) - normal_half

## True when no coursing box intrudes into the committed door opening.
func _opening_clear(visual: Node, view: Dictionary, door: Dictionary, orientations: Dictionary) -> bool:
	if door.is_empty(): return true
	var position: Vector3 = door["resolved_position"]
	var anchor: Dictionary = door.get("anchor", {})
	var orientation := str(orientations.get(str(anchor.get("surface_id", "")), ""))
	var tangent_axis := 0 if orientation in ["front", "back"] else 2
	var normal_axis := 2 if orientation in ["front", "back"] else 0
	var dimensions: Vector3 = view["dimensions"]
	var plane := snappedf(dimensions[normal_axis] * 0.5, Grid.UNIT)
	for transform_value in _instances(visual):
		# Same wall only: the facing sits just outside the wall the door is on.
		if absf(transform_value.origin[normal_axis]) > plane + 0.5 or absf(transform_value.origin[normal_axis]) < plane - 0.5: continue
		if signf(transform_value.origin[normal_axis]) != signf(position[normal_axis]): continue
		if absf(transform_value.origin[tangent_axis] - position[tangent_axis]) <= 0.375 and absf(transform_value.origin.y - position.y) <= 1.35: return false
	return true

## Which batch and instance a transform came from, for failure messages.
func _describe(visual: Node, value: Transform3D) -> String:
	for node in _tone_nodes(visual):
		var multi: MultiMesh = (node as MultiMeshInstance3D).multimesh
		for index in multi.instance_count:
			if multi.get_instance_transform(index) == value:
				return "%s#%d %s" % [str(node.name), index, _transform_text(value)]
	return _transform_text(value)

func _run() -> void:
	var cottage_view := _view("riverside_cottage")
	check(not cottage_view.is_empty(), "riverside cottage preview resolves")
	if cottage_view.is_empty():
		_finish()
		return
	var document_before := JSON.stringify(cottage_view)
	var cottage := _build(cottage_view)
	var tone_nodes := _tone_nodes(cottage)

	# --- part 1: cottage brick coursing -------------------------------------
	check(tone_nodes.size() >= BRICK_TONE_MIN and tone_nodes.size() <= BRICK_TONE_MAX, "cottage lays 4-7 brick tones, one batch each (got %d)" % tone_nodes.size())
	var used := 0
	var lightest := 1.0
	var darkest := 0.0
	var family := true
	for node in tone_nodes:
		var colour := _tone_colour(node)
		var instances: int = (node as MultiMeshInstance3D).multimesh.instance_count
		check(instances > 0, "brick tone %s is used by real geometry" % str(node.name))
		if instances > 0: used += 1
		family = family and colour.r > colour.g and colour.g > colour.b and colour.s > 0.25
		lightest = maxf(lightest if lightest < 1.0 else colour.v, colour.v)
		darkest = minf(darkest if darkest > 0.0 else colour.v, colour.v)
	check(family, "every brick tone stays a darker cut of the warm wall tone (never a cold hue)")
	check(lightest - darkest >= 0.15, "brick tones spread across the family (value spread %.3f)" % (lightest - darkest))

	var brick_count := 0
	for transform_value in _instances(cottage):
		brick_count += 1
	check(brick_count > 200, "cottage coursing covers the walls (%d bricks)" % brick_count)
	notes.append("riverside_cottage: %d tone batches, %d bricks, child_count=%d" % [tone_nodes.size(), brick_count, cottage.get_child_count()])

	check(str((cottage.get_node("WallFront") as MeshInstance3D).material_override.albedo_color) == str(Color("#e7cfab")), "the authored wall material tone is unchanged")
	check(JSON.stringify(cottage_view) == document_before, "coursing is presentation-only: the building record is untouched")

	# Record-level fixtures used by the geometry checks below.
	var orientations := {}
	for surface_value in cottage_view.get("surfaces", []):
		var surface: Dictionary = surface_value
		orientations[str(surface.get("id", ""))] = str(surface.get("orientation", ""))
	var door := {}
	for detail_value in cottage_view.get("details", []):
		var detail: Dictionary = detail_value
		if str(detail.get("kind", "")) == "door" and detail.get("resolved_position") is Vector3: door = detail
	check(not door.is_empty(), "cottage fixture exposes a door anchor")

	if not _has_geometry():
		notes.append("geometry checks skipped: the headless Dummy renderer keeps no instance buffers")
	else:
		var on_grid := true
		var clear_of_wall := true
		var min_clearance := 99.0
		var worst := ""
		for transform_value in _instances(cottage):
			var world_scale := transform_value.basis.get_scale() * MINIATURE
			var world_origin := transform_value.origin * MINIATURE
			# Boxes are whole fine cells with their edges on the fine grid; a centre
			# may legitimately sit half a cell off when a brick is an odd cell count.
			for edge in [world_origin - world_scale * 0.5, world_origin + world_scale * 0.5]:
				on_grid = on_grid and is_equal_approx(snappedf(edge.x, Grid.COTTAGE_DETAIL_UNIT), edge.x)
				on_grid = on_grid and is_equal_approx(snappedf(edge.y, Grid.COTTAGE_DETAIL_UNIT), edge.y)
				on_grid = on_grid and is_equal_approx(snappedf(edge.z, Grid.COTTAGE_DETAIL_UNIT), edge.z)
			# Convert the clearance check into world space as well.
			var clearance := _wall_clearance(transform_value, cottage_view["dimensions"]) * MINIATURE
			if clearance < min_clearance:
				min_clearance = clearance
				worst = _describe(cottage, transform_value)
			clear_of_wall = clear_of_wall and clearance >= Grid.COTTAGE_DETAIL_UNIT - 0.0005
		check(on_grid, "every brick stays on the fine 0.0625 cell grid (added, never stretched)")
		check(clear_of_wall, "the facing keeps a full cell of mortar bed clear of the wall plane (min %.4f at %s)" % [min_clearance, worst])
		check(_opening_clear(cottage, cottage_view, door, orientations), "no brick is laid across the door opening")

	# --- determinism ---------------------------------------------------------
	var repeat := _build(_view("riverside_cottage"))
	check(_digest(repeat) == _digest(cottage), "a regenerated cottage lays byte-identical coursing")
	var second_view := _view("riverside_cottage")
	cottage.request_revision(1)
	check(cottage.apply_building(second_view, 1), "cottage can re-apply a later revision")
	check(_digest(cottage) == _digest(repeat), "re-applying the same recipe rebuilds identical coursing")

	# --- every wall carries the accent-brick character -----------------------
	# The user saw one wall read plain against a bricked side: hash columns used
	# to count from a centred space, so a wide wall could expose outer regions no
	# other wall ever showed. Columns now count from each wall's left edge, so
	# all walls sample the same accent map. The boxes are pure math (no renderer
	# needed), so this balance check runs headless too.
	var per_wall := {"front": 0, "back": 0, "left": 0, "right": 0}
	var dim: Vector3 = cottage_view["dimensions"]
	for tone_boxes in (cottage as Node).get("_tone_boxes"):
		for box in tone_boxes:
			var c: Vector3 = box["center"]
			var dx := absf(c.x) - dim.x * 0.5
			var dz := absf(c.z) - dim.z * 0.5
			var which := "front" if dz >= dx and c.z < 0 else ("back" if dz >= dx else ("left" if c.x < 0 else "right"))
			per_wall[which] += 1
	var wall_min := -1.0
	var wall_max := 0.0
	for k in per_wall:
		check(per_wall[k] > 0, "wall %s carries accent bricks (count %d)" % [k, per_wall[k]])
		wall_min = float(per_wall[k]) if wall_min < 0.0 else minf(wall_min, float(per_wall[k]))
		wall_max = maxf(wall_max, float(per_wall[k]))
	check(wall_min >= 0.0 and wall_min / wall_max >= 0.5, "accent density is balanced across walls (min/max %.2f, front %d back %d left %d right %d)" % [wall_min / wall_max, per_wall["front"], per_wall["back"], per_wall["left"], per_wall["right"]])

	# --- part 2: timber-framed village gable ---------------------------------
	var tudor_view := _view("village_gable")
	var tudor := _build(tudor_view)
	var tudor_nodes := _tone_nodes(tudor)
	var material_colour: Color = (tudor.get_node("WallFront") as MeshInstance3D).material_override.albedo_color
	check(material_colour == Color("#e8e2d5"), "village gable shell keeps its chalk-white material tone")
	var subtle := not tudor_nodes.is_empty()
	var distinct_from_brick := true
	for node in tudor_nodes:
		var colour := _tone_colour(node)
		subtle = subtle and maxf(maxf(absf(colour.r - material_colour.r), absf(colour.g - material_colour.g)), absf(colour.b - material_colour.b)) <= 0.08
		for brick in CottageVisualScript.BRICK_TONES:
			distinct_from_brick = distinct_from_brick and colour.to_html() != (brick as Color).to_html()
	check(not tudor_nodes.is_empty(), "village gable walls carry plaster mottling")
	check(subtle, "plaster mottling stays subtle around the chosen wall material")
	check(distinct_from_brick, "plaster mottling is not brick coursing")
	check(tudor.get_node_or_null("TudorWallFrame") != null, "timber framing still renders over the mottled plaster")
	check(_digest(_build(_view("village_gable"))) == _digest(tudor), "village gable mottling is deterministic")
	notes.append("village_gable: %d mottle batches, %d patches" % [tudor_nodes.size(), _instances(tudor).size()])

	# --- untouched neighbours -----------------------------------------------
	var lodge := _build(_view("woodland_lodge"))
	check(_tone_nodes(lodge).is_empty(), "woodland lodge log walls keep their existing course variation only")
	var lodge_courses := 0
	for child_value in lodge.get_children():
		if str((child_value as Node).name).begins_with("LogCourses"): lodge_courses += 1
	check(lodge_courses >= 2, "woodland lodge still varies per log course (%d batches)" % lodge_courses)
	var wood_cottage := _build(_view("riverside_cottage", "timber"))
	check(_tone_nodes(wood_cottage).is_empty(), "a timber-walled cottage is not bricked over")

	_finish()

func _finish() -> void:
	for line in notes: print("NOTE " + line)
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
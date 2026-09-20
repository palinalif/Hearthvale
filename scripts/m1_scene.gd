extends Node3D
## Controller-first M1 playtest: one cottage recipe beside a volumetric bank.

const PATCH_SIZE := Vector3i(preload("res://scripts/m2_world_bounds.gd").EXTENT)
const BUILDING_ID := "building-1"
const M1PatchGenerator = preload("res://scripts/m1_patch_generator.gd")
const BuildingWorldScript = preload("res://scripts/building_world.gd")
const CottageVisualScript = preload("res://scripts/cottage_visual.gd")
const BrushPreviewScript = preload("res://scripts/brush_preview.gd")
const CursorReticleScript = preload("res://scripts/m1_cursor_reticle.gd")
const LandscapeScript = preload("res://scripts/landscape_state.gd")
const Grid = preload("res://scripts/visual_grid.gd")
const Flora = preload("res://scripts/vegetation_mesh.gd")

const GardenVisualScript = preload("res://scripts/m1_garden_visual.gd")
const WaterVisualScript = preload("res://scripts/water_visual.gd")
const PremadeRiver = preload("res://scripts/premade_river.gd")

@export var checkpoint_root := "user://m1_checkpoints"
@export var test_mode := false

var backend: Node
var building_world: RefCounted
var cottage_visual: Node3D
var cottage_visuals: Dictionary = {}
var brush_preview: Node3D
var preview_cells: Array[Vector3i] = []
var preview_center := Vector3.ZERO
var _preview_key := ""
var cursor := Vector3(32.0, 8.0, 28.0)
var terrain_cursor := Vector3(32.0, 8.0, 28.0)
var cottage_cursor := Vector3(22.0, 10.0, 18.0)
var camera_yaw := -1.1
var camera_pitch := 0.66
var camera_distance := 36.0
var brush_radius := 2.0
var brush_strength := 6.0
var brush_falloff := 0.45
var height_snap_enabled := false
var reference_mode := "ground"
var sculpt_tool := "raise"
var view_context := "terrain"
var precision_mode := false
var menu_open := false
var tools_open := false
var detail_open := false
var selected_detail_id := ""
var selected_surface_id := ""
var selected_building_id := BUILDING_ID
var detail_move_active := false
var detail_move_position := Vector3.ZERO
var detail_move_surface_id := ""
var resize_active := false
var resize_locked := false
var resize_dimensions := Vector3.ZERO
var resize_preview_dimensions := Vector3.ZERO
var resize_accumulator := Vector3.ZERO
var resize_axis := "width"
var stroke_active := false
var stroke_reference: Dictionary = {}
var stroke_surface_normal := Vector3.UP
var stroke_aim_offset := Vector3.ZERO
var keep_reference := false
var status_text := "Loading cottage…"
var last_frame_costs: Dictionary = {}
# Worst-frame peak tracker (debug builds only): catches the hitch frames the
# last-frame costs miss. A rolling 180-frame (3 s at 60) window so the record
# decays when the game recovers; the "reset_peaks" action clears it on demand.
var worst_frame_costs: Dictionary = {}
var worst_frame_ms := 0.0
# Peak real-time delta between _process callbacks (ms) over the same window.
# Godot's delta includes the main loop's wait for the render pipeline, so a
# GPU-side stall (the user's 1-2 s post-stroke freezes) shows up here even
# when process_ms stays small. 2026-09-19: Godot 4.7 has no GPU frame-time
# monitor, this is the closest in-app proxy for perceived frame time.
var worst_frame_delta_ms := 0.0
var worst_frame_at_ms := 0
var _peak_window_frames := 0
# Frame-clock probe marks (debug builds only; the probe reads these across scripts).
var _fc_scene_start := 0
var _fc_scene_end := 0
var _frame_clock_probe: Node = null
var _last_focus := true
var _shutting_down := false
var _pause_buttons: Dictionary = {}
var _tool_buttons: Dictionary = {}
var _presentation_key := ""

## Shared per-frame presentation gate for the deep scene chain: true on the
## first frame and on frames where the building or terrain revision changed.
## Chain-level presentation gate (2026-09-19, v44 device profiling). The
## _update_presentation chain cost ~15ms/frame even when nothing changed
## (~10 feature classes x 1-2ms of per-frame key work), capping the game at
## ~33fps. The live loop now computes presentation_gate_key() and only calls
## the chain when it changes: building/terrain revision, selection, view,
## menus, or any active preview operation (cursor included while one runs).
var _presentation_gate_key := ""

func presentation_gate_key() -> String:
	var brev: int = building_world.get_revision() if building_world else -1
	var trev: int = int((backend.stats() as Dictionary).get("revision", -1)) if backend and backend.has_method("stats") else -1
	var s := "%d|%d|%s|%s" % [brev, trev, str(selected_building_id), view_context]
	# Base-declared flags read directly; derived-class flags come from the same
	# node instance (one inheritance chain = one object). Dynamic get stays
	# isolated here, per the project's adapter rule.
	var active_op: int = (1 if stroke_active else 0) + (1 if landscape_active else 0) + (1 if detail_move_active else 0) + (1 if resize_active else 0)
	for derived_flag in ["building_placement_active", "portion_placement_active", "roof_accessory_placement_active", "_surface_material_picker_open", "_house_shape_picker_open", "_roof_design_picker_open", "water_placement_active"]:
		if get(derived_flag) == true:
			active_op += 1
	s += "|%d|%d" % [active_op, 1 if _restoring else 0]
	if active_op > 0:
		# Cursor and preview center move every frame during an op (live preview
		# needs the chain), but preview_center is recomputed from the camera
		# raycast even while idle (2026-09-19: including it unconditionally
		# re-dirtied the gate every idle frame, defeating the whole gate).
		s += "|%.2f|%.2f|%.2f|%.2f|%.2f" % [cursor.x, cursor.z, preview_center.x, preview_center.y, preview_center.z]
	if detail_move_active:
		s += "|%.2f|%.2f|%.2f" % [detail_move_position.x, detail_move_position.y, detail_move_position.z]
	if resize_active:
		s += "|%.2f|%.2f|%.2f" % [resize_preview_dimensions.x, resize_preview_dimensions.y, resize_preview_dimensions.z]
	s += "|%d|%d|%d|%d|%.1f|%.1f" % [1 if menu_open else 0, 1 if tools_open else 0, 1 if detail_open else 0, 1 if precision_mode else 0, brush_strength, brush_falloff]
	return s
var _last_requested_cottage_revision := -1
var _last_target_label_text := ""
var _history_tags: Array[String] = []
var _redo_tags: Array[String] = []
var _building_dirty := false
var _restoring := false
var _player_restored := false
var _review_menu_after_ready := false
var _review_clean := false
var _review_edited := false
var _blocked_until_accept_release := false

var camera: Camera3D
var hud: CanvasLayer
var status_label: Label
var context_label: Label
var target_label: Label
var debug_label: Label
var pause_panel: PanelContainer
var tools_panel: PanelContainer
var decor_root: Node3D
var resize_handles: Node3D
var reference_plane: MeshInstance3D
var terrain_hit_marker: MeshInstance3D
var cursor_reticle: Node3D
var river_water: MeshInstance3D
var _river_water_spans: Array[Vector2i] = []
var garden_visual: Node3D
var water_visual: Node3D
var landscape_state := LandscapeScript.new()
var landscape_active := false
var _landscape_before: Dictionary = {}
var _landscape_history: Array[Dictionary] = []
var _landscape_redo: Array[Dictionary] = []
var _plant_elapsed := 0.0
var _plant_last := Vector3.INF
var _plant_sequence := 0
var planting_yaw_degrees := 0.0

const PLANT_ROTATION_COARSE_DEGREES := 15.0
const PLANT_ROTATION_FINE_DEGREES := 1.0

var _terrain_target_valid := false
var _terrain_target_point := Vector3.ZERO
var _terrain_target_normal := Vector3.UP
var _terrain_action_labels: Array[String] = ["Raise", "Dig", "Level", "Slope", "Smooth", "Foliage brush", "Tree brush", "Clear planting", "Radius +", "Radius -", "Strength +", "Strength -", "Falloff +", "Falloff -", "Height snap: off", "Reference: ground", "Reference: wall", "Reference: ceiling", "Resample reference", "Keep reference"]
var _cottage_action_labels: Array[String] = ["Move selected window", "Support: next", "Support: previous", "Replace selected", "Suppress / restore", "Reattach selected", "Add flower box", "Add shutter", "Delete selected surface", "Material: warm plaster", "Miniature scale", "Duplicate cottage", "Close"]

## Tracked signal bookkeeping. Every connection the scene makes goes through
## _track_connect so _exit_tree can disconnect each one exactly once when the
## scene leaves the tree. Entries: {emitter: Object, signal: String, callable: Callable}.
var _signal_teardown: Array = []

func _track_connect(emitter: Object, signal_name: String, callable: Callable) -> void:
	if emitter == null or not emitter.has_signal(signal_name):
		return
	if emitter.is_connected(signal_name, callable):
		return
	emitter.connect(signal_name, callable)
	_signal_teardown.append({"emitter": emitter, "signal": signal_name, "callable": callable})

func _disconnect_tracked_signals() -> void:
	for entry in _signal_teardown:
		if not (entry is Dictionary):
			continue
		var emitter: Object = entry.get("emitter")
		var signal_name: String = str(entry.get("signal", ""))
		var callable_value: Variant = entry.get("callable")
		if emitter != null and emitter.has_signal(signal_name) and callable_value is Callable and emitter.is_connected(signal_name, callable_value):
			emitter.disconnect(signal_name, callable_value)
	_signal_teardown.clear()

func _exit_tree() -> void:
	_disconnect_tracked_signals()

func _ready() -> void:
	get_window().title = "Hearthvale — M1"
	_setup_input_map()
	_apply_review_args()
	_build_world()
	_build_ui()
	if _review_clean: hud.visible = false
	_create_backend()
	_last_focus = get_window().has_focus()
	_update_camera()
	_set_status(status_text)
	_track_connect(backend, "ready_changed", _on_backend_ready)
	_track_connect(backend, "changed", _on_backend_changed)
	_track_connect(Input, "joy_connection_changed", _on_joy_connection_changed)
	_track_connect(building_world, "changed", _on_building_changed)
	if backend and backend.has_method("is_ready") and backend.is_ready(): _on_backend_ready(true)
	# Debug-only virtual-controller + telemetry bridge (localhost TCP, loopback
	# only, OS.is_debug_build()-gated). Inert in release builds; see the script.
	if OS.is_debug_build():
		var bridge: Node = load("res://scripts/m1_debug_bridge.gd").new()
		bridge.name = "virtual_controller_bridge"
		add_child(bridge)
		# Main-loop frame clock. Child of the scene root (children process
		# before their parent, so it brackets the scene _process "pre").
		# NOT get_tree().root.add_child(): during the main scene's _ready() the
		# Window root is busy setting up children and the add fails silently
		# (the probe then never runs and frame_clock reports all zeros).
		var fc: Node = load("res://scripts/frame_clock_probe.gd").new()
		fc.name = "FrameClockProbe"
		fc.set("scene", self)
		add_child(fc)
		_frame_clock_probe = fc

## Debug-only semantic action API for the virtual-controller bridge (see
## scripts/m1_debug_bridge.gd). Each verb calls the *same handler functions the
## real input uses* (virtual dispatch, so subclass overrides win); the bridge
## stays the input-injection + telemetry path for the rest of the interaction.
## Debug builds only, loopback only, unreachable in release.
func debug_test_action(name: String, args: Array) -> Dictionary:
	if not OS.is_debug_build():
		return {"type": "error", "message": "debug build only"}
	match name:
		"reset_peaks":
			worst_frame_costs = {}
			worst_frame_ms = 0.0
			worst_frame_at_ms = 0
			worst_frame_delta_ms = 0.0
			_peak_window_frames = 0
			return {"type": "ok", "reset": true}
		"state":
			return {
				"type": "state", "tool": sculpt_tool, "stroke_active": stroke_active,
				"landscape_active": landscape_active, "view_context": view_context,
				"menu_open": menu_open, "tools_open": tools_open,
				"water_placement_active": get("water_placement_active"),
				"water_stroking": get("water_stroking"), "water_kind": get("water_kind"),
				"cursor": [cursor.x, cursor.y, cursor.z],
			}
		"composition_dump":
			# Debug: dump the authoritative M2 composition records (id/kind/style/
			# position/size/yaw/colour) so a scripted placement can be verified
			# on-device without a save round-trip. M2-only: no-op elsewhere.
			var ls: Variant = get("landscape_state")
			if ls == null or not ls.has("composition"):
				return {"type": "error", "message": "no composition in this scene"}
			var rows: Array = []
			var comp: Variant = ls.get("composition")
			if comp is Array:
				for rec in comp:
					if rec is Dictionary:
						rows.append({
							"id": int(rec.get("id", -1)),
							"kind": str(rec.get("kind", "")),
							"style": str(rec.get("style_id", "")),
							"pos": rec.get("position", []),
							"size": rec.get("size", []),
							"yaw": int(rec.get("yaw_quarters", 0)),
							"colour": str(rec.get("colour_id", "")),
						})
			return {"type": "composition", "count": rows.size(), "records": rows}
		"shell_keys":
			# Diagnostic (2026-09-19, idle-15fps hunt): per-house massing cache key plus
			# its raw field components, so a two-call diff shows which field drifts
			# frame-to-frame and defeats the idle skip. Debug builds only.
			if not has_method("_massing_shell_key"):
				return {"type": "error", "message": "no massing layer in this scene"}
			var keys_out: Dictionary = {"type": "shell_keys", "revision": building_world.get_revision() if building_world else -1, "terrain_revision": int((backend.stats() as Dictionary).get("revision", -1)) if backend and backend.has_method("stats") else -1, "ops": call("_dbg_ops_read"), "houses": {}}
			var last_variant: Variant = get("_last_shell_key")
			var last_map: Dictionary = last_variant if last_variant is Dictionary else {}
			for bid in cottage_visuals:
				var bid_str := str(bid)
				var v: Dictionary = building_world.get_building(bid_str) if building_world else {}
				if v.is_empty(): continue
				var secs: Variant = v.get("massing_sections")
				var dims_variant: Variant = v.get("dimensions", Vector3.ZERO)
				var tr_variant: Variant = v.get("transform", Transform3D.IDENTITY)
				var k := str(call("_massing_shell_key", v))
				(keys_out["houses"] as Dictionary)[bid_str] = {
					"key": k, "last_match": str(last_map.get(bid_str, "")) == k,
					"dims": str(dims_variant),
					"transform_hash": hash(str(tr_variant)),
					"wall": str(v.get("wall_material_id", v.get("material_id", ""))),
					"roof": str(v.get("roof_material_id", "")),
					"sections": str(secs), "sections_hash": hash(str(secs))
				}
			return keys_out
		"cursor_set":
			# args: [x, y, z]; debug teleport of the world cursor to a known
			# terrain position (e.g. a house pad) so scripted strokes are
			# deterministic. The cursor is the brush position; only the LEFT
			# stick moves it in normal play (the right stick orbits the camera
			# and can never arm a stroke).
			if args.size() < 3:
				return {"type": "error", "message": "cursor_set needs [x, y, z]"}
			var p := Vector3(
				clampf(float(args[0]), 0.5, float(PATCH_SIZE.x) - 0.5),
				clampf(float(args[1]), 0.0, 31.0),
				clampf(float(args[2]), 0.5, float(PATCH_SIZE.z) - 0.5)
			)
			cursor = p
			if view_context == "terrain": terrain_cursor = p
			else: cottage_cursor = p
			return {"type": "ok", "cursor": [p.x, p.y, p.z]}
		"select_tool":
			if args.size() < 1: return {"type": "error", "message": "select_tool needs a tool name"}
			if not has_method("_select_terrain_tool"):
				return {"type": "error", "message": "no terrain tool selector in this scene"}
			# Dynamic call: the selector lives in a downstream chain link (m1_scene_tool_ui)
			# and is overridden further down (m2_scene_water), so dispatch must be virtual.
			call("_select_terrain_tool", str(args[0]))
			return {"type": "ok", "tool": sculpt_tool}
		"view_context":
			if args.size() < 1: return {"type": "error", "message": "view_context needs terrain|building"}
			_set_view_context(str(args[0]), "debug")
			return {"type": "ok", "view_context": view_context}
		"furniture_select":
			# Debug: arm the real street-furniture placement mode through the
			# same entry point the build browser calls (m2_scene_street_furniture).
			# M2-only: an m1 scene without the furniture layer reports so.
			if args.size() < 1:
				return {"type": "error", "message": "furniture_select needs a style id"}
			if not has_method("_choose_furniture_style"):
				return {"type": "error", "message": "no furniture catalogue in this scene"}
			call("_choose_furniture_style", str(args[0]))
			return {
				"type": "ok", "style": str(args[0]),
				"placement": bool(get("detail_placement_active")),
				"kind": str(get("detail_kind")),
			}
		"furniture_commit":
			# Debug: commit the armed furniture placement at the current cursor
			# (the same shared transaction the A button uses).
			if not has_method("_commit_furniture"):
				return {"type": "error", "message": "no furniture placement in this scene"}
			if bool(call("_commit_furniture")):
				return {"type": "ok", "committed": true}
			var reason := str(get("detail_placement_reason"))
			return {"type": "error", "message": reason if reason != "" else "placement not active"}
		"cancel":
			_cancel_current_edit("debug")
			return {"type": "ok"}
		"undo":
			_undo(); return {"type": "ok"}
		"redo":
			_redo(); return {"type": "ok"}
		"world_stats":
			return _debug_world_stats()
		"mesh_survey":
			return _debug_mesh_survey()
		"tune":
			# args: [target, key, value]; target is terrain or viewer.
			# Debug A/B lever for the native terrain/viewer knobs found by
			# mesh_survey. Only the allowlisted performance knobs are settable.
			if args.size() < 3:
				return {"type": "error", "message": "tune needs [target, key, value]"}
			# str(), not the String() constructor: in the pinned Godot 4.7.2 build a
			# String() call on these arguments aborts the whole action with
			# "Invalid call 'String' constructor" (tune silently no-ops, returns {}).
			var target := str(args[0])
			var key := str(args[1])
			var raw := str(args[2])
			var allow: Dictionary
			match target:
				"terrain", "viewer":
					allow = {
						"view_distance": "float", "view_distance_vertical_ratio": "float",
						"max_view_distance": "float", "use_gpu_generation": "bool",
						"generate_collisions": "bool", "automatic_loading_enabled": "bool",
						"mesh_block_size": "float", "process_mode": "float",
					"visible": "bool", # A/B isolation: which viewer's mesh is actually drawn
					}
				"light":
					allow = {"shadow_enabled": "bool", "directional_shadow_max_distance": "float"}
				"environment":
					allow = {"glow_enabled": "bool", "fog_enabled": "bool"}
				_:
					return {"type": "error", "message": "tune target not allowed: %s" % target}
			if not allow.has(key):
				return {"type": "error", "message": "tune key not allowed: %s" % key}
			var value: Variant
			if allow[key] == "bool":
				value = raw.to_lower() == "true" or raw == "1"
			else:
				value = raw.to_float()
			if key == "process_mode":
				value = int(value)
			var applied := 0
			var last: Variant = null
			var want_index := -1
			if args.size() >= 4:
				want_index = int(args[3])
			var match_index := 0
			if get_tree().current_scene != null:
				var tstack: Array[Node] = [get_tree().current_scene]
				while tstack.size() > 0:
					var n: Node = tstack.pop_back()
					for c in n.get_children():
						tstack.push_back(c)
					var want := (target == "terrain" and n.get_class() == "VoxelTerrain") \
						or (target == "viewer" and n.get_class() == "VoxelViewer") \
						or (target == "light" and n is DirectionalLight3D and n.name == "WorldSun") \
						or (target == "environment" and n is WorldEnvironment)
					if want:
						if want_index < 0 or match_index == want_index:
							if target == "environment" and n.environment != null:
								n.environment.set(key, value)
								last = n.environment.get(key)
							else:
								n.set(key, value)
								last = n.get(key)
								applied += 1
						match_index += 1
			return {"type": "ok", "applied": applied, "key": key, "now": str(last)}
		"perf":
			# Phase-level CPU attribution for on-device profiling: the scene's own
			# per-frame phase timers plus the native backend's last-edit cost.
			var profile: Dictionary = call("path_profile_stats") if has_method("path_profile_stats") else {}
			var water_perf: Dictionary = get("water_visual").get_perf() if get("water_visual") != null and get("water_visual").has_method("get_perf") else {}
			var fps_now := Engine.get_frames_per_second()
			return {
				"type": "perf",
				"fps": fps_now,
				"frame_ms": 1000.0 / maxf(fps_now, 0.001),
				"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				"prims": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
				"last_frame_costs": last_frame_costs.duplicate(true),
				"worst_frame": {
					"ms": worst_frame_ms,
					"delta_ms": worst_frame_delta_ms,
					"age_ms": Time.get_ticks_msec() - worst_frame_at_ms,
					"costs": worst_frame_costs.duplicate(true),
				},
				"path_profile": profile,
				"native": backend.stats() if backend != null and backend.has_method("stats") else {},
				"water": water_perf,
			}
		"frame_clock":
			# Main-loop bracketing from the root-level probe: pre (engine/input/
			# pre-scene nodes), scene (the chain's measured process), post
			# (post-scene nodes + physics + render hand-off + vsync wait).
			if _frame_clock_probe != null:
				# The probe is Node-typed in the scene; hop through Variant so the
				# dynamic read() call still parses (typed Node has no read()).
				var probe: Variant = _frame_clock_probe
				var out: Dictionary = probe.read()
				out["type"] = "ok"
				return out
			return {"type": "error", "message": "no frame clock (release build?)"}
		"probe_nodes":
			# Debug A/B binary search over the scene tree: hide/show or disable/enable
			# every node matching a class or name, one call. args: [selector, op],
			# selector = "class:MultiMeshInstance3D" or "name:WaterVisual";
			# op = hide | show | disable | enable. Returns how many were touched.
			if args.size() < 2:
				return {"type": "error", "message": "probe_nodes needs [selector, op]"}
			var sel := str(args[0])
			var op := str(args[1])
			var cls := ""
			var nod := ""
			if sel.begins_with("class:"): cls = sel.trim_prefix("class:")
			elif sel.begins_with("name:"): nod = sel.trim_prefix("name:")
			else:
				return {"type": "error", "message": "selector must be class:X or name:X"}
			var touched := 0
			if get_tree().current_scene != null:
				var pstack: Array[Node] = [get_tree().current_scene]
				while pstack.size() > 0:
					var p: Node = pstack.pop_back()
					for c in p.get_children():
						pstack.push_back(c)
					var hit := (cls != "" and p.get_class() == cls) or (nod != "" and p.name == nod)
					if not hit:
						continue
					match op:
						"hide": p.visible = false
						"show": p.visible = true
						"disable": p.process_mode = Node.PROCESS_MODE_DISABLED
						"enable": p.process_mode = Node.PROCESS_MODE_INHERIT
						_: return {"type": "error", "message": "op must be hide|show|disable|enable"}
					touched += 1
			return {"type": "ok", "touched": touched, "selector": sel, "op": op}
		"tree_survey":
			# Debug: enumerate the live scene tree (name/class/process flags) so an
			# on-device binary search can target nodes by name (many preview nodes
			# have generic classes and no class_name).
			var rows: Array = []
			var cap := 600
			if get_tree().current_scene != null:
				var sstack: Array[Node] = [get_tree().current_scene]
				while sstack.size() > 0 and rows.size() < cap:
					var sn: Node = sstack.pop_back()
					rows.append({"n": sn.name, "c": sn.get_class(), "p": sn.is_processing()})
					for c in sn.get_children():
						sstack.push_back(c)
			return {"type": "ok", "count": rows.size(), "rows": rows}
		_:
			return {"type": "error", "message": "unknown action: " + name}

## One-shot render-cost snapshot: how many visible meshes we ship and where the
## triangles live (terrain / trees / houses / water / props). Lets a playtest
## answer "why is my world slow" without guessing — a stale dense forest world
## shows up instantly (1.5M+ tris across thousands of tree meshes) versus the
## ~158k-class current starter valley. Debug builds only.
func _debug_world_stats() -> Dictionary:
	var meshes := 0
	var tris := 0
	var by_cat: Dictionary = {}
	var root_node: Node = get_tree().current_scene
	if root_node == null:
		root_node = self
	var stack: Array[Node] = [root_node]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if not mi.visible or mi.mesh == null or not (mi.mesh is ArrayMesh):
				continue
			var am := mi.mesh as ArrayMesh
			meshes += 1
			var t := 0
			for s in am.get_surface_count():
				var arr: Array = am.surface_get_arrays(s)
				var index: Variant = arr[Mesh.ARRAY_INDEX]
				if index != null and index.size() > 0:
					t += index.size() / 3
				else:
					var verts: Variant = arr[Mesh.ARRAY_VERTEX]
					if verts != null and verts.size() > 0:
						t += verts.size() / 3
			tris += t
			var path := String(n.get_path()).to_lower()
			var cat := "other"
			if path.contains("water"):
				cat = "water"
			elif path.contains("tree"):
				cat = "trees"
			elif path.contains("foliage") or path.contains("flower") or path.contains("mushroom") or path.contains("rock"):
				cat = "foliage/props"
			elif path.contains("house") or path.contains("cottage") or path.contains("roof") or path.contains("wall") or path.contains("door") or path.contains("window"):
				cat = "houses/buildings"
			elif path.contains("terrain") or path.contains("voxel") or path.contains("chunk"):
				cat = "terrain"
			by_cat[cat] = int(by_cat.get(cat, 0)) + t
	return {
		"type": "world_stats", "meshes": meshes, "tris": tris, "by_cat": by_cat,
		"fps": Engine.get_frames_per_second(),
	}

## One-shot render survey: what is actually on the GPU. Complements
## _debug_world_stats (which only sees MeshInstance3Ds in the scene graph) by
## counting MultiMesh instances (meadow etc.) and probing the native
## VoxelTerrain/VoxelViewer for their mesh payload, so an on-device playtest
## can say exactly where the prims come from. Debug builds only.
func _debug_mesh_survey() -> Dictionary:
	var class_counts: Dictionary = {}
	var multimesh: Dictionary = {}
	var terrain_info: Dictionary = {}
	var viewer_info: Array = []
	var mesher_info: Dictionary = {}
	var meshi_visible := 0
	var meshi_tris := 0
	var native_idx := 0
	var root_node: Node = get_tree().current_scene
	if root_node == null:
		return {"type": "error", "message": "no current scene"}
	var stack: Array[Node] = [root_node]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		var cn := n.get_class()
		class_counts[cn] = int(class_counts.get(cn, 0)) + 1
		if cn == "VoxelTerrain":
			terrain_info = _probe_mesh_holder(n)
			var m_obj: Variant = n.get("mesher")
			if m_obj != null:
				mesher_info = _probe_mesh_holder(m_obj)
		elif cn == "VoxelViewer":
			var v: Dictionary = _probe_mesh_holder(n)
			v["index"] = int(native_idx)
			native_idx += 1
			viewer_info.append(v)
		elif cn == "VoxelMesherBlocky":
			mesher_info = _probe_mesh_holder(n)
		elif n is MultiMeshInstance3D:
			var mmi := n as MultiMeshInstance3D
			multimesh[str(n.name)] = {
				"instances": mmi.multimesh.get_instance_count() if mmi.multimesh != null else 0,
				"tris_each": _mesh_tri_count(mmi.multimesh.mesh) if mmi.multimesh != null else 0,
				"visible": n.visible,
			}
		elif n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.visible and mi.mesh != null:
				meshi_visible += 1
				meshi_tris += _mesh_tri_count(mi.mesh)
	return {
		"type": "mesh_survey", "classes": class_counts, "multimesh": multimesh,
		"terrain": terrain_info, "viewer": viewer_info, "mesher": mesher_info,
		"meshi_visible": meshi_visible, "meshi_tris": meshi_tris,
		"prims": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"fps": Engine.get_frames_per_second(),
	}

func _probe_mesh_holder(obj: Object) -> Dictionary:
	var info: Dictionary = {"class": obj.get_class()}
	if "mesh" in obj:
		var m: Variant = obj.get("mesh")
		if m == null:
			info["mesh"] = "null"
		elif m is ArrayMesh:
			info["mesh"] = "ArrayMesh tris=%d" % _mesh_tri_count(m)
		else:
			info["mesh"] = String((m as Object).get_class())
			if (m as Object).has_method("get_mesh"):
				var inner: Variant = (m as Object).call("get_mesh")
				if inner is ArrayMesh:
					info["inner"] = "ArrayMesh tris=%d" % _mesh_tri_count(inner)
				elif inner != null:
					info["inner"] = String((inner as Object).get_class())
	else:
		info["has_mesh_prop"] = false
	# Native GDExtension objects (VoxelViewer/VoxelTerrain/VoxelMesherBlocky):
	# enumerate the actual property surface of the pinned build so device
	# evidence names the knobs that exist, without guessing.
	var plist := obj.get_property_list()
	var names := PackedStringArray()
	var values: Dictionary = {}
	for pd in plist:
		var pname: String = str((pd as Dictionary).get("name", ""))
		names.append(pname)
		values[pname] = str(obj.get(pname))
	names.sort()
	info["props"] = names
	info["values"] = values
	return info

func _mesh_tri_count(m: Mesh) -> int:
	if m == null or not (m is ArrayMesh):
		return 0
	var am := m as ArrayMesh
	var t := 0
	for s in am.get_surface_count():
		var arr: Array = am.surface_get_arrays(s)
		var index: Variant = arr[Mesh.ARRAY_INDEX]
		if index != null and index.size() > 0:
			t += index.size() / 3
		else:
			var verts: Variant = arr[Mesh.ARRAY_VERTEX]
			if verts != null and verts.size() > 0:
				t += verts.size() / 3
	return t

func _process(delta: float) -> void:
	if _shutting_down: return
	if (stroke_active or landscape_active) and (menu_open or tools_open or detail_open or _restoring):
		_cancel_current_edit("Sculpting cancelled")
	var process_started := Time.get_ticks_usec()
	_fc_scene_start = process_started
	var phase_started := process_started
	if not menu_open and not tools_open and not detail_open:
		_read_camera_and_cursor(delta)
	if detail_move_active and not menu_open and not tools_open and not detail_open:
		_read_detail_move(delta)
	last_frame_costs["camera_ms"] = (Time.get_ticks_usec() - phase_started) / 1000.0
	phase_started = Time.get_ticks_usec()
	if stroke_active and backend and backend.has_method("update_stroke"):
		backend.update_stroke(cursor + stroke_aim_offset, delta)
	last_frame_costs["sculpt_ms"] = (Time.get_ticks_usec() - phase_started) / 1000.0
	if landscape_active: _update_plant_stroke(delta)
	phase_started = Time.get_ticks_usec()
	_update_camera()
	# Keep native terrain mesh streaming centered on the camera, at a radius
	# that still covers the whole finite valley (whole-world viewer radius).
	if backend != null and backend.has_method("update_visual_focus"):
		backend.update_visual_focus(camera.global_position)
	last_frame_costs["focus_ms"] = (Time.get_ticks_usec() - phase_started) / 1000.0
	phase_started = Time.get_ticks_usec()
	_update_brush_preview()
	_update_cursor_reticle()
	last_frame_costs["preview_ms"] = (Time.get_ticks_usec() - phase_started) / 1000.0
	phase_started = Time.get_ticks_usec()
	_update_presentation()
	last_frame_costs["presentation_ms"] = (Time.get_ticks_usec() - phase_started) / 1000.0
	phase_started = Time.get_ticks_usec()
	_update_debug_overlay()
	last_frame_costs["overlay_ms"] = (Time.get_ticks_usec() - phase_started) / 1000.0
	last_frame_costs["process_ms"] = (Time.get_ticks_usec() - process_started) / 1000.0
	_fc_scene_end = Time.get_ticks_usec()
	var focused := get_window().has_focus()
	if not focused and _last_focus: _cancel_current_edit("Window focus lost")
	_last_focus = focused

func _notification(what: int) -> void:
	if _shutting_down: return
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_cancel_current_edit("Application suspended")
		_set_menu(true)
		if _world_is_dirty(): _save_all()

func _input(event: InputEvent) -> void:
	if _shutting_down: return
	if _blocked_until_accept_release:
		if event.is_action_released("m1_accept"):
			_blocked_until_accept_release = false
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_accept"):
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("m1_pause"):
		_set_menu(not menu_open)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("m1_view") and not menu_open:
		_set_view_context("terrain" if view_context == "building" else "building", "Context changed")
		get_viewport().set_input_as_handled()
		return
	if menu_open:
		_handle_menu_input(event)
		return
	if tools_open or detail_open:
		_handle_overlay_input(event)
		return
	if view_context == "building" and event.is_action_pressed("m1_cycle_left"):
		if resize_active:
			resize_axis = "depth" if resize_axis == "width" else "width"
			_set_status("Resize %s: left stick, D-pad up/down height" % resize_axis)
			get_viewport().set_input_as_handled(); return
		_cycle_building(-1); get_viewport().set_input_as_handled(); return
	if view_context == "building" and event.is_action_pressed("m1_cycle_right"):
		if resize_active:
			resize_axis = "depth" if resize_axis == "width" else "width"
			_set_status("Resize %s: left stick, D-pad up/down height" % resize_axis)
			get_viewport().set_input_as_handled(); return
		_cycle_building(1); get_viewport().set_input_as_handled(); return
	if event.is_action_pressed("m1_precision"):
		precision_mode = not precision_mode
		_set_status("Precision %s" % ("ON" if precision_mode else "OFF"))
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("m1_tools"):
		_open_actions_for_context()
		var buttons: Array = _visible_action_buttons()
		if not buttons.is_empty(): (buttons[0] as Button).grab_focus()
		get_viewport().set_input_as_handled()
		return
	if view_context == "terrain":
		if sculpt_tool in ["foliage", "tree"] and (event.is_action_pressed("m1_cycle_left") or event.is_action_pressed("m1_cycle_right")):
			_rotate_plant_brush(-1 if event.is_action_pressed("m1_cycle_left") else 1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_cancel"):
			_cancel_current_edit("Stroke cancelled")
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("m1_accept"):
			if _terrain_target_valid:
				if sculpt_tool in ["foliage", "tree", "clear_planting"]: _begin_plant_stroke()
				else: _begin_stroke()
			else: _set_status("No terrain target under cursor")
			get_viewport().set_input_as_handled()
		elif event.is_action_released("m1_accept"):
			if landscape_active: _end_plant_stroke()
			else: _end_stroke()
			get_viewport().set_input_as_handled()
	else:
		if event.is_action_pressed("m1_accept"):
			if detail_move_active:
				_commit_detail_move()
			elif resize_active: _commit_resize()
			else: _begin_resize()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("m1_cancel"):
			if detail_move_active: _cancel_detail_move()
			elif resize_active: _cancel_resize()
			else: _set_menu(true)
			get_viewport().set_input_as_handled()
		elif resize_active and event.is_action_pressed("m1_height_up"):
			var height_step := 0.25 if precision_mode else 1.0
			resize_accumulator.y = minf(resize_accumulator.y + height_step, BuildingWorldScript.MAX_DIMENSIONS.y)
			resize_preview_dimensions.y = snappedf(resize_accumulator.y, height_step)
			get_viewport().set_input_as_handled()
		elif resize_active and event.is_action_pressed("m1_height_down"):
			var height_step := 0.25 if precision_mode else 1.0
			resize_accumulator.y = maxf(resize_accumulator.y - height_step, BuildingWorldScript.MIN_DIMENSIONS.y)
			resize_preview_dimensions.y = snappedf(resize_accumulator.y, height_step)
			get_viewport().set_input_as_handled()
	if event.is_action_pressed("m1_undo"): _undo()
	if event.is_action_pressed("m1_redo"): _redo()

func _setup_input_map() -> void:
	_ensure_action("m1_accept"); _button("m1_accept", JOY_BUTTON_A); _key("m1_accept", KEY_ENTER)
	_ensure_action("m1_cancel"); _button("m1_cancel", JOY_BUTTON_B); _key("m1_cancel", KEY_ESCAPE)
	_ensure_action("m1_pause"); _button("m1_pause", JOY_BUTTON_START); _key("m1_pause", KEY_P)
	_ensure_action("m1_tools"); _button("m1_tools", JOY_BUTTON_X); _key("m1_tools", KEY_X)
	_ensure_action("m1_precision"); _button("m1_precision", JOY_BUTTON_LEFT_STICK); _key("m1_precision", KEY_F)
	_ensure_action("m1_view"); _button("m1_view", JOY_BUTTON_BACK); _key("m1_view", KEY_TAB)
	_ensure_action("m1_undo"); _button("m1_undo", JOY_BUTTON_LEFT_SHOULDER); _key("m1_undo", KEY_Z)
	_ensure_action("m1_redo"); _button("m1_redo", JOY_BUTTON_RIGHT_SHOULDER); _key("m1_redo", KEY_C)
	_ensure_action("m1_move_left"); _axis("m1_move_left", JOY_AXIS_LEFT_X, -1.0); _key("m1_move_left", KEY_A)
	_ensure_action("m1_move_right"); _axis("m1_move_right", JOY_AXIS_LEFT_X, 1.0); _key("m1_move_right", KEY_D)
	_ensure_action("m1_move_up"); _axis("m1_move_up", JOY_AXIS_LEFT_Y, -1.0); _key("m1_move_up", KEY_W)
	_ensure_action("m1_move_down"); _axis("m1_move_down", JOY_AXIS_LEFT_Y, 1.0); _key("m1_move_down", KEY_S)
	_ensure_action("m1_orbit_left"); _axis("m1_orbit_left", JOY_AXIS_RIGHT_X, -1.0); _key("m1_orbit_left", KEY_LEFT)
	_ensure_action("m1_orbit_right"); _axis("m1_orbit_right", JOY_AXIS_RIGHT_X, 1.0); _key("m1_orbit_right", KEY_RIGHT)
	_ensure_action("m1_orbit_up"); _axis("m1_orbit_up", JOY_AXIS_RIGHT_Y, -1.0); _key("m1_orbit_up", KEY_UP)
	_ensure_action("m1_orbit_down"); _axis("m1_orbit_down", JOY_AXIS_RIGHT_Y, 1.0); _key("m1_orbit_down", KEY_DOWN)
	_ensure_action("m1_zoom_in"); _axis("m1_zoom_in", JOY_AXIS_TRIGGER_RIGHT, 1.0); _key("m1_zoom_in", KEY_EQUAL)
	_ensure_action("m1_zoom_out"); _axis("m1_zoom_out", JOY_AXIS_TRIGGER_LEFT, 1.0); _key("m1_zoom_out", KEY_MINUS)
	_ensure_action("m1_height_up"); _button("m1_height_up", JOY_BUTTON_DPAD_UP); _key("m1_height_up", KEY_E)
	_ensure_action("m1_height_down"); _button("m1_height_down", JOY_BUTTON_DPAD_DOWN); _key("m1_height_down", KEY_Q)
	_ensure_action("m1_cycle_left"); _button("m1_cycle_left", JOY_BUTTON_DPAD_LEFT); _key("m1_cycle_left", KEY_BRACKETLEFT)
	_ensure_action("m1_cycle_right"); _button("m1_cycle_right", JOY_BUTTON_DPAD_RIGHT); _key("m1_cycle_right", KEY_BRACKETRIGHT)
	_ensure_action("m1_debug"); _button("m1_debug", JOY_BUTTON_Y); _key("m1_debug", KEY_F1)
	_ensure_action("m1_focus"); _button("m1_focus", JOY_BUTTON_RIGHT_STICK); _key("m1_focus", KEY_G)

func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action): InputMap.add_action(action)
	if action.begins_with("m1_move_") or action.begins_with("m1_orbit_"):
		InputMap.action_set_deadzone(action, 0.18)
	elif action.begins_with("m1_zoom_"):
		InputMap.action_set_deadzone(action, 0.05)
func _button(action: String, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new(); event.button_index = button; InputMap.action_add_event(action, event)
func _axis(action: String, axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new(); event.axis = axis; event.axis_value = value; InputMap.action_add_event(action, event)
func _key(action: String, key: Key) -> void:
	var event := InputEventKey.new(); event.keycode = key; InputMap.action_add_event(action, event)

## World lighting, as a single overridable seam. This is the canonical M2 live
## look; an environment that wants a different atmosphere overrides just this
## method instead of re-copying the whole world build (which previously dropped
## water_visual and other nodes).
func _apply_world_lighting() -> void:
	# M2 lighting polish -> golden-hour overhaul. Warm low sun for long,
	# directional contrast; warm hazy procedural sky with depth; ordinary fog
	# for atmospheric perspective; modest glow for a soft golden bloom; ACES
	# + a light warm grade; a restrained SSAO pass for contact/AO softness.
	# All Mobile-renderer-safe; no volumetrics, SDFGI, or SSR.
	var sun := DirectionalLight3D.new()
	sun.name = "WorldSun"  # stable name: debug tune target "light"
	sun.rotation_degrees = Vector3(-33, -46, 0)
	sun.light_color = Color("#ffd9a0")
	sun.light_energy = 1.72
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	sun.shadow_bias = 0.028
	sun.shadow_normal_bias = 0.02
	add_child(sun)

	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#d8e1e5")
	# Canonical M2 live look (this is the build that actually ships; a prior
	# m1-only "wide-shot" pass never reached the live level, so M2's values win).
	sky_material.sky_horizon_color = Color("#f2d9a4")
	sky_material.ground_bottom_color = Color("#c3b795")
	sky_material.ground_horizon_color = Color("#e0d3b2")
	sky_material.sky_energy_multiplier = 0.55
	sky_material.ground_energy_multiplier = 0.35
	# Environment.sky requires a Sky resource, not a raw material (a bare
	# ProceduralSkyMaterial here fails to parse and breaks the whole M2 chain).
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 1.0
	environment.fog_enabled = true
	environment.fog_light_color = Color("#ead7b3")
	# Canonical M2 live look: the single source of truth for world fog. Envs that
	# want a different atmosphere override this (see _apply_world_lighting).
	environment.fog_density = 0.0038
	environment.fog_sky_affect = 0.8
	environment.fog_depth_begin = 18.0
	environment.fog_depth_end = 150.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.5
	environment.glow_bloom = 0.14
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.05
	environment.tonemap_white = 1.35
	# SSAO disabled: its per-frame jitter breaks the repo's render-determinism
	# contract (cottage/roof-course tests require identical re-renders), and it
	# adds Mobile GPU cost for a barely-visible contact shadow here.
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.06
	environment.adjustment_contrast = 1.04
	environment.adjustment_brightness = 1.02
	environment_node.environment = environment
	environment_node.name = "WorldEnvironment"  # stable name: debug tune target "environment"
	add_child(environment_node)

## Building-world factory: the base M1 world returns the base BuildingWorld; an
## environment (e.g. M2) overrides this to construct its subclass once, in place,
## so the base _build_world builds exactly one building world (no double-build).
func _create_building_world() -> RefCounted:
	return BuildingWorldScript.new()

func _build_world() -> void:
	_apply_world_lighting()
	river_water = MeshInstance3D.new(); river_water.name = "RiverWater"; river_water.mesh = _build_river_water_mesh(); river_water.position.y = 5.0
	var water_material := StandardMaterial3D.new(); water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; water_material.albedo_color = Color(0.31, 0.52, 0.52, 0.86); water_material.metallic = 0.05; water_material.roughness = 0.42; river_water.material_override = water_material; add_child(river_water)
	decor_root = Node3D.new(); decor_root.name = "GardenDecor"; add_child(decor_root)
	garden_visual = GardenVisualScript.new(); garden_visual.name = "M1GardenVisual"; garden_visual.set_wind_enabled(not test_mode); decor_root.add_child(garden_visual)
	water_visual = WaterVisualScript.new(); water_visual.name = "M1WaterVisual"; decor_root.add_child(water_visual)
	camera = Camera3D.new(); camera.current = true; camera.fov = 52; add_child(camera)
	resize_handles = Node3D.new(); resize_handles.name = "ResizeHandles"; resize_handles.visible = false; add_child(resize_handles)
	for axis_name in ["width", "depth", "height"]:
		var handle := MeshInstance3D.new(); handle.name = "Handle_%s" % axis_name
		var handle_mesh := BoxMesh.new(); handle_mesh.size = Vector3(0.22, 0.22, 0.22); handle.mesh = handle_mesh
		var handle_material := StandardMaterial3D.new(); handle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; handle_material.albedo_color = Color(1.0, 0.70, 0.28, 0.82); handle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; handle.material_override = handle_material
		resize_handles.add_child(handle)
	building_world = _create_building_world()
	cottage_visual = CottageVisualScript.new(); cottage_visual.name = "CottageVisual"; add_child(cottage_visual); cottage_visuals[BUILDING_ID] = cottage_visual
	brush_preview = BrushPreviewScript.new()
	brush_preview.name = "BrushPreview"
	# BrushPreview geometry is expressed in native cells; map it to the same
	# world-space voxel edge as the terrain and authored visual details.
	brush_preview.scale = Vector3.ONE * M1PatchGenerator.VOXEL_SCALE
	brush_preview.visible = false
	add_child(brush_preview)
	reference_plane = MeshInstance3D.new()
	reference_plane.name = "ReferencePlane"
	var plane_mesh := PlaneMesh.new(); plane_mesh.size = Vector2(8, 8); reference_plane.mesh = plane_mesh
	var plane_material := StandardMaterial3D.new(); plane_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; plane_material.albedo_color = Color(0.42, 0.82, 0.88, 0.16); plane_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; reference_plane.material_override = plane_material; reference_plane.visible = false; add_child(reference_plane)
	terrain_hit_marker = MeshInstance3D.new(); terrain_hit_marker.name = "TerrainHitMarker"
	var marker_mesh := SphereMesh.new(); marker_mesh.radius = 0.12; marker_mesh.height = 0.24; marker_mesh.radial_segments = 12; marker_mesh.rings = 6; terrain_hit_marker.mesh = marker_mesh
	var marker_material := StandardMaterial3D.new(); marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; marker_material.albedo_color = Color(0.55, 0.92, 0.96, 0.82); marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; marker_material.no_depth_test = true; terrain_hit_marker.material_override = marker_material; terrain_hit_marker.visible = false; add_child(terrain_hit_marker)
	cursor_reticle = CursorReticleScript.new()
	cursor_reticle.name = "M1CursorReticle"
	cursor_reticle.visible = false
	add_child(cursor_reticle)

func _build_river_water_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for z_index in M1PatchGenerator.PATCH_SIZE.z + 1:
		var world_z := float(z_index) * M1PatchGenerator.VOXEL_SCALE
		var center := M1PatchGenerator.river_center_x(world_z)
		var half_width := M1PatchGenerator.river_half_width(world_z)
		vertices.append(Vector3(center - half_width, 0, world_z))
		vertices.append(Vector3(center + half_width, 0, world_z))
		normals.append(Vector3.UP); normals.append(Vector3.UP)
		uvs.append(Vector2(0, world_z * 0.25)); uvs.append(Vector2(1, world_z * 0.25))
		if z_index < M1PatchGenerator.PATCH_SIZE.z:
			var base := z_index * 2
			indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = normals; arrays[Mesh.ARRAY_TEX_UV] = uvs; arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _river_water_span_for_row(z: int, water_cell_y: int, support_cell_y: int) -> Vector2i:
	var best_start := -1
	var best_end := -1
	var run_start := -1
	for x in range(floori(37.5 / M1PatchGenerator.VOXEL_SCALE), M1PatchGenerator.PATCH_SIZE.x + 1):
		var qualifies: bool = x < M1PatchGenerator.PATCH_SIZE.x and int(backend.voxel_at(Vector3i(x, water_cell_y, z))) == 0 and int(backend.voxel_at(Vector3i(x, support_cell_y, z))) != 0
		if qualifies and run_start < 0: run_start = x
		if not qualifies and run_start >= 0:
			if x - run_start > best_end - best_start:
				best_start = run_start
				best_end = x
			run_start = -1
	return Vector2i(best_start, best_end)

func _refresh_river_water_from_terrain() -> void:
	if not river_water or not backend or not backend.has_method("voxel_at") or not backend.is_ready(): return
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var unit := M1PatchGenerator.VOXEL_SCALE
	var water_cell_y := floori(5.0 / unit) - 1
	var support_cell_y := floori(3.0 / unit)
	if _river_water_spans.size() != M1PatchGenerator.PATCH_SIZE.z:
		_river_water_spans.resize(M1PatchGenerator.PATCH_SIZE.z)
		for z in M1PatchGenerator.PATCH_SIZE.z:
			_river_water_spans[z] = _river_water_span_for_row(z, water_cell_y, support_cell_y)
	else:
		var edit_bounds: AABB = backend.get_last_edit_bounds() if backend.has_method("get_last_edit_bounds") else AABB()
		# Only edits within the water/support sampling band can alter the river
		# surface. All other terrain work keeps the existing mesh untouched.
		if edit_bounds.size == Vector3.ZERO or edit_bounds.end.x < 37.5 or edit_bounds.position.y >= 5.0 or edit_bounds.end.y <= 3.0:
			return
		var row_start := clampi(floori(edit_bounds.position.z / unit) - 1, 0, M1PatchGenerator.PATCH_SIZE.z - 1)
		var row_end := clampi(ceili(edit_bounds.end.z / unit) + 1, 0, M1PatchGenerator.PATCH_SIZE.z - 1)
		for z in range(row_start, row_end + 1):
			_river_water_spans[z] = _river_water_span_for_row(z, water_cell_y, support_cell_y)
	for z in M1PatchGenerator.PATCH_SIZE.z:
		var span := _river_water_spans[z]
		var best_start := span.x
		var best_end := span.y
		if best_start < 0: continue
		var base := vertices.size()
		var x0 := float(best_start) * unit; var x1 := float(best_end) * unit
		var z0 := float(z) * unit; var z1 := float(z + 1) * unit
		vertices.append_array(PackedVector3Array([Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x0, 0, z1), Vector3(x1, 0, z1)]))
		for unused in 4: normals.append(Vector3.UP)
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
	if vertices.is_empty(): return
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = normals; arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	river_water.mesh = mesh

func _create_backend() -> void:
	var backend_script := load("res://scripts/terrain_backend.gd")
	if not backend_script:
		_set_status("Terrain backend unavailable")
		return
	backend = backend_script.new()
	backend.name = "TerrainBackend"
	backend.set("checkpoint_root", checkpoint_root)
	backend.set("initial_generator", M1PatchGenerator)
	backend.set("generator_id", M1PatchGenerator.GENERATOR_ID)
	backend.set("require_building_document", true)
	# Keep the same world bounds; native grid and asset cells share one edge.
	backend.set("patch_size", M1PatchGenerator.PATCH_SIZE)
	backend.set("voxel_scale", M1PatchGenerator.VOXEL_SCALE)
	# Startup only waits for the initial cottage/play area to mesh; the full
	# 64-unit valley remains authoritative, editable and continues streaming.
	backend.set("startup_mesh_focus_world", Vector3(24.0, 8.0, 22.0))
	backend.set("startup_mesh_radius_world", 12.0)
	backend.set("startup_mesh_height_world", 16.0)
	if test_mode: backend.set("initialization_budget_override_ms", 90000)
	add_child(backend)
	if garden_visual and garden_visual.has_method("attach_backend"):
		garden_visual.attach_backend(backend)
	# The region-water surface is a heavy presentation mesh (tens of thousands of
	# quads). Build it only for scenes that actually render; test_mode suites
	# (placement/path) instantiate the world without rendering water and skip the
	# build so they stay fast. The game (not test_mode) always builds it.
	if not test_mode:
		if water_visual and water_visual.has_method("attach_backend"):
			water_visual.attach_backend(backend)
		_sync_water_visual()

func _sync_water_visual() -> void:
	if test_mode:
		return
	if water_visual and water_visual.has_method("set_regions"):
		water_visual.set_regions(landscape_state.water)
	# set_waterfall_suppressions also re-derives the (bounded) waterfalls honouring
	# the player's dismissals, so water commit / undo / redo / restore all stay in sync.
	if water_visual and water_visual.has_method("set_waterfall_suppressions"):
		water_visual.set_waterfall_suppressions(landscape_state.waterfall_suppressions)

func _ensure_premade_river() -> void:
	# The starter river is a water region so it shares the same presentation path,
	# materials and editability as player-authored water. Deterministic + idempotent:
	# derived from the generator, added once, and the generated bed already exists
	# (no carve). Covers fresh and existing worlds.
	# NOTE: the legacy static river mesh is kept VISIBLE alongside the region water
	# until the player confirms the combined look in playtest (a visual call).
	var river := PremadeRiver.region()
	for existing: Dictionary in landscape_state.water:
		if PremadeRiver.matches(existing, river): return
	if landscape_state.add_water("stream", river["level"], river["points"], river["width"], river["flow"]) > 0:
		_sync_water_visual()

func _update_brush_preview() -> void:
	if not brush_preview:
		return
	var visible_now: bool = backend != null and backend.has_method("is_ready") and backend.is_ready() and view_context == "terrain" and not menu_open and not tools_open and not detail_open and not _restoring and not _shutting_down
	brush_preview.visible = visible_now
	if not visible_now:
		if reference_plane: reference_plane.visible = false
		if terrain_hit_marker: terrain_hit_marker.visible = false
		if cursor_reticle and cursor_reticle.has_method("set_target_visible"): cursor_reticle.set_target_visible(false)
		_terrain_target_valid = false
		return
	var scale_value := float(backend.get("voxel_scale")) if backend.get("voxel_scale") != null else 1.0
	if scale_value <= 0.0:
		scale_value = 1.0
	# Keep the sampled target in authored world coordinates.  Native-cell
	# snapping is only a cache aid; the backend receives this same raw point
	# when a stroke begins and while it advances.
	var target_center: Vector3 = cursor
	var snapped_center := Vector3(snappedf(target_center.x, scale_value), snappedf(target_center.y, scale_value), snappedf(target_center.z, scale_value))
	var remove := sculpt_tool == "dig"
	var preview_normal := _active_reference_normal()
	var sample_center: Vector3 = backend.get_stroke_preview_center(cursor + stroke_aim_offset) if stroke_active else target_center
	var sample_normal := stroke_surface_normal if stroke_active else preview_normal
	var surface_sample: Dictionary = backend.sample_surface_plane(sample_center, sample_normal, brush_radius + 1.0) if backend.has_method("sample_surface_plane") else {}
	var display_center: Vector3 = target_center
	if bool(surface_sample.get("valid", false)) and surface_sample.get("point", null) is Vector3:
		display_center = surface_sample["point"]
	else:
		var local_surface := _find_local_surface(sample_center, sample_normal, scale_value)
		if bool(local_surface.get("valid", false)) and local_surface.get("point", null) is Vector3:
			surface_sample = local_surface
			display_center = local_surface["point"]
	var target_valid := bool(surface_sample.get("valid", false)) and surface_sample.get("point", null) is Vector3
	_terrain_target_valid = target_valid
	if target_valid:
		_terrain_target_point = display_center
		_terrain_target_normal = surface_sample.get("normal", Vector3.UP) if surface_sample.get("normal", Vector3.UP) is Vector3 else Vector3.UP
	else:
		preview_center = Vector3.ZERO
		preview_cells.clear()
		brush_preview.visible = false
		if reference_plane: reference_plane.visible = false
		if terrain_hit_marker: terrain_hit_marker.visible = false
		if cursor_reticle and cursor_reticle.has_method("set_target_visible"): cursor_reticle.set_target_visible(false)
		_set_status("No terrain target under cursor")
		return
	var revision := int(backend.stats().get("revision", -1)) if backend.has_method("stats") else -1
	var key := "%d|%s|%s|%s|%.3f|%s|%s|%s|%s|%s|%d" % [revision, str(snapped_center), str(display_center), str(preview_normal), brush_radius, str(remove), sculpt_tool, reference_mode, str(keep_reference), str(stroke_reference), get_instance_id()]
	if key == _preview_key:
		return
	_preview_key = key
	preview_center = display_center
	# Keep aiming feedback cheap: the authoritative terrain preview API clones a
	# bounded native buffer and is reserved for one-shot transactions.  A live
	# sculpt stroke uses the faint volume as its influence cue; actual changed
	# cells are reported only after the native stroke commits.
	preview_cells = _build_influence_cells(display_center, brush_radius / scale_value, remove, scale_value)
	var native_center := display_center / scale_value
	var native_radius := brush_radius / scale_value
	if brush_preview.has_method("update_geometry"):
		brush_preview.update_geometry(native_center, native_radius, remove, preview_cells)
	_update_reference_guides(display_center, surface_sample)
	if cursor_reticle and cursor_reticle.has_method("update_target"):
		cursor_reticle.update_target(display_center, _terrain_target_normal, brush_radius, sculpt_tool, camera, true)

func _update_cursor_reticle() -> void:
	if not cursor_reticle or not cursor_reticle.has_method("update_target"):
		return
	var visible_now := not menu_open and not tools_open and not detail_open and not _restoring and not _shutting_down
	if not visible_now:
		if cursor_reticle.has_method("set_target_visible"): cursor_reticle.set_target_visible(false)
		return
	if view_context == "building" and not menu_open and not tools_open and not detail_open and not _restoring and not _shutting_down:
		cursor_reticle.update_target(cottage_cursor, Vector3.UP, 1.2, "cottage", camera, true)
		return
	var point := _terrain_target_point if _terrain_target_valid else (cursor + stroke_aim_offset if stroke_active else cursor)
	var normal := _terrain_target_normal if _terrain_target_valid else Vector3.UP
	cursor_reticle.update_target(point, normal, brush_radius, sculpt_tool, camera, _terrain_target_valid)

func _find_local_surface(center: Vector3, normal: Vector3, scale_value: float) -> Dictionary:
	var result: Dictionary = {"valid": false}
	if not backend or not backend.has_method("voxel_at"):
		return result
	var native_center := center / scale_value
	var base := Vector3i(floori(native_center.x), floori(native_center.y), floori(native_center.z))
	var radius := ceili(brush_radius / scale_value) + 3
	var best_distance := INF
	var best_cell := Vector3i.ZERO
	var best_face := Vector3i.UP
	var patch: Vector3i = backend.get("patch_size") if backend.get("patch_size") is Vector3i else Vector3i(96, 64, 96)
	# Preserve the previous eight-world-unit recovery reach after refinement.
	var vertical_reach := ceili(8.0 / scale_value)
	var min_y: int = maxi(0, base.y - vertical_reach)
	var max_y: int = mini(patch.y - 1, base.y + vertical_reach)
	# Recovery when the direct surface probe misses: seven columns per axis,
	# including the exact centre, rather than a radius-cubed search every frame.
	var stride := maxi(1, ceili(radius / 3.0))
	for dx in [0, -stride, stride, -2 * stride, 2 * stride, -radius, radius]:
		var x: int = base.x + int(dx)
		if x < 0 or x >= patch.x: continue
		for dz in [0, -stride, stride, -2 * stride, 2 * stride, -radius, radius]:
			var z: int = base.z + int(dz)
			if z < 0 or z >= patch.z: continue
			for y in range(min_y, max_y + 1):
				var cell := Vector3i(x, y, z)
				if backend.voxel_at(cell) == 0:
					continue
				var face := Vector3i.ZERO
				if absf(normal.y) >= maxf(absf(normal.x), absf(normal.z)):
					face = Vector3i.UP if normal.y >= 0.0 else Vector3i.DOWN
				elif absf(normal.x) >= absf(normal.z):
					face = Vector3i.RIGHT if normal.x >= 0.0 else Vector3i.LEFT
				else:
					face = Vector3i.BACK if normal.z >= 0.0 else Vector3i.FORWARD
				var neighbor := cell + face
				if neighbor.x < 0 or neighbor.y < 0 or neighbor.z < 0 or neighbor.x >= patch.x or neighbor.y >= patch.y or neighbor.z >= patch.z:
					continue
				if backend.voxel_at(neighbor) != 0:
					continue
				var point := Vector3(cell) * scale_value + Vector3.ONE * scale_value * 0.5
				if face == Vector3i.UP:
					point.y += scale_value * 0.5
				elif face == Vector3i.DOWN:
					point.y -= scale_value * 0.5
				elif face == Vector3i.RIGHT:
					point.x += scale_value * 0.5
				elif face == Vector3i.LEFT:
					point.x -= scale_value * 0.5
				elif face == Vector3i.BACK:
					point.z += scale_value * 0.5
				else:
					point.z -= scale_value * 0.5
				var distance := point.distance_squared_to(center)
				if distance < best_distance:
					best_distance = distance
					best_cell = cell
					best_face = face
	if best_distance == INF:
		return result
	var best_point := Vector3(best_cell) * scale_value + Vector3.ONE * scale_value * 0.5
	if best_face == Vector3i.UP:
		best_point.y += scale_value * 0.5
	elif best_face == Vector3i.DOWN:
		best_point.y -= scale_value * 0.5
	elif best_face == Vector3i.RIGHT:
		best_point.x += scale_value * 0.5
	elif best_face == Vector3i.LEFT:
		best_point.x -= scale_value * 0.5
	elif best_face == Vector3i.BACK:
		best_point.z += scale_value * 0.5
	else:
		best_point.z -= scale_value * 0.5
	result["valid"] = true
	result["point"] = best_point
	result["normal"] = Vector3(best_face)
	return result

func _build_influence_cells(center: Vector3, native_radius: float, remove: bool, scale_value: float) -> Array[Vector3i]:
	# A sparse surface highlight accompanies the full influence outline. Keep
	# target feedback bounded as native resolution increases; do not scan a cube.
	var result: Array[Vector3i] = []
	if not backend or not backend.has_method("voxel_at"): return result
	var base := Vector3i(floor(center / scale_value))
	var normal := _active_reference_normal()
	var axis := normal.abs().max_axis_index()
	var tangent_a := (axis + 1) % 3; var tangent_b := (axis + 2) % 3
	var direction := Vector3i.ZERO; direction[axis] = 1 if normal[axis] >= 0 else -1
	# Show exact cells at the aim point; the ghost carries the full brush radius.
	for a in range(-1, 2):
		for b in range(-1, 2):
			if Vector2(a, b).length() > native_radius: continue
			var cell := base; cell[tangent_a] += a; cell[tangent_b] += b
			var found := false
			for depth in range(3):
				for sign_value in [1, -1]:
					var candidate: Vector3i = cell + direction * depth * sign_value
					if backend.voxel_at(candidate) != 0 and backend.voxel_at(candidate + direction) == 0:
						result.append(candidate if remove else candidate + direction); found = true; break
				if found: break
	return result

func _update_reference_guides(center: Vector3, sample_override: Dictionary = {}) -> void:
	if not reference_plane or not terrain_hit_marker:
		return
	var sample: Dictionary = sample_override if not sample_override.is_empty() else (backend.sample_surface_plane(center, _reference_normal(), brush_radius + 1.0) if backend.has_method("sample_surface_plane") else {})
	var point = sample.get("point", null)
	var valid: bool = bool(sample.get("valid", false)) and point is Vector3
	terrain_hit_marker.visible = valid
	if valid: terrain_hit_marker.position = point
	var reference: Dictionary = stroke_reference if not stroke_reference.is_empty() else sample
	var reference_point = reference.get("point", point)
	var normal = reference.get("normal", Vector3.UP)
	if sculpt_tool == "level": normal = Vector3.UP
	var show_plane: bool = sculpt_tool in ["level", "slope"] and reference_point is Vector3 and normal is Vector3 and normal.length_squared() > 0.001 and (not stroke_reference.is_empty() or valid)
	reference_plane.visible = show_plane
	if show_plane:
		reference_plane.position = reference_point
		reference_plane.rotation = Quaternion(Vector3.UP, normal.normalized()).get_euler()
		var plane_mesh := reference_plane.mesh as PlaneMesh
		if plane_mesh: plane_mesh.size = Vector2(brush_radius * 2.0, brush_radius * 2.0)

func _on_backend_ready(ready: bool) -> void:
	if not ready: _set_status("Native terrain error"); return
	if _player_restored or _restoring: return
	_restoring = true
	var loaded_ok: bool = backend.load_world() if backend.has_method("load_world") else false
	if loaded_ok:
		var loaded_document: Dictionary = backend.get("loaded_building_document")
		if loaded_document.is_empty() or not BuildingWorldScript.validate_document(loaded_document) or not _load_cottage_document(loaded_document):
			_restoring = false
			_set_menu(true)
			_set_status("Checkpoint cottage design is invalid; reload blocked")
			return
		_building_dirty = false
		_set_status("Cottage and riverbank restored")
	else:
		var backend_stats: Dictionary = backend.stats() if backend.has_method("stats") else {}
		var load_error := str(backend_stats.get("error", ""))
		if not load_error.is_empty() and load_error != "no valid checkpoint":
			_set_menu(true)
			_set_status("Checkpoint load failed; reload blocked")
		else: _set_status("Cottage and riverbank ready")
	_refresh_river_water_from_terrain()
	_restore_landscape(backend.get("loaded_building_document") if loaded_ok else {})
	_player_restored = true
	_restoring = false
	if _review_edited:
		var review_view: Dictionary = building_world.get_building(BUILDING_ID)
		var review_detail: Dictionary = review_view["details"][0]
		building_world.move_detail(BUILDING_ID, str(review_detail["id"]), str(review_detail["anchor"]["surface_id"]), Vector3(-4.0, 3.5, -7.02))
		building_world.resize(BUILDING_ID, Vector3(23, 8, 12))
	if _review_menu_after_ready:
		view_context = "building"
		detail_open = true
		tools_panel.visible = true
		_update_action_buttons()
		var buttons: Array = _visible_action_buttons()
		if not buttons.is_empty(): (buttons[0] as Button).grab_focus()
	if garden_visual and garden_visual.has_method("refresh_terrain"):
		garden_visual.refresh_terrain()
	if water_visual and water_visual.has_method("refresh_terrain"):
		water_visual.refresh_terrain()
	if water_visual and water_visual.has_method("set_waterfall_suppressions"):
		water_visual.set_waterfall_suppressions(landscape_state.waterfall_suppressions)
	_update_presentation()

func _apply_review_args() -> void:
	var review_run := false
	var review_arguments: Array = []
	review_arguments.append_array(OS.get_cmdline_args())
	review_arguments.append_array(OS.get_cmdline_user_args())
	for argument in review_arguments:
		if str(argument).begins_with("--review-"): review_run = true
		match str(argument):
			"--review-close":
				view_context = "building"
				cursor = cottage_cursor
				camera_distance = 16.0
			"--review-cottage":
				view_context = "building"
				cursor = cottage_cursor
				camera_distance = 36.0
			"--review-near": camera_distance = 12.0
			"--review-far": camera_distance = 52.0
			"--review-terrain":
				view_context = "terrain"
				cursor = terrain_cursor
			"--review-dig":
				view_context = "terrain"
				sculpt_tool = "dig"
				cursor = terrain_cursor
			"--review-occluded":
				view_context = "terrain"
				cursor = Vector3(23.0, 13.0, 20.0)
			"--review-front": camera_yaw = -2.1
			"--review-clean": _review_clean = true
			"--review-edited": _review_edited = true
			"--review-menu": _review_menu_after_ready = true
	if review_run:
		checkpoint_root = "user://m1-review-%s" % Time.get_ticks_usec()
		test_mode = true

func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	if connected or _shutting_down:
		return
	_cancel_current_edit("Controller disconnected")
	_set_menu(true)
	_set_status("Controller disconnected; world paused")

func _sync_meadow_exclusions() -> void:
	if not garden_visual or not garden_visual.has_method("set_meadow_exclusions"):
		return
	var rects: Array = []
	if building_world != null and building_world.has_method("get_buildings"):
		for building_value: Dictionary in building_world.get_buildings():
			var transform_value: Variant = building_value.get("transform", Transform3D.IDENTITY)
			var transform: Transform3D = transform_value if transform_value is Transform3D else Transform3D.IDENTITY
			var dims: Vector3 = building_value.get("dimensions", Vector3(18, 10, 14))
			var scale_abs: Vector3 = transform.basis.get_scale().abs()
			var margin := 0.5
			var half := (dims + Vector3(0.5, 0.0, 0.5)) * 0.125 * 0.5 * Vector3(scale_abs.x, 1.0, scale_abs.z)
			var origin := transform.origin
			half.x += margin
			half.z += margin
			rects.append(Rect2(origin.x - half.x, origin.z - half.z, half.x * 2.0, half.z * 2.0))
	garden_visual.set_meadow_exclusions(rects)

func _on_backend_changed() -> void:
	var started := Time.get_ticks_usec()
	_refresh_river_water_from_terrain()
	var water_ms := float(Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	_sync_meadow_exclusions()
	if garden_visual and garden_visual.has_method("refresh_terrain"):
		garden_visual.refresh_terrain()
	# Localize the region-water surface to the edit bounds (like the river and
	# waterfalls) so a local dig only re-samples the nearby cells; the full
	# refresh_terrain() is the startup / unknown-bounds fallback.
	if backend and backend.has_method("get_last_edit_bounds") and water_visual and water_visual.has_method("refresh_surface_from_bounds"):
		water_visual.refresh_surface_from_bounds(backend.get_last_edit_bounds())
	elif water_visual and water_visual.has_method("refresh_terrain"):
		water_visual.refresh_terrain()
	if water_visual and water_visual.has_method("refresh_waterfalls_from_bounds") and backend and backend.has_method("get_last_edit_bounds"):
		water_visual.refresh_waterfalls_from_bounds(backend.get_last_edit_bounds())
	var garden_ms := float(Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	_update_presentation()
	if OS.is_debug_build():
		print("THOR_BACKEND_BASE " + JSON.stringify({"water_ms": water_ms, "garden_ms": garden_ms, "presentation_ms": float(Time.get_ticks_usec() - started) / 1000.0}))

func _on_building_changed() -> void:
	if not _restoring:
		_building_dirty = true
		_sync_meadow_exclusions()
	_update_presentation()

func _read_camera_and_cursor(delta: float) -> void:
	var move := Vector2(Input.get_axis("m1_move_left", "m1_move_right"), Input.get_axis("m1_move_up", "m1_move_down"))
	if move.length() > 0.05:
		var magnitude := minf(move.length(), 1.0); move = move.normalized() * pow(magnitude, 1.45)
		if resize_active and view_context == "building":
			var resize_speed: float = 3.5
			var snap_step: float = 1.0
			if precision_mode:
				resize_speed = 1.2
				snap_step = 0.25
			if resize_axis == "width":
				resize_accumulator.x = clampf(resize_accumulator.x + move.x * delta * resize_speed * pow(magnitude, 0.85), BuildingWorldScript.MIN_DIMENSIONS.x, BuildingWorldScript.MAX_DIMENSIONS.x)
				resize_preview_dimensions.x = snappedf(resize_accumulator.x, snap_step)
			else:
				resize_accumulator.z = clampf(resize_accumulator.z - move.y * delta * resize_speed * pow(magnitude, 0.85), BuildingWorldScript.MIN_DIMENSIONS.z, BuildingWorldScript.MAX_DIMENSIONS.z)
				resize_preview_dimensions.z = snappedf(resize_accumulator.z, snap_step)
			_set_status("Resize preview: %.1f × %.1f × %.1f  •  A commit / B cancel" % [resize_preview_dimensions.x, resize_preview_dimensions.y, resize_preview_dimensions.z])
		else:
			if not detail_move_active:
				var speed := lerpf(2.5, 10.0, pow(magnitude, 0.85)); if precision_mode: speed *= 0.35
				var forward := Vector3(sin(camera_yaw), 0, cos(camera_yaw)); var right := Vector3(forward.z, 0, -forward.x); cursor += (right * move.x + forward * move.y) * delta * speed; cursor.x = clampf(cursor.x, 0.5, float(PATCH_SIZE.x) - 0.5); cursor.z = clampf(cursor.z, 0.5, float(PATCH_SIZE.z) - 0.5)
	var orbit_x := Input.get_axis("m1_orbit_left", "m1_orbit_right"); var orbit_y := Input.get_axis("m1_orbit_up", "m1_orbit_down"); camera_yaw += orbit_x * delta * 2.2; camera_pitch = clampf(camera_pitch + orbit_y * delta * 1.5, 0.15, 1.25); var zoom := Input.get_axis("m1_zoom_out", "m1_zoom_in"); camera_distance = clampf(camera_distance - zoom * delta * 18.0, 8, 52)
	if not detail_move_active and not resize_active and Input.is_action_just_pressed("m1_height_up"): cursor.y = clampf(cursor.y + 1.0, 0.0, 31.0)
	if not detail_move_active and not resize_active and Input.is_action_just_pressed("m1_height_down"): cursor.y = clampf(cursor.y - 1.0, 0.0, 31.0)
	if Input.is_action_just_pressed("m1_focus"):
		_focus_selected_building()
	if Input.is_action_just_pressed("m1_debug") and debug_label:
		debug_label.visible = not debug_label.visible
	if view_context == "terrain": terrain_cursor = cursor
	else: cottage_cursor = cursor

func _read_detail_move(delta: float) -> void:
	if detail_move_active and not resize_locked:
		var stick := Vector2(Input.get_axis("m1_move_left", "m1_move_right"), Input.get_axis("m1_move_up", "m1_move_down"))
		if stick.length() > 0.05:
			var magnitude := minf(stick.length(), 1.0)
			var speed := (0.9 if precision_mode else 3.0) * pow(magnitude, 1.45)
			var view: Dictionary = building_world.get_building(selected_building_id)
			var tangent_axis := "x"
			for surface_value in view.get("surfaces", []):
				var surface: Dictionary = surface_value
				if str(surface.get("id", "")) == detail_move_surface_id:
					tangent_axis = "x" if str(surface.get("orientation", "front")) in ["front", "back"] else "z"
					break
			if tangent_axis == "x": detail_move_position.x += stick.x * delta * speed
			else: detail_move_position.z += stick.x * delta * speed
			detail_move_position.y -= stick.y * delta * speed
			detail_move_position.x = clampf(detail_move_position.x, -16.0, 16.0)
			detail_move_position.z = clampf(detail_move_position.z, -16.0, 16.0)
			detail_move_position.y = clampf(detail_move_position.y, 0.5, 16.0)
			_update_presentation()

func _update_camera() -> void:
	if not camera: return
	var target := cursor + Vector3(0, 2, 0); var offset := Vector3(sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch)) * camera_distance; camera.position = target + offset; camera.look_at(target, Vector3.UP)

func _set_view_context(next_context: String, reason: String = "Context changed") -> bool:
	var normalized := "terrain" if next_context == "terrain" else "building"
	if normalized == view_context:
		_set_status("Terrain mode" if normalized == "terrain" else "Cottage mode")
		return false
	_cancel_current_edit(reason)
	if view_context == "terrain": terrain_cursor = cursor
	else: cottage_cursor = cursor
	view_context = normalized
	cursor = terrain_cursor if normalized == "terrain" else cottage_cursor
	tools_open = false
	detail_open = false
	if tools_panel: tools_panel.visible = false
	if normalized == "terrain":
		_set_status("Terrain mode • %s • A hold / release, B cancel" % sculpt_tool.capitalize())
	else:
		_set_status("Cottage mode • A resize, X actions")
	_update_action_buttons()
	_preview_key = ""
	return true

func _set_sculpt_tool(tool: String) -> bool:
	var normalized := tool.to_lower()
	if normalized not in ["raise", "dig", "level", "slope", "smooth"]:
		return false
	sculpt_tool = normalized
	if view_context != "terrain":
		_set_view_context("terrain", "Terrain tool selected")
	else:
		_cancel_current_edit("Terrain tool selected")
		tools_open = false
		detail_open = false
		if tools_panel: tools_panel.visible = false
	_set_status("Terrain mode • %s • A hold / release, B cancel" % sculpt_tool.capitalize())
	_preview_key = ""
	return true

func _open_actions_for_context() -> void:
	_cancel_current_edit("Actions opened")
	if view_context == "building":
		detail_open = true
		tools_open = false
	else:
		tools_open = true
		detail_open = false
	if tools_panel: tools_panel.visible = true
	_update_action_buttons()
	var buttons := _visible_action_buttons()
	if not buttons.is_empty(): (buttons[0] as Button).grab_focus()
	_set_status("Cottage actions • D-pad choose / A select" if view_context == "building" else "Terrain tools • D-pad choose / A select")

func _visible_action_labels() -> Array[String]:
	return _terrain_action_labels if view_context == "terrain" else _cottage_action_labels

func _visible_action_buttons() -> Array:
	var result: Array = []
	for label in _visible_action_labels():
		if _tool_buttons.has(label): result.append(_tool_buttons[label])
	return result

func _update_action_buttons() -> void:
	var visible_labels := _visible_action_labels()
	for label in _tool_buttons.keys():
		var button: Button = _tool_buttons[label]
		button.visible = visible_labels.has(str(label))
		button.disabled = not button.visible

func _begin_stroke() -> void:
	if view_context != "terrain":
		_set_status("Switch to Terrain mode to sculpt")
		return
	if stroke_active or resize_active or detail_move_active or menu_open or tools_open or detail_open:
		return
	if not _terrain_target_valid:
		_set_status("No terrain target under cursor")
		return
	if not backend or not backend.has_method("begin_stroke"):
		_set_status("Terrain backend unavailable")
		return
	var stroke_center := _terrain_target_point if _terrain_target_valid else cursor
	stroke_aim_offset = stroke_center - cursor
	var reference := {}
	if sculpt_tool in ["level", "slope"] and backend.has_method("sample_surface_plane"):
		if keep_reference and not stroke_reference.is_empty(): reference = stroke_reference.duplicate(true)
		else: reference = backend.sample_surface_plane(stroke_center, _reference_normal(), brush_radius + 1.0)
		reference = _snap_reference(reference)
		if sculpt_tool == "level" and not reference.is_empty(): reference["normal"] = Vector3.UP
	var facing := _reference_normal()
	var settings := {"radius": brush_radius, "strength": brush_strength * (0.25 if precision_mode else 1.0), "falloff": brush_falloff, "surface_normal": facing}
	_landscape_before = landscape_state.document()
	if backend.begin_stroke(sculpt_tool, stroke_center, settings, reference):
		stroke_active = true; stroke_reference = reference; stroke_surface_normal = facing; _set_status("Sculpting %s… release A to finish" % sculpt_tool)

func resample_reference() -> void:
	if backend and backend.has_method("sample_surface_plane"):
		var candidate: Dictionary = backend.sample_surface_plane(cursor, _reference_normal(), brush_radius + 1.0)
		if bool(candidate.get("valid", false)): stroke_reference = _snap_reference(candidate); _preview_key = ""; _set_status("Reference sampled")

func _snap_reference(reference: Dictionary) -> Dictionary:
	var result := reference.duplicate(true)
	if height_snap_enabled and result.get("point", null) is Vector3:
		var point: Vector3 = result["point"]
		point.y = snappedf(point.y, 1.0)
		result["point"] = point
	return result

func _end_stroke() -> void:
	if not stroke_active: return
	var final_target: Vector3 = backend.get_stroke_preview_center(cursor + stroke_aim_offset)
	var ok: bool = backend.end_stroke() if backend and backend.has_method("end_stroke") else false
	if sculpt_tool in ["raise", "dig"]:
		cursor = final_target; terrain_cursor = cursor
	stroke_active = false; stroke_aim_offset = Vector3.ZERO
	if ok:
		landscape_state.clear_edited_cells(backend.get_last_edit_cells(), float(backend.voxel_scale))
		garden_visual.apply_records(landscape_state.records)
		_sync_water_visual()
		_record_history("terrain")
	_landscape_before.clear()
	_set_status("Stroke committed" if ok else "Stroke unchanged")

func _begin_resize() -> void:
	if detail_move_active: return
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty(): return
	resize_dimensions = view["dimensions"]; resize_preview_dimensions = resize_dimensions; resize_accumulator = resize_dimensions; resize_active = true; resize_locked = false; resize_axis = "width"; _set_status("Resize width: left stick, D-pad left/right axis, up/down height")

func _commit_resize() -> bool:
	if not resize_active: return false
	var ok: bool = building_world.resize(selected_building_id, resize_preview_dimensions)
	resize_active = false
	if ok: _record_history("building")
	_set_status("Cottage resized" if ok else "Resize rejected")
	return ok

func _cancel_resize() -> void:
	resize_active = false; resize_preview_dimensions = resize_dimensions; resize_accumulator = resize_dimensions; _set_status("Resize cancelled")

func _begin_detail_move() -> void:
	var view: Dictionary = building_world.get_building(selected_building_id)
	var details: Array = view.get("details", [])
	if selected_detail_id.is_empty() and not details.is_empty(): selected_detail_id = str(details[0].get("id", ""))
	for detail_value in details:
		var detail: Dictionary = detail_value
		if str(detail.get("id", "")) != selected_detail_id: continue
		var anchor: Dictionary = detail.get("anchor", {})
		detail_move_surface_id = str(anchor.get("surface_id", ""))
		var local = anchor.get("local_position", detail.get("resolved_position", Vector3.ZERO))
		if local is Vector3: detail_move_position = local
		detail_move_active = true
		resize_locked = false
		detail_open = false
		tools_open = false
		tools_panel.visible = false
		_set_status("Move %s: left stick fine move, A commit / B cancel" % selected_detail_id)
		_update_presentation()
		return

func _commit_detail_move() -> bool:
	if not detail_move_active: return false
	var ok: bool = building_world.move_detail(selected_building_id, selected_detail_id, detail_move_surface_id, detail_move_position)
	detail_move_active = false
	if ok: _record_history("building")
	_set_status("Detail moved" if ok else "Move rejected")
	_update_presentation()
	return ok

func _cancel_detail_move() -> void:
	if not detail_move_active: return
	detail_move_active = false
	_set_status("Move cancelled")
	_update_presentation()

func _cancel_current_edit(reason: String) -> void:
	var accept_was_down: bool = stroke_active or landscape_active or Input.is_action_pressed("m1_accept")
	if landscape_active:
		landscape_state.restore(_landscape_before)
		garden_visual.reset_records(landscape_state.records)
		_sync_water_visual()
		landscape_active = false
	_landscape_before.clear()
	if stroke_active and backend and backend.has_method("cancel_stroke"): backend.cancel_stroke()
	stroke_active = false
	stroke_aim_offset = Vector3.ZERO
	if resize_active: _cancel_resize()
	if detail_move_active: _cancel_detail_move()
	if accept_was_down: _blocked_until_accept_release = true
	_set_status(reason)

func _reference_normal() -> Vector3:
	if reference_mode == "ceiling": return Vector3.DOWN
	if reference_mode == "wall": return Vector3(sin(camera_yaw), 0.0, cos(camera_yaw)).normalized()
	return Vector3.UP

func _active_reference_normal() -> Vector3:
	if stroke_active and stroke_surface_normal.length_squared() > 0.001:
		return stroke_surface_normal.normalized()
	return _reference_normal()

func _undo() -> void:
	if stroke_active or landscape_active or resize_active or detail_move_active: _set_status("Finish or cancel the current edit first"); return
	if _history_tags.is_empty(): _set_status("Nothing to undo"); return
	var tag: String = str(_history_tags.back())
	var ok: bool = true if tag == "landscape" else (building_world.undo() if tag == "building" else (backend and backend.has_method("undo") and backend.undo()))
	if ok:
		_history_tags.pop_back(); _redo_tags.append(tag)
		var entry: Dictionary = _landscape_history.pop_back()
		_landscape_redo.append(entry); landscape_state.restore(entry["before"])
		garden_visual.reset_records(landscape_state.records); _building_dirty = true; _sync_water_visual()
	_set_status("Undo complete" if ok else "Nothing to undo")

func _redo() -> void:
	if stroke_active or landscape_active or resize_active or detail_move_active: _set_status("Finish or cancel the current edit first"); return
	if _redo_tags.is_empty(): _set_status("Nothing to redo"); return
	var tag: String = str(_redo_tags.back())
	var ok: bool = true if tag == "landscape" else (building_world.redo() if tag == "building" else (backend and backend.has_method("redo") and backend.redo()))
	if ok:
		_redo_tags.pop_back(); _history_tags.append(tag)
		var entry: Dictionary = _landscape_redo.pop_back()
		_landscape_history.append(entry); landscape_state.restore(entry["after"])
		garden_visual.reset_records(landscape_state.records); _building_dirty = true; _sync_water_visual()
	_set_status("Redo complete" if ok else "Nothing to redo")

func _record_history(tag: String) -> void:
	_history_tags.append(tag)
	var after := landscape_state.document()
	_landscape_history.append({"before": after.duplicate(true) if _landscape_before.is_empty() else _landscape_before.duplicate(true), "after": after})
	_building_dirty = true
	_redo_tags.clear(); _landscape_redo.clear()
	if _history_tags.size() > 50: _history_tags.pop_front(); _landscape_history.pop_front()

func _update_presentation() -> void:
	var _ul_t0 := Time.get_ticks_usec()
	if not cottage_visual or not building_world: return
	var revision: int = building_world.get_revision()
	var key := "%d|%s|%s|%s" % [revision, str(resize_preview_dimensions if resize_active else Vector3.ZERO), selected_detail_id if detail_move_active else "", str(detail_move_position) if detail_move_active else ""]
	if revision != _last_requested_cottage_revision:
		if cottage_visual.has_method("request_revision"): cottage_visual.request_revision(revision)
		_last_requested_cottage_revision = revision
	if key != _presentation_key:
		var presentation: Dictionary = building_world.get_building(selected_building_id)
		if resize_active:
			var resize_preview: Dictionary = building_world.preview_resize(selected_building_id, resize_preview_dimensions)
			if not resize_preview.is_empty():
				presentation["dimensions"] = resize_preview.get("dimensions", resize_preview_dimensions)
				presentation["details"] = resize_preview.get("details", presentation.get("details", []))
		if detail_move_active:
			var moved_details: Array = presentation.get("details", [])
			for i in moved_details.size():
				var moved: Dictionary = moved_details[i]
				if str(moved.get("id", "")) == selected_detail_id:
					moved["resolved_position"] = detail_move_position
					var moved_anchor: Dictionary = moved.get("anchor", {})
					moved_anchor["surface_id"] = detail_move_surface_id
					moved_anchor["local_position"] = detail_move_position
					moved["anchor"] = moved_anchor
					moved_details[i] = moved
			presentation["details"] = moved_details
		if not presentation.is_empty():
			cottage_visual.apply_building(presentation, revision)
			var seen: Dictionary = {}
			for building_value in building_world.get_buildings():
				var other_view: Dictionary = building_value
				var other_id := str(other_view.get("id", ""))
				if other_id.is_empty(): continue
				seen[other_id] = true
				var other_visual: Node3D = cottage_visuals.get(other_id)
				if not other_visual:
					other_visual = CottageVisualScript.new()
					other_visual.name = "CottageVisual_%s" % other_id
					add_child(other_visual)
					cottage_visuals[other_id] = other_visual
				if other_visual.has_method("request_revision"): other_visual.request_revision(revision)
				if other_id == selected_building_id and not presentation.is_empty(): other_visual.apply_building(presentation, revision)
				else: other_visual.apply_building(other_view, revision)
			for existing_id in cottage_visuals.keys():
				if not seen.has(existing_id):
					var stale_visual: Node3D = cottage_visuals[existing_id]
					if is_instance_valid(stale_visual): stale_visual.queue_free()
					cottage_visuals.erase(existing_id)
		_presentation_key = key
	if target_label:
		var next_target_text := ""
		if view_context == "terrain":
			var mode_name := sculpt_tool.capitalize()
			var target_text := "%s target (%.1f, %.1f, %.1f)  •  radius %.1f" % [mode_name, preview_center.x, preview_center.y, preview_center.z, brush_radius] if _terrain_target_valid else "%s • NO TERRAIN TARGET" % mode_name
			if sculpt_tool in ["level", "slope"] and stroke_reference.get("point", null) is Vector3:
				target_text += "  •  locked y %.1f" % (stroke_reference["point"] as Vector3).y
			next_target_text = "%s  •  str %.1f falloff %.1f  %s  •  A hold/release B cancel  R3 refocus" % [target_text, brush_strength, brush_falloff, "PRECISION" if precision_mode else "NORMAL"]
		else:
			var cottage_text := "Cottage %s" % selected_building_id
			if detail_move_active: cottage_text = "Move %s at (%.1f, %.1f, %.1f)" % [selected_detail_id, detail_move_position.x, detail_move_position.y, detail_move_position.z]
			next_target_text = "%s  •  A resize  B cancel  •  sticks move/orbit  R3 refocus" % cottage_text
		if next_target_text != _last_target_label_text:
			target_label.text = next_target_text
			_last_target_label_text = next_target_text
	_update_resize_handles()

	var _ul_t1 := Time.get_ticks_usec()
	last_frame_costs["upd_m1_scene"] = (_ul_t1 - _ul_t0) / 1000.0
func _update_resize_handles() -> void:
	if not resize_handles:
		return
	var show_handles: bool = resize_active and not menu_open and not tools_open and not detail_open and not _restoring
	resize_handles.visible = show_handles
	if not show_handles:
		return
	var view: Dictionary = building_world.get_building(selected_building_id)
	var transform_value = view.get("transform", Transform3D.IDENTITY)
	var building_transform: Transform3D = transform_value if transform_value is Transform3D else Transform3D.IDENTITY
	var dims := resize_preview_dimensions
	var authored_positions := [Vector3(dims.x * 0.5 + 0.5, dims.y * 0.5, 0), Vector3(0, dims.y * 0.5, dims.z * 0.5 + 0.5), Vector3(0, dims.y + 0.5, 0)]
	for index in mini(authored_positions.size(), resize_handles.get_child_count()):
		(resize_handles.get_child(index) as Node3D).position = building_transform * authored_positions[index]

func _update_debug_overlay() -> void:
	if not debug_label or not debug_label.visible:
		return
	var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var primitives := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var static_memory := Performance.get_monitor(Performance.MEMORY_STATIC)
	var memory_text := "unavailable" if static_memory <= 0.0 else "%.1f MB" % (static_memory / 1048576.0)
	var native_stats: Dictionary = backend.stats() if backend and backend.has_method("stats") else {}
	var renderer := RenderingServer.get_current_rendering_method()
	var adapter := RenderingServer.get_video_adapter_name()
	var path_profile: Dictionary = {}
	if has_method("path_profile_stats"):
		path_profile = call("path_profile_stats")
	var path_profile_text := ""
	if path_profile is Dictionary and not path_profile.is_empty():
		path_profile_text = "\nPath ms total %.2f  camera %.2f  brush %.2f  valid %.2f  preview %.2f  HUD %.2f" % [float(path_profile.get("path_process_total_ms", 0.0)), float(path_profile.get("camera_cursor_ms", 0.0)), float(path_profile.get("brush_preview_ms", 0.0)), float(path_profile.get("validity_ms", 0.0)), float(path_profile.get("preview_ms", 0.0)), float(path_profile.get("hud_ms", 0.0))]
	# Water perf: where the water surface frame time goes (resample vs mesh
	# build, how many cells, how many quads, and full vs incremental vs
	# localized) so we can see exactly which path is hot on the device.
	var water_perf_text := ""
	if water_visual and water_visual.has_method("get_perf"):
		var rebuilds: int = water_visual.get_rebuilds() if water_visual.has_method("get_rebuilds") else 0
		var wp: Dictionary = water_visual.get_perf()
		if not wp.is_empty():
			var kind := "FULL" if wp.get("full_rebuild", false) else ("LOCAL" if wp.get("localized", false) else "incr")
			water_perf_text = "\nWATER[%s] rebuilds %d  resample %.1f  mesh %.1f  cells %d  regions %d  quads %d" % [kind, rebuilds, float(wp.get("resample_ms", 0.0)), float(wp.get("mesh_ms", 0.0)), int(wp.get("cells_resampled", 0)), int(wp.get("regions", 0)), int(wp.get("quads", 0))]
		if water_visual.has_method("reset_rebuilds"):
			water_visual.reset_rebuilds()
	var costs_text := "\nCOSTS process %.1f  sculpt %.1f  preview %.1f  query %.1f  build %.1f" % [process_ms, float(last_frame_costs.get("sculpt_ms", 0.0)), float(last_frame_costs.get("preview_ms", 0.0)), float(last_frame_costs.get("preview_query_ms", 0.0)), float(last_frame_costs.get("preview_build_ms", 0.0))]
	debug_label.text = "FPS %.0f  process %.2f ms\n%s / %s  %dx%d  draw %d  triangles %d\nStatic memory %s  sculpt %.2f ms%s%s%s" % [Engine.get_frames_per_second(), process_ms, renderer, adapter, get_viewport().size.x, get_viewport().size.y, draw_calls, primitives, memory_text, float(native_stats.get("last_edit_ms", -1.0)), water_perf_text, costs_text, path_profile_text]

func _build_ui() -> void:
	hud = CanvasLayer.new(); add_child(hud)
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); margin.add_theme_constant_override("margin_left", 28); margin.add_theme_constant_override("margin_top", 24); hud.add_child(margin)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 5); margin.add_child(column)
	status_label = Label.new(); status_label.add_theme_font_size_override("font_size", 26); column.add_child(status_label)
	context_label = Label.new(); context_label.text = "COTTAGE • Select/Back: Terrain ↔ Cottage • X actions"; context_label.add_theme_font_size_override("font_size", 20); column.add_child(context_label)
	target_label = Label.new(); target_label.add_theme_font_size_override("font_size", 22); target_label.add_theme_color_override("font_color", Color("#ffe0a8")); column.add_child(target_label)
	debug_label = Label.new(); debug_label.position = Vector2(28, 285); debug_label.add_theme_font_size_override("font_size", 20); debug_label.visible = false; hud.add_child(debug_label)
	_build_pause_panel(); _build_tools_panel()

func _build_pause_panel() -> void:
	pause_panel = PanelContainer.new(); pause_panel.position = Vector2(430, 120); pause_panel.size = Vector2(430, 460); pause_panel.visible = false; hud.add_child(pause_panel)
	var box := VBoxContainer.new(); pause_panel.add_child(box); var title := Label.new(); title.text = "PAUSED\nWorld input suspended"; title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.add_theme_font_size_override("font_size", 28); box.add_child(title)
	for label in ["Save", "Reload", "Resume", "Quit"]:
		var button := Button.new(); button.text = label; button.focus_mode = Control.FOCUS_ALL; button.custom_minimum_size = Vector2(0, 56); button.add_theme_font_size_override("font_size", 24); _track_connect(button, "pressed", _pause_choice.bind(label)); box.add_child(button); _pause_buttons[label] = button

func _build_tools_panel() -> void:
	tools_panel = PanelContainer.new(); tools_panel.position = Vector2(330, 80); tools_panel.size = Vector2(560, 560); tools_panel.visible = false; hud.add_child(tools_panel)
	var scroll := ScrollContainer.new(); scroll.follow_focus = true; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; tools_panel.add_child(scroll)
	var box := VBoxContainer.new(); scroll.add_child(box); var title := Label.new(); title.text = "ACTIONS"; title.add_theme_font_size_override("font_size", 24); box.add_child(title)
	var all_labels: Array[String] = []
	all_labels.append_array(_terrain_action_labels)
	for label in _cottage_action_labels:
		if not all_labels.has(label): all_labels.append(label)
	for label in all_labels:
		var button := Button.new(); button.text = label; button.focus_mode = Control.FOCUS_ALL; button.custom_minimum_size = Vector2(0, 42); _track_connect(button, "pressed", _tool_choice.bind(label)); box.add_child(button); _tool_buttons[label] = button
	_update_action_buttons()

func _handle_menu_input(event: InputEvent) -> void:
	if event.is_action_pressed("m1_cancel"): _set_menu(false); get_viewport().set_input_as_handled(); return
	if event.is_action_pressed("m1_accept"):
		var focus := get_viewport().gui_get_focus_owner(); if focus is Button: (focus as Button).pressed.emit(); get_viewport().set_input_as_handled(); return
	if event.is_action_pressed("m1_height_down"): _move_focus(_pause_buttons.values(), 1); get_viewport().set_input_as_handled(); return
	if event.is_action_pressed("m1_height_up"): _move_focus(_pause_buttons.values(), -1); get_viewport().set_input_as_handled(); return

func _handle_overlay_input(event: InputEvent) -> void:
	if event.is_action_pressed("m1_cancel"): tools_open = false; detail_open = false; tools_panel.visible = false; _set_status("Actions closed"); get_viewport().set_input_as_handled(); return
	if event.is_action_pressed("m1_accept"):
		var focus := get_viewport().gui_get_focus_owner(); if focus is Button: (focus as Button).pressed.emit(); get_viewport().set_input_as_handled(); return
	if tools_open and event.is_action_pressed("m1_height_down"):
		_move_focus(_visible_action_buttons(), 1); get_viewport().set_input_as_handled(); return
	if tools_open and event.is_action_pressed("m1_height_up"):
		_move_focus(_visible_action_buttons(), -1); get_viewport().set_input_as_handled(); return
	if detail_open and event.is_action_pressed("m1_cycle_left"): _select_detail(-1); get_viewport().set_input_as_handled(); return
	if detail_open and event.is_action_pressed("m1_cycle_right"): _select_detail(1); get_viewport().set_input_as_handled(); return

func _move_focus(values: Array, direction: int) -> void:
	if values.is_empty(): return
	var focus := get_viewport().gui_get_focus_owner(); var index := values.find(focus); index = posmod(index + direction, values.size()); (values[index] as Button).grab_focus()

func _select_detail(direction: int) -> void:
	var view: Dictionary = building_world.get_building(selected_building_id)
	var details: Array = view.get("details", [])
	var ids: Array[String] = []
	var labels: Array[String] = []
	for detail_value in details:
		var detail: Dictionary = detail_value
		var detail_id := str(detail.get("id", ""))
		if detail_id.is_empty(): continue
		ids.append(detail_id)
		labels.append(str(detail.get("kind", "detail")))
	if ids.is_empty(): return
	var index := ids.find(selected_detail_id)
	selected_detail_id = ids[posmod(index + direction, ids.size())]
	var selected_index := ids.find(selected_detail_id)
	for detail_value in details:
		var selected_detail: Dictionary = detail_value
		if str(selected_detail.get("id", "")) == selected_detail_id:
			selected_surface_id = str(selected_detail.get("anchor", {}).get("surface_id", ""))
			break
	_set_status("Selected %s %s" % [labels[selected_index] if selected_index >= 0 else "detail", selected_detail_id])

func _cycle_surface(direction: int) -> void:
	var view: Dictionary = building_world.get_building(selected_building_id)
	var ids: Array[String] = []
	for surface_value in view.get("surfaces", []):
		var surface: Dictionary = surface_value
		if str(surface.get("kind", "wall")) == "wall" and not bool(surface.get("deleted", false)): ids.append(str(surface.get("id", "")))
	if ids.is_empty(): return
	var index := ids.find(selected_surface_id)
	selected_surface_id = ids[posmod(index + direction, ids.size())]
	_set_status("Support surface %s" % selected_surface_id)

func _cycle_building(direction: int) -> void:
	var buildings: Array[Dictionary] = building_world.get_buildings()
	if buildings.is_empty(): return
	var ids: Array[String] = []
	for building_value in buildings: ids.append(str(building_value.get("id", "")))
	var index := ids.find(selected_building_id)
	selected_building_id = ids[posmod(index + direction, ids.size())]
	selected_detail_id = ""
	_set_status("Selected cottage %s" % selected_building_id)
	_focus_selected_building()
	_update_presentation()

func _focus_selected_building() -> void:
	if view_context == "terrain":
		_cancel_current_edit("Terrain focus reset")
		terrain_cursor = Vector3(32.0, 8.0, 28.0)
		cursor = terrain_cursor
		_terrain_target_valid = false
		_terrain_target_point = Vector3.ZERO
	else:
		var view: Dictionary = building_world.get_building(selected_building_id)
		var transform_value = view.get("transform", Transform3D.IDENTITY)
		if transform_value is Transform3D:
			cursor = transform_value * Vector3(0, 2, 0)
		cursor.x = clampf(cursor.x, 0.5, float(PATCH_SIZE.x) - 0.5)
		cursor.y = clampf(cursor.y, 0.5, 31.5)
		cursor.z = clampf(cursor.z, 0.5, float(PATCH_SIZE.z) - 0.5)
		cottage_cursor = cursor
	camera_yaw = -1.1
	camera_pitch = 0.66
	camera_distance = 36.0

func _pause_choice(choice: String) -> void:
	match choice:
		"Save": _save_all()
		"Reload": _reload_all()
		"Resume": _set_menu(false)
		"Quit": _quit_cleanly()

func _tool_choice(choice: String) -> void:
	if choice in ["Foliage brush", "Tree brush", "Clear planting"]:
		if view_context != "terrain": return
		_cancel_current_edit("Planting tool selected")
		sculpt_tool = {"Foliage brush": "foliage", "Tree brush": "tree", "Clear planting": "clear_planting"}[choice]
		reference_mode = "ground"
		tools_open = false; detail_open = false; tools_panel.visible = false
		var rotate_hint := " • left/right rotate" if sculpt_tool in ["foliage", "tree"] else ""
		_set_status(choice + rotate_hint + " • A hold and move / release to commit • B cancel")
		return
	if choice in ["Raise", "Dig", "Level", "Slope", "Smooth"]:
		if view_context != "terrain":
			_set_status("Terrain tool unavailable in Cottage mode")
			return
		_set_sculpt_tool(choice)
		if sculpt_tool in ["level", "slope", "smooth"]: reference_mode = "ground"
		tools_open = false; detail_open = false; tools_panel.visible = false; _set_status("Terrain mode • %s • A hold / release, B cancel" % sculpt_tool.capitalize()); return
	if choice in ["Radius +", "Radius -", "Strength +", "Strength -", "Falloff +", "Falloff -", "Height snap: off", "Reference: ground", "Reference: wall", "Reference: ceiling", "Resample reference", "Keep reference"]:
		if view_context != "terrain":
			_set_status("Terrain settings unavailable in Cottage mode")
			return
		match choice:
			"Radius +": brush_radius = minf(8.0, brush_radius + (0.25 if precision_mode else 1.0))
			"Radius -": brush_radius = maxf(0.25, brush_radius - (0.25 if precision_mode else 1.0))
			"Strength +": brush_strength = minf(16.0, brush_strength + (0.5 if precision_mode else 2.0))
			"Strength -": brush_strength = maxf(0.5, brush_strength - (0.5 if precision_mode else 2.0))
			"Falloff +": brush_falloff = minf(1.0, brush_falloff + 0.1)
			"Falloff -": brush_falloff = maxf(0.0, brush_falloff - 0.1)
			"Height snap: off":
				height_snap_enabled = not height_snap_enabled
				if _tool_buttons.has("Height snap: off"):
					(_tool_buttons["Height snap: off"] as Button).text = "Height snap: on" if height_snap_enabled else "Height snap: off"
			"Reference: ground": reference_mode = "ground"
			"Reference: wall": reference_mode = "wall"
			"Reference: ceiling": reference_mode = "ceiling"
			"Resample reference": resample_reference()
			"Keep reference": keep_reference = not keep_reference
		tools_open = false; detail_open = false; tools_panel.visible = false
		_set_status("Brush %.1f / strength %.1f / falloff %.1f / snap %s / %s%s" % [brush_radius, brush_strength, brush_falloff, "on" if height_snap_enabled else "off", reference_mode, " / keep" if keep_reference else ""])
		_update_presentation()
		return
	if view_context != "building":
		_set_status("Cottage action unavailable in Terrain mode")
		return
	var view: Dictionary = building_world.get_building(selected_building_id); var details: Array = view.get("details", [])
	if selected_detail_id.is_empty() and not details.is_empty(): selected_detail_id = str(details[0]["id"])
	var selected_detail: Dictionary = {}
	for detail_value in details:
		var candidate: Dictionary = detail_value
		if str(candidate.get("id", "")) == selected_detail_id: selected_detail = candidate; break
	if selected_surface_id.is_empty() and not selected_detail.is_empty(): selected_surface_id = str(selected_detail.get("anchor", {}).get("surface_id", ""))
	var operation_ok := false
	match choice:
		"Miniature scale":
			if building_world.has_method("set_miniature_scale"):
				operation_ok = building_world.set_miniature_scale(selected_building_id)
				if operation_ok: _set_status("Miniature cottage scale applied")
			else:
				_set_status("Miniature scale API unavailable")
		"Move selected window":
			_begin_detail_move()
		"Support: next":
			_cycle_surface(1)
			return
		"Support: previous":
			_cycle_surface(-1)
			return
		"Replace selected":
			if not selected_detail_id.is_empty(): operation_ok = building_world.replace_detail(selected_building_id, selected_detail_id, "window_round")
		"Suppress / restore":
			if not selected_detail_id.is_empty(): operation_ok = building_world.suppress_detail(selected_building_id, selected_detail_id, bool(selected_detail.get("visible", true)))
		"Reattach selected":
			if not selected_detail_id.is_empty():
				var reattach_surface := ""
				for surface_value in view.get("surfaces", []):
					var surface: Dictionary = surface_value
					var surface_id := str(surface.get("id", ""))
					if surface_id == selected_surface_id and not bool(surface.get("deleted", false)):
						reattach_surface = surface_id
						break
				if reattach_surface.is_empty():
					for surface_value in view.get("surfaces", []):
						var surface: Dictionary = surface_value
						if not bool(surface.get("deleted", false)):
							reattach_surface = str(surface.get("id", ""))
							break
				var selected_anchor: Dictionary = selected_detail.get("anchor", {})
				var old_local = selected_anchor.get("local_position", Vector3(0, 4, -7.02))
				if selected_detail.get("resolved_position", null) is Vector3: old_local = selected_detail["resolved_position"]
				if not reattach_surface.is_empty() and old_local is Vector3: operation_ok = building_world.reattach_detail(selected_building_id, selected_detail_id, reattach_surface, old_local)
		"Add flower box", "Add shutter":
			var selected_anchor: Dictionary = selected_detail.get("anchor", {})
			var surface_id := str(selected_anchor.get("surface_id", ""))
			if surface_id.is_empty():
				for surface_value in view.get("surfaces", []):
					var surface: Dictionary = surface_value
					if not bool(surface.get("deleted", false)): surface_id = str(surface.get("id", "")); break
			if not surface_id.is_empty():
				var p: Vector3 = selected_detail.get("resolved_position", Vector3(0, 3.3, -view["dimensions"].z * 0.5 - 0.02))
				var kind := "shutter" if choice == "Add shutter" else "flower_box"
				if kind == "shutter":
					var horizontal_axis := 0
					for surface: Dictionary in view.get("surfaces", []):
						if surface["id"] == surface_id and str(surface.get("orientation", "")) in ["left", "right"]: horizontal_axis = 2
					p[horizontal_axis] += 2.2
				else: p.y -= 2.0
				operation_ok = not building_world.add_detail(selected_building_id, kind, surface_id, p, kind + "_wood").is_empty()
		"Delete selected surface":
			var delete_surface_id := str(selected_detail.get("anchor", {}).get("surface_id", ""))
			if delete_surface_id.is_empty():
				var surfaces: Array = view.get("surfaces", [])
				if not surfaces.is_empty(): delete_surface_id = str(surfaces[0].get("id", ""))
			if not delete_surface_id.is_empty(): operation_ok = building_world.delete_surface(selected_building_id, delete_surface_id)
		"Material: warm plaster": operation_ok = building_world.set_material(selected_building_id, "warm_plaster")
		"Duplicate cottage":
			var duplicate_id: String = building_world.duplicate_building(selected_building_id, Vector3(0, 0, 18))
			if not duplicate_id.is_empty():
				selected_building_id = duplicate_id
				selected_detail_id = ""
				selected_surface_id = ""
				operation_ok = true
			if operation_ok: _focus_selected_building()
			_set_status("Cottage duplicated" if not duplicate_id.is_empty() else "Duplicate rejected")
		"Close": tools_open = false; detail_open = false; tools_panel.visible = false
	if choice != "Move selected window":
		if operation_ok: _record_history("building")
		tools_open = false; detail_open = false; tools_panel.visible = false
		_update_action_buttons()
		_update_presentation()

func _set_menu(open: bool) -> void:
	menu_open = open; pause_panel.visible = open
	if open:
		tools_open = false
		detail_open = false
		if tools_panel: tools_panel.visible = false
		_cancel_current_edit("Paused")
		(_pause_buttons["Save"] as Button).grab_focus()
	else:
		_update_action_buttons()
		_set_status("Terrain mode" if view_context == "terrain" else "Cottage mode")

func _save_all() -> bool:
	if landscape_active:
		_set_status("Finish or cancel planting before saving"); return false
	var ok := false
	if backend and backend.has_method("save_world"):
		var document: Dictionary = building_world.get_document()
		document["landscape"] = landscape_state.document()
		ok = backend.save_world(document)
	_set_status("World saved" if ok else "Save failed (cottage design kept in memory)")
	if ok: _building_dirty = false
	return ok

func _world_is_dirty() -> bool:
	if _building_dirty: return true
	if backend and backend.has_method("stats"):
		return bool((backend.stats() as Dictionary).get("dirty", false))
	return false

func _reload_all() -> bool:
	var ok: bool = backend and backend.has_method("load_world") and backend.load_world()
	if ok:
		_history_tags.clear()
		_redo_tags.clear(); _landscape_history.clear(); _landscape_redo.clear()
		var loaded_document = backend.get("loaded_building_document")
		if not loaded_document is Dictionary or not BuildingWorldScript.validate_document(loaded_document) or not _load_cottage_document(loaded_document):
			_set_status("Reload failed: cottage design missing or invalid")
			return false
		_restore_landscape(loaded_document)
		_building_dirty = false
		_set_status("World and cottage reloaded")
		_update_presentation()
	else: _set_status("Reload failed")
	return ok

func _set_status(message: String) -> void:
	status_text = message
	if status_label: status_label.text = "HEARTHVALE / M1   %s" % message
	if context_label:
		context_label.text = ("TERRAIN • Select/Back: Cottage ↔ Terrain • X tools • A hold/release • B cancel" if view_context == "terrain" else "COTTAGE • Select/Back: Terrain ↔ Cottage • X actions • A resize • B cancel")

func _quit_cleanly() -> void:
	if _shutting_down: return
	_cancel_current_edit("Quit")
	if _world_is_dirty() and not _save_all():
		_set_status("Save failed; quit cancelled")
		_set_menu(true)
		return
	_shutting_down = true; set_process(false); set_process_input(false); var tree := get_tree(); var old_backend := backend; backend = null; if old_backend: old_backend.queue_free(); await tree.process_frame; await tree.process_frame; queue_free(); tree.quit()

func _restore_landscape(document: Dictionary) -> void:
	if document.has("landscape") and landscape_state.restore(document["landscape"]):
		garden_visual.reset_records(landscape_state.records)
		_sync_water_visual()
		return
	landscape_state = LandscapeScript.new()
	var rng := RandomNumberGenerator.new(); rng.seed = 1042
	for point in [Vector3(10, 8, 9), Vector3(31, 8, 10), Vector3(12, 8, 29), Vector3(34, 8, 31), Vector3(9, 8, 37), Vector3(34, 8, 17), Vector3(27, 8, 35), Vector3(7, 8, 20)]:
		var ground := _plant_ground(point, true)
		if not ground.is_empty(): landscape_state.add("tree", ground["point"], rng.randi_range(0, 2))
	# Plant in loose drifts instead of an even procedural dusting. The cottage
	# frontage and the central sculpting lawn remain calm, readable spaces.
	var cluster_centers := [Vector2(9, 13), Vector2(11, 33), Vector2(17, 31), Vector2(29, 9), Vector2(33, 14), Vector2(33, 34), Vector2(36, 24)]
	for cluster: Vector2 in cluster_centers:
		for sample in 12:
			var angle := rng.randf_range(0.0, TAU)
			var radius := sqrt(rng.randf()) * rng.randf_range(1.2, 3.4)
			var point := Vector3(cluster.x + cos(angle) * radius, 8, cluster.y + sin(angle) * radius)
			if point.x > 17 and point.x < 28 and point.z > 13 and point.z < 25: continue
			var ground := _plant_ground(point, true)
			if not ground.is_empty(): landscape_state.add("foliage", ground["point"], rng.randi_range(0, Flora.variant_count("foliage") - 1))
	for point in [Vector3(37, 7, 7), Vector3(37, 7, 12), Vector3(37, 7, 30), Vector3(36, 7, 38), Vector3(32, 8, 37), Vector3(13, 8, 34), Vector3(8, 8, 16)]:
		var ground := _plant_ground(point, true)
		if not ground.is_empty(): landscape_state.add("rock", ground["point"], rng.randi_range(0, 2))
	garden_visual.reset_records(landscape_state.records)
	_sync_water_visual()

func _plant_ground(point: Vector3, from_top: bool = false) -> Dictionary:
	if not backend or not backend.is_ready(): return {}
	var unit := float(backend.voxel_scale)
	point.x = snappedf(point.x, Grid.UNIT); point.z = snappedf(point.z, Grid.UNIT)
	var x := floori(point.x / unit); var z := floori(point.z / unit)
	if x < 1 or z < 1 or point.x >= 47 or point.z >= 47: return {}
	var surface := -1
	var closest := INF
	var reach := ceili(2.0 / unit)
	var low := 0 if from_top else maxi(0, floori(point.y / unit) - reach)
	var high := int(backend.patch_size.y) - 2 if from_top else mini(int(backend.patch_size.y) - 2, floori(point.y / unit) + reach)
	for y in range(high, low - 1, -1):
		if backend.voxel_at(Vector3i(x, y, z)) == 0: continue
		if backend.voxel_at(Vector3i(x, y + 1, z)) != 0: continue
		var distance := absf((y + 1) * unit - point.y)
		if not from_top and distance > 2.0: continue
		if distance < closest: closest = distance; surface = y
		if from_top: break
	if surface < 0: return {}
	var p := Vector3(point.x, (surface + 1) * unit, point.z)
	if p.y <= 5.05: return {}
	for building: Dictionary in building_world.get_buildings():
		var local: Vector3 = (building["transform"] as Transform3D).affine_inverse() * p
		var dims: Vector3 = building["dimensions"]
		if absf(local.x) < dims.x * 0.5 + 1.0 and absf(local.z) < dims.z * 0.5 + 1.0: return {}
	return {"point": p}

func _begin_plant_stroke() -> void:
	if landscape_active or stroke_active or menu_open or tools_open or detail_open or view_context != "terrain": return
	_landscape_before = landscape_state.document()
	landscape_active = true; _plant_elapsed = 0.0; _plant_last = Vector3.INF; _plant_sequence = 0
	_paint_plant_sample()

func _update_plant_stroke(delta: float) -> void:
	_plant_elapsed += delta
	while _plant_elapsed >= 0.15:
		_plant_elapsed -= 0.15
		_paint_plant_sample()

func _rotate_plant_brush(direction: int) -> void:
	if direction == 0 or sculpt_tool not in ["tree", "foliage"]: return
	var step := PLANT_ROTATION_FINE_DEGREES if precision_mode else PLANT_ROTATION_COARSE_DEGREES
	planting_yaw_degrees = fposmod(planting_yaw_degrees + step * float(signi(direction)), 360.0)
	_set_status("%s brush • rotation %.0f° • A hold and move / release to commit" % [sculpt_tool.capitalize(), planting_yaw_degrees])

func _paint_plant_sample() -> void:
	var center := _terrain_target_point if _terrain_target_valid else cursor
	if sculpt_tool == "tree" and center.distance_to(_plant_last) < 2.8: return
	if sculpt_tool == "clear_planting":
		landscape_state.erase_brush(center, brush_radius)
	else:
		var rng := RandomNumberGenerator.new(); rng.seed = int(_landscape_before.get("next_id", 1)) * 7919 + _plant_sequence * 97
		for sample_index in (1 if sculpt_tool == "tree" else 5):
			var angle := rng.randf_range(0, TAU)
			var radius := sqrt(rng.randf()) * brush_radius if sculpt_tool != "tree" else 0.0
			var ground := _plant_ground(center + Vector3(cos(angle) * radius, 0, sin(angle) * radius))
			if not ground.is_empty(): landscape_state.add(sculpt_tool, ground["point"], rng.randi_range(0, Flora.variant_count(sculpt_tool) - 1), planting_yaw_degrees)
	_plant_last = center; _plant_sequence += 1
	garden_visual.apply_records(landscape_state.records)
	_sync_water_visual()

func _end_plant_stroke() -> void:
	if not landscape_active: return
	landscape_active = false
	if landscape_state.document() != _landscape_before:
		_record_history("landscape")
		_set_status("Planting committed • LB undo")
	else: _set_status("No planting change: move to clear ground or clear existing planting")
	_landscape_before.clear()

func _load_cottage_document(document: Dictionary) -> bool:
	# The checkpoint envelope owns landscape; building history owns cottages.
	# Keep the two authoritative components separate after deserialization.
	var cottage := document.duplicate(true)
	cottage.erase("landscape")
	return building_world.load_document(cottage)

extends RefCounted
## Single-flight terrain preview service. Idle aiming uses one isolated snapshot
## worker and may keep the last completed exact result at its ORIGINAL world
## position while a newer request computes. Ordinary active brushes reuse the
## authoritative live frontier; oversized brushes remain asynchronous so they
## cannot stall gameplay.
const Snapshot = preload("res://scripts/sculpt_preview_snapshot.gd")
const Query = preload("res://scripts/sculpt_preview_query.gd")
const Live = preload("res://scripts/sculpt_live_next_layer.gd")
const Buffers = preload("res://scripts/terrain_preview_buffers.gd")
const LIVE_NATIVE_RADIUS_MAX := 24.0
var _thread: Thread
var _running_key: Array = []
var _wanted_key: Array = []
var _ready_key: Array = []
var _ready_plan: Dictionary = {}
var _latest_key: Array = []
var _latest_plan: Dictionary = {}
var query_count := 0
var discarded_count := 0
var last_capture_ms := 0.0
var last_query_ms := 0.0
var last_pack_ms := 0.0
var last_snapshot_bytes := 0
var last_latency_ms := 0.0
var _started_usec := 0
var _epoch := 0
var _running_epoch := 0

func update(source: Node, tool: String, center: Vector3, settings: Dictionary, reference: Dictionary, key: Array) -> Dictionary:
	_wanted_key = key.duplicate(true)
	last_capture_ms = 0.0
	_collect()
	var active := bool(source.get("_stroke_active"))
	var native_radius := float(source.get("_stroke_settings").get("radius", 0.0)) if active else 0.0
	if active and native_radius <= LIVE_NATIVE_RADIUS_MAX:
		var started := Time.get_ticks_usec()
		var live := Live.plan(source, center)
		if bool(live.get("valid", false)):
			var packed := Buffers.pack(live)
			live["packed"] = packed
			# Gameplay consumes packed output only, matching worker ownership.
			live.erase("changes")
			live["_stale"] = false
			live["_request_key"] = key.duplicate(true)
			_ready_key = key.duplicate(true)
			_ready_plan = live
			_latest_key = key.duplicate(true)
			_latest_plan = live
			last_query_ms = float(live.get("query_ms", 0.0))
			last_pack_ms = float(packed.get("pack_ms", 0.0))
			last_latency_ms = (Time.get_ticks_usec() - started) / 1000.0
			query_count += 1
			return live
		return {}
	if _ready_key == key:
		return _ready_plan
	if _thread == null:
		var snapshot: RefCounted = Snapshot.capture(source, tool, center, settings, reference)
		if snapshot != null:
			last_capture_ms = snapshot.capture_ms
			last_snapshot_bytes = snapshot.copied_bytes
			_running_key = key.duplicate(true)
			_running_epoch = _epoch
			_started_usec = Time.get_ticks_usec()
			_thread = Thread.new()
			var error := _thread.start(_compute.bind(snapshot, tool, center, settings.duplicate(true), snapshot.plane_reference, false))
			if error != OK:
				_thread = null
				push_error("Cannot start terrain preview worker: %s" % error)
			else:
				query_count += 1
	# Idle terrain is unchanged while the cursor moves. Keep the last exact
	# completed overlay at the coordinates it was actually computed for; the
	# caller dims it and labels the newer request as pending. Never do this
	# during an active stroke because terrain beneath an old plan may have moved.
	if not active and not _latest_plan.is_empty():
		var stale := _latest_plan.duplicate(false)
		stale["_stale"] = true
		stale["_request_key"] = _latest_key.duplicate(true)
		return stale
	return {}

func invalidate() -> void:
	_epoch += 1
	_wanted_key.clear()
	_ready_key.clear()
	_ready_plan = {}
	_latest_key.clear()
	_latest_plan = {}
	_collect()

func _collect() -> void:
	if _thread == null or _thread.is_alive(): return
	var result: Dictionary = _thread.wait_to_finish()
	_thread = null
	if _running_epoch != _epoch or not bool(result.get("valid", false)):
		discarded_count += 1
		return
	result["_stale"] = false
	result["_request_key"] = _running_key.duplicate(true)
	_latest_key = _running_key.duplicate(true)
	_latest_plan = result
	last_query_ms = float(result.get("query_ms", 0.0))
	last_pack_ms = float(result.get("packed", {}).get("pack_ms", 0.0))
	last_latency_ms = (Time.get_ticks_usec() - _started_usec) / 1000.0
	if _running_key == _wanted_key and not _wanted_key.is_empty():
		_ready_key = _running_key.duplicate(true)
		_ready_plan = result
	else:
		discarded_count += 1

static func _compute(snapshot: RefCounted, tool: String, center: Vector3, settings: Dictionary, reference: Dictionary, retain_changes: bool = true) -> Dictionary:
	# The adapter node is private to this worker, is never added to the tree,
	# and reads only its own snapshot. The actual terrain is never accessed.
	var query := Query.new()
	var result: Dictionary = query.plan(snapshot, tool, center, settings, reference)
	query.free()
	if snapshot.voxels.out_of_bounds_reads != 0:
		push_error("Terrain preview snapshot missed %d reads" % snapshot.voxels.out_of_bounds_reads)
		return {"valid": false}
	if bool(result.get("valid", false)):
		result["packed"] = Buffers.pack(result)
		# Gameplay needs counts, cell indices and packed geometry, not thousands
		# of temporary per-cell dictionaries. Destroy those on THIS worker;
		# otherwise replacing a completed result adds a main-thread free spike.
		if not retain_changes: result.erase("changes")
	if not retain_changes:
		# Ownership was transferred at Thread.start. Reclaim the copied front
		# metadata and native volume here rather than when the main thread joins.
		snapshot.state = {}
		snapshot.voxels = null
	return result

func close() -> void:
	# Only shutdown may join a running job. Menus/focus changes invalidate
	# without blocking; the result is collected and discarded when finished.
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_ready_plan = {}
	_latest_plan = {}

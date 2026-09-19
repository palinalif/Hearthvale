extends Node
## Debug-only main-loop frame clock. Sits as the FIRST child of the root
## window, so its _process runs before the scene's; comparing its tick
## against the scene's own start/end marks brackets the three parts of a
## frame the scene's phase timers cannot see:
##   pre  = engine bookkeeping + input flush + any root children before the scene
##   scene = the scene chain's measured process
##   post = everything after the scene until the next probe tick
##          (root children after it, physics step, render-thread hand-off,
##           vsync wait)
## Inert in release builds (never added there). Prints a rolling summary
## every 300 frames and answers the bridge's "frame_clock" action.

var scene: Node = null

var _prev_t := 0
var _prev_scene_end := 0
var _n := 0
var _sum_pre := 0.0
var _sum_scene := 0.0
var _sum_post := 0.0
var _sum_period := 0.0
var last: Dictionary = {}

func attach(scene_node: Node) -> void:
	scene = scene_node

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _prev_t > 0 and scene != null:
		# 4.7.2 gotcha: float()/int() constructors reject Variant args; use
		# typed assignment for the Variant coming from scene.get().
		var s_start: float = scene.get("_fc_scene_start")
		var s_end: float = scene.get("_fc_scene_end")
		var pre := s_start - float(_prev_t)
		var scene_ms := s_end - s_start
		# post = from the scene's end (last frame) to this probe tick:
		# post-scene nodes + physics + render hand-off + vsync wait.
		var post := now - _prev_scene_end
		if pre < 0 or post < 0 or pre > 500000 or post > 500000:
			# first frame after attach / anomaly: skip, not average
			_prev_t = now
			_prev_scene_end = int(s_end)
			return
		_n += 1
		_sum_pre += pre / 1000.0
		_sum_scene += scene_ms / 1000.0
		_sum_post += post / 1000.0
		_sum_period += (now - _prev_t) / 1000.0
		if _n % 300 == 0:
			last = {
				"period_ms": _sum_period / _n, "pre_ms": _sum_pre / _n,
				"scene_ms": _sum_scene / _n, "post_ms": _sum_post / _n,
			}
			print("FRAME_CLOCK ", JSON.stringify(last))
			_n = 0
			_sum_pre = 0.0
			_sum_scene = 0.0
			_sum_post = 0.0
			_sum_period = 0.0
	_prev_t = now
	if scene != null:
		var e: int = scene.get("_fc_scene_end")
		_prev_scene_end = e

extends Node2D
class_name Character

@export var speed_px: float = 90.0
@export var visit_min_s: float = 2.0
@export var visit_max_s: float = 5.0

var char_name: String = ""
var _segments: Array = []              # Array of Array[Vector2]
var _seg_idx := 0
var _i := 0
var _ship: Node = null
var _waiting := false

func begin_visit(paths: Array, ship: Node, spawn_pos: Vector2) -> void:
	_segments.clear()
	for seg in paths:
		var arr: Array[Vector2] = []
		for p in seg:
			arr.append(Vector2(p))
		_segments.append(arr)
	_ship = ship
	global_position = spawn_pos
	_seg_idx = 0
	_i = 0
	_waiting = false
	set_process(true)

func _process(delta: float) -> void:
	if _waiting:
		return
	if _seg_idx >= _segments.size():
		if is_instance_valid(_ship) and "request_depart" in _ship:
			_ship.request_depart()
		queue_free()
		return
	var seg: Array[Vector2] = _segments[_seg_idx]
	if _advance_along(seg, delta):
		_seg_idx += 1
		_i = 0
		if _seg_idx < _segments.size():
			if _seg_idx < _segments.size() - 1:
				_waiting = true
				var t := randf_range(visit_min_s, visit_max_s)
				await get_tree().create_timer(t).timeout
				_waiting = false

func _advance_along(points: Array[Vector2], delta: float) -> bool:
	if points.is_empty(): return true
	if _i >= points.size(): return true
	var tgt := points[_i]
	var v := tgt - global_position
	var d := v.length()
	if d < 2.0:
		_i += 1
		return _i >= points.size()
	var step := v.normalized() * speed_px * delta
	if step.length() > d:
		global_position = tgt
	else:
		global_position += step
	return false

func _draw() -> void:
	# tiny placeholder dot
	draw_circle(Vector2.ZERO, 6.0, Color(0.9, 0.6, 0.2))

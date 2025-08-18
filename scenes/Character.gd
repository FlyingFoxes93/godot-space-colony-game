extends Node2D
class_name Character

@export var speed_px: float = 90.0
@export var visit_min_s: float = 2.0
@export var visit_max_s: float = 5.0

var char_name: String = ""
var _path: Array[Vector2] = []
var _path_back: Array[Vector2] = []
var _i := 0
var _phase := "to_shop"  # to_shop -> visiting -> to_dock -> done
var _ship: Node = null

func begin_visit(path_to: Array, path_back: Array, ship: Node, spawn_pos: Vector2) -> void:
	# Accept generic Arrays; store as Vector2 arrays
	_path.clear()
	for p in path_to: _path.append(Vector2(p))
	_path_back.clear()
	for p in path_back: _path_back.append(Vector2(p))
	_ship = ship
	global_position = spawn_pos
	_i = 0
	_phase = "to_shop"
	set_process(true)

func _process(delta: float) -> void:
	match _phase:
		"to_shop":
			if _advance_along(_path, delta):
				_phase = "visiting"
				var t := randf_range(visit_min_s, visit_max_s)
				await get_tree().create_timer(t).timeout
				_phase = "to_dock"
				_i = 0
		"to_dock":
			if _advance_along(_path_back, delta):
				_phase = "done"
				if is_instance_valid(_ship) and "request_depart" in _ship:
					_ship.request_depart()  # tell the ship we're back aboard
				queue_free()
		_:
			pass

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

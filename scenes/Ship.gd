extends Node2D

@export var speed_px: float = 140.0

signal arrived   # when we reach the dock and open doors
signal departed  # when we exit the map

enum State { APPROACH, DWELL, DEPART, DONE }
var state: State = State.APPROACH

var dock_pos: Vector2
var depart_pos: Vector2
var _ready_to_leave := false

func set_route(dock_target: Vector2, depart_target: Vector2) -> void:
	dock_pos = dock_target
	depart_pos = depart_target
	state = State.APPROACH
	set_process(true)

func request_depart() -> void:
	_ready_to_leave = true
	if state == State.DWELL:
		state = State.DEPART

func _process(delta: float) -> void:
	match state:
		State.APPROACH:
			if _move_towards(dock_pos, delta):
				state = State.DWELL
				emit_signal("arrived")  # passenger may spawn now
		State.DWELL:
			# wait until request_depart() is called
			if _ready_to_leave:
				state = State.DEPART
		State.DEPART:
			if _move_towards(depart_pos, delta):
				state = State.DONE
				emit_signal("departed")
				queue_free()
		_:
			pass

func _move_towards(target: Vector2, delta: float) -> bool:
	var v := target - global_position
	var d := v.length()
	if d < 1.5:
		global_position = target
		return true
	var step := v.normalized() * speed_px * delta
	if step.length() > d:
		global_position = target
	else:
		global_position += step
	return false

func _draw() -> void:
	# cute bubble ship
	draw_circle(Vector2.ZERO, 10, Color(0.95, 0.8, 0.3))
	draw_circle(Vector2(4, -3), 3, Color(1,1,1,0.8))

extends Node2D

@export var cell_size: int = 64
@export var speed_px: float = 90.0
@export var pause_min_s: float = 0.6
@export var pause_max_s: float = 1.4

var current_cell: Vector2i
var path_cells: Array[Vector2i] = []       # grid path
var path_world: Array[Vector2] = []        # world waypoints (centers)
var _target_index: int = 0

# Provided by Main
var request_new_path_cells: Callable        # (start:Vector2i, goal:Vector2i) -> Array[Vector2i]
var random_hall_cell: Callable              # () -> Vector2i

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	if path_world.is_empty():
		# idle: pick a new hall destination
		if random_hall_cell.is_valid() and request_new_path_cells.is_valid():
			var dest: Vector2i = random_hall_cell.call()
			_set_path_from_cells(request_new_path_cells.call(current_cell, dest))
		return

	var target := path_world[_target_index]
	var dir := (target - global_position)
	var dist := dir.length()
	if dist < 2.0:
		# reached this waypoint: advance
		_target_index += 1
		# update our current_cell to match the waypoint's cell
		if _target_index - 1 >= 0 and _target_index - 1 < path_cells.size():
			current_cell = path_cells[_target_index - 1]

		if _target_index >= path_world.size():
			# arrived at final cell; settle and clear path
			if path_cells.size() > 0:
				current_cell = path_cells.back()
			path_world.clear()
			path_cells.clear()
			_target_index = 0
			await get_tree().create_timer(randf_range(pause_min_s, pause_max_s)).timeout
		else:
			# continue to next point
			pass
	else:
		var step := dir.normalized() * speed_px * delta
		if step.length() > dist:
			global_position = target
		else:
			global_position += step

func set_spawn(cell: Vector2i, world_pos: Vector2) -> void:
	current_cell = cell
	global_position = world_pos

func _set_path_from_cells(cells: Array[Vector2i]) -> void:
	path_cells = cells.duplicate()
	path_world.clear()
	for c in path_cells:
		path_world.append(_cell_to_center(c))
	_target_index = 0

func _cell_to_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * cell_size + cell_size * 0.5, c.y * cell_size + cell_size * 0.5)

func _draw() -> void:
	# simple character blob
	draw_circle(Vector2.ZERO, min(10.0, cell_size * 0.25), Color(0.18, 0.22, 0.28, 1))
	draw_circle(Vector2.ZERO, min(9.0, cell_size * 0.23), Color(0.85, 0.92, 1.0, 1))

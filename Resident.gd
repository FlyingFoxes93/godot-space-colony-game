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
var random_walk_target: Callable            # () -> Dictionary{"hall":Vector2i, "inside":Vector2i}

# -- Lifecycle ------------------------------------------------------------
# Enables processing so the resident can move each frame.
func _ready() -> void:
	set_process(true)

# Handles idle wandering and step-by-step movement along the current path.
func _process(delta: float) -> void:
	if path_world.is_empty():
		# idle: pick a new destination (hall or room)
		if random_walk_target.is_valid() and request_new_path_cells.is_valid():
			var data: Dictionary = random_walk_target.call()
			var hall: Vector2i = data.get("hall", current_cell)
			var inside: Vector2i = data.get("inside", hall)
			var cells: Array[Vector2i] = request_new_path_cells.call(current_cell, hall)
			if not cells.is_empty() and inside != hall:
				cells.append(inside)
			_set_path_from_cells(cells)
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

# Sets the starting cell and world position when the resident spawns.
func set_spawn(cell: Vector2i, world_pos: Vector2) -> void:
	current_cell = cell
	global_position = world_pos

# Converts a list of grid cells into a world-space path for the resident to follow.
func _set_path_from_cells(cells: Array[Vector2i]) -> void:
	path_cells = cells.duplicate()
	path_world.clear()
	for c in path_cells:
		path_world.append(_cell_to_center(c))
	_target_index = 0

# Returns the world coordinate at the center of a given grid cell.
func _cell_to_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * cell_size + cell_size * 0.5, c.y * cell_size + cell_size * 0.5)

# -- Rendering ------------------------------------------------------------
# Draws the simple circular representation of a resident.
func _draw() -> void:
	draw_circle(Vector2.ZERO, min(10.0, cell_size * 0.25), Color(0.18, 0.22, 0.28, 1))
	draw_circle(Vector2.ZERO, min(9.0, cell_size * 0.23), Color(0.85, 0.92, 1.0, 1))

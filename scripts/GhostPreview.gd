extends Node2D

var cell_size: int = 64
var size_cells: Vector2i = Vector2i(1, 1)
var door_cells: Array = []   # untyped for safety when fed from Dictionaries
var valid: bool = false

# -- Configuration -------------------------------------------------------
# Sets up the preview's footprint, size and door markers for the selected
# blueprint.
func configure(cell_size_: int, size_: Vector2i, doors_: Array) -> void:
	cell_size = cell_size_
	size_cells = size_
	door_cells.clear()
	for d in doors_:
		door_cells.append(Vector2i(d))  # force-cast each element

# Marks whether the current placement is valid and redraws to update color.
func set_valid(v: bool) -> void:
	valid = v
	queue_redraw()

# -- Rendering ----------------------------------------------------------
# Draws the translucent footprint and door indicators for the pending build.
func _draw() -> void:
	var sz := Vector2(size_cells.x * cell_size, size_cells.y * cell_size)
	var top_left := Vector2(-sz.x / 2.0, -sz.y / 2.0)

	var main_color := (Color(0, 1, 0, 0.18) if valid else Color(1, 0, 0, 0.18))
	var border := (Color(0, 1, 0, 0.6) if valid else Color(1, 0, 0, 0.6))

	draw_rect(Rect2(top_left, sz), main_color, true)
	draw_rect(Rect2(top_left, sz), border, false, 2.0)

	# door pips
	for d in door_cells:
		var c := Vector2(
			top_left.x + (d.x + 0.5) * cell_size,
			top_left.y + (d.y + 0.5) * cell_size
		)
		var r := Rect2(c - Vector2(6, 6), Vector2(12, 12))
		draw_rect(r, border, true)

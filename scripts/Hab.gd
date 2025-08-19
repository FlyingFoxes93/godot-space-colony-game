extends Node2D
@export var cell_size: int = 64
@export var size_cells: Vector2i = Vector2i(1, 1) # will be set to 2x2 / 3x2 by Main
@export var fill: Color = Color.hex(0x5DC1B9FF)
@export var stroke: Color = Color(0x111111ff)

# -- Rendering ------------------------------------------------------------
# Draws the hab module as a filled rectangle with an outline.
func _draw() -> void:
	var sz := Vector2(size_cells.x * cell_size, size_cells.y * cell_size)
	var rect := Rect2(-sz * 0.5, sz)
	draw_rect(rect, fill, true)
	draw_rect(rect, stroke, false, 2.0)

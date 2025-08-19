extends Node2D

@export var cell_size: int = 64
@export var cols: int = 30
@export var rows: int = 18
@export var line_color: Color = Color(1, 1, 1, 0.08)

# -- Drawing -------------------------------------------------------------
# Renders a grid to visualize the map's cell layout.
func _draw() -> void:
	for x in range(cols + 1):
		draw_line(Vector2(x * cell_size, 0), Vector2(x * cell_size, rows * cell_size), line_color, 1.0)
	for y in range(rows + 1):
		draw_line(Vector2(0, y * cell_size), Vector2(cols * cell_size, y * cell_size), line_color, 1.0)

# Requests a redraw, e.g. after changing grid dimensions.
func refresh() -> void:
	queue_redraw()

extends Node2D

@export var cell_size: int = 64
@export var size_cells: Vector2i = Vector2i(1, 1) # always 1x1
@export var floor_color: Color = Color.hex(0x7A8FA9FF)   # corridor floor
@export var edge_color: Color  = Color(0x111111ff)       # outline/grout
@export var edge_px: int = 2                             # border thickness
@export var seam_px: int = 0                             # tiny inset for tile seam

var mask: int = 0  # N=1, E=2, S=4, W=8

# --- Visual Updates ---
# Sets the neighbor mask used to determine which edges of the hall are visible
# and schedules the tile to redraw with the new state.
func set_mask(m: int) -> void:
	mask = m
	queue_redraw()

# Draws the corridor floor and outlines any sides that do not connect to
# another hall segment.
func _draw() -> void:
	var half := cell_size * 0.5
	var base := Rect2(Vector2(-half, -half), Vector2(cell_size, cell_size))

	# Slight inset so adjacent tiles have a hairline seam (reads as tiles)
	var inset := float(seam_px)
	var inner := Rect2(base.position + Vector2(inset, inset),
					   base.size - Vector2(inset * 2.0, inset * 2.0))

	# Solid floor
	draw_rect(inner, floor_color, true)

	# Draw edges only where there is NO neighbor (keeps interior edges invisible)
	var w := float(edge_px)
	if (mask & 1) == 0: # top
		draw_rect(Rect2(inner.position, Vector2(inner.size.x, w)), edge_color, true)
	if (mask & 2) == 0: # right
		draw_rect(Rect2(inner.position + Vector2(inner.size.x - w, 0), Vector2(w, inner.size.y)), edge_color, true)
	if (mask & 4) == 0: # bottom
		draw_rect(Rect2(inner.position + Vector2(0, inner.size.y - w), Vector2(inner.size.x, w)), edge_color, true)
	if (mask & 8) == 0: # left
		draw_rect(Rect2(inner.position, Vector2(w, inner.size.y)), edge_color, true)

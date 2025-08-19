extends Node2D

@export var cell_size: int = 64
@export var size_cells: Vector2i = Vector2i(2, 1)      # default 2×1 dock slab
@export var floor_color: Color = Color.hex(0x6F86A6FF) # dock floor
@export var edge_color: Color  = Color(0x111111ff)     # outline
@export var edge_px: int = 2

var approach_dir: int = 0  # 0=N,1=E,2=S,3=W (set by Main from rot)

# -- Rendering -----------------------------------------------------------
# Draws the dock pad and an arrow showing the spaceward approach direction.
func _draw() -> void:
	var sz: Vector2 = Vector2(float(size_cells.x * cell_size), float(size_cells.y * cell_size))
	var rect: Rect2 = Rect2(-sz * 0.5, sz)
	draw_rect(rect, floor_color, true)
	draw_rect(rect, edge_color, false, float(edge_px))

	# Facing chevron on the approach side
	var cx: Vector2 = Vector2.ZERO
	var tip: Vector2 = Vector2.ZERO
	match approach_dir:
		0:
			tip = Vector2(0, -sz.y * 0.48)
		1:
			tip = Vector2(sz.x * 0.48, 0)
		2:
			tip = Vector2(0,  sz.y * 0.48)
		3:
			tip = Vector2(-sz.x * 0.48, 0)
		_:
			tip = Vector2.ZERO

	var left: Vector2  = tip - (tip - cx).orthogonal().normalized() * 12.0
	var right: Vector2 = tip + (tip - cx).orthogonal().normalized() * 12.0
	draw_line(left, tip, edge_color, 2.0)
	draw_line(right, tip, edge_color, 2.0)

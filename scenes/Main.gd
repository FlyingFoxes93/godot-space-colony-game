extends Node2D
const BuildDefs = preload("res://scripts/BuildDefs.gd")
const GhostPreview = preload("res://scripts/GhostPreview.gd")
const ResidentScene := preload("res://scenes/Resident.tscn")
const ShipScene := preload("res://scenes/Ship.tscn")
const CharacterScene := preload("res://scenes/Character.tscn")

@export var cell_size: int = 64
@export var cols: int = 30
@export var rows: int = 18
@export var starting_credits: int = 1000
@export var refund_rate: float = 0.5

@onready var cam: Camera2D = $Camera2D
@onready var grid: Node2D = $GridOverlay
@onready var modules_root: Node2D = $Modules
@onready var ui: Control = $HUD/UI
@onready var residents_root: Node2D = $Residents

# Direction unit vectors (N, E, S, W)
const DIR4 := [Vector2i(0,-1), Vector2i(1,0), Vector2i(0,1), Vector2i(-1,0)]

var credits: int
var is_panning := false
var pan_origin_screen := Vector2.ZERO
var cam_origin := Vector2.ZERO

var hall_cells: Dictionary = {}                 # cell(Vector2i)->true
var upkeep_per_resident: int = 1
var tick_interval_s: float = 2.0
var _tick_timer: Timer

# cell(Vector2i) -> {id:String, node:Node2D, type:String, rot:int}
var occupied: Dictionary = {}

var defs := BuildDefs.all()
var current_id := "HALL"
var current_rot := 0               # 0,1,2,3 = 0°,90°,180°,270°
var NONE := "NONE"

var ghost: Node2D = GhostPreview.new()

var pending_erase_cell: Vector2i = Vector2i(-1, -1)

var dock_records: Array = []  # each: {node:Node2D, origin:Vector2i, size:Vector2i, dir:int}
var dock_state := {}          # node -> {"timer": Timer, "busy": bool}

# -- Setup & Main Loop ---------------------------------------------------
# Initializes camera limits, connects UI signals and spawns starting entities.
func _ready() -> void:
	# grid & camera
	grid.set("cell_size", cell_size)
	grid.set("cols", cols)
	grid.set("rows", rows)
	if grid.has_method("refresh"): grid.call("refresh")

	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = cols * cell_size
	cam.limit_bottom = rows * cell_size
	cam.position = Vector2(cols * cell_size, rows * cell_size) * 0.5

	randomize()

	ui.connect("save_pressed", func(): save_game())
	ui.connect("load_pressed", func(): load_game())
	ui.connect("upgrade_pressed", func(n: Node): _upgrade_module(n))

	credits = starting_credits
	ui.call("set_credits", credits)
	ui.connect("choose_blueprint", _on_choose_blueprint)

	refresh_hall_visuals()

	ui.connect("confirm_erase_ok", func():
		if pending_erase_cell != Vector2i(-1, -1):
			erase_at(pending_erase_cell)
			pending_erase_cell = Vector2i(-1, -1)
	)
	add_child(ghost)
	_update_ghost_def()

	_start_timers()
	# spawn_resident()   # starting resident (comment out to start empty)

# Positions the ghost preview and checks if placement is valid each frame.
func _process(_dt: float) -> void:
	if not ghost.visible:
		return
	var mouse := get_global_mouse_position()
	var origin_cell := world_to_cell(mouse)

	var size := rotated_size(current_id, current_rot)
	var top_left := cell_to_world_top_left(origin_cell)
	var size_px := Vector2(size.x * cell_size, size.y * cell_size)
	ghost.position = top_left + size_px * 0.5

	var ok := (can_delete_at(origin_cell) if current_id == "ERASE" else can_place_at(origin_cell, current_id, current_rot))
	ghost.call("set_valid", ok)

# Handles blueprint selection from the UI.
func _on_choose_blueprint(id: String) -> void:
	# toggle off if clicking the same tool again
	if current_id == id:
		current_id = NONE
	else:
		current_id = id
	# update ghost (or hide if NONE)
	_update_ghost_def()

# Updates the ghost preview to match the currently selected blueprint.
func _update_ghost_def() -> void:
	if current_id == NONE or current_id == "ERASE":
		ghost.visible = false
		return
	ghost.visible = true
	var size := rotated_size(current_id, current_rot)
	var doors := rotated_doors(current_id, current_rot)
	ghost.call("configure", cell_size, size, doors)

# -- Helpers -------------------------------------------------------------
# Converts a world position to the grid cell index.
func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(floor(world_pos.x / cell_size), floor(world_pos.y / cell_size))

# Returns the world-space center of a grid cell.
func cell_to_world_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * cell_size + cell_size * 0.5, cell.y * cell_size + cell_size * 0.5)

# Returns the world-space top-left corner of a grid cell.
func cell_to_world_top_left(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * cell_size, cell.y * cell_size)

# Determines if a rectangle of cells fits within the map bounds.
func in_bounds_rect(origin: Vector2i, size: Vector2i) -> bool:
	return origin.x >= 0 and origin.y >= 0 and (origin.x + size.x) <= cols and (origin.y + size.y) <= rows

# Generates an array of all cells covered by a rectangle.
func cells_for(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(size.y):
		for x in range(size.x):
			out.append(origin + Vector2i(x, y))
	return out

# True if any modules have been placed on the map.
func has_any_modules() -> bool:
	return occupied.size() > 0

# Checks if the given cell touches an existing hall module.
func any_neighbor_hall(cell: Vector2i) -> bool:
	for d in DIR4:
		var n: Vector2i = cell + d
		if occupied.has(n) and occupied[n]["type"] == "hall":
			return true
	return false

# Creates and starts the repeating economy tick timer.
func _start_timers() -> void:
	_tick_timer = Timer.new()
	_tick_timer.wait_time = tick_interval_s
	_tick_timer.autostart = true
	_tick_timer.timeout.connect(_on_economy_tick)
	add_child(_tick_timer)

# Determines if a placement rectangle lies on a specified map edge.
func is_on_map_edge_rect(origin: Vector2i, size: Vector2i, space_side: int) -> bool:
	# space_side: 0=N,1=E,2=S,3=W — the side that must touch the map boundary
	match space_side:
		0: return origin.y == 0
		1: return origin.x + size.x == cols
		2: return origin.y + size.y == rows
		3: return origin.x == 0
	return false

# ---------- Docks & Ships ----------
# Returns the map side a dock faces based on rotation.
func dock_space_side(rot: int) -> int:
	return rot % 4

# Creates a timer for a dock to periodically attempt spawning ships.
func _start_dock_timer(dock_node: Node2D) -> void:
	var t := Timer.new()
	t.one_shot = true
	t.autostart = false
	add_child(t)
	dock_state[dock_node] = {"timer": t, "busy": false}
	_arm_dock_timer(dock_node)  # first arm

# Arms or re-arms a dock's spawn timer.
func _arm_dock_timer(dock_node: Node2D) -> void:
	if not is_instance_valid(dock_node): return
	if not dock_state.has(dock_node): return
	var t: Timer = dock_state[dock_node]["timer"]
	# random spawn window per dock
	t.wait_time = 5.0 + randf() * 6.0  # 5–11s
	# reconnect timeout cleanly
	for c in t.timeout.get_connections():
		t.timeout.disconnect(c.callable)
	t.timeout.connect(func():
		# if a ship is already on this pad, just re-arm later
		if dock_state[dock_node]["busy"]:
			_arm_dock_timer(dock_node)
		else:
			_spawn_ship_for_dock(dock_node)
	)
	t.start()

# Spawns a ship that approaches the given dock and handles arrival/departure.
func _spawn_ship_for_dock(dock_node: Node2D) -> void:
	if not is_instance_valid(dock_node):
		return
	var approach_dir: int = int(dock_node.get("approach_dir"))
	var dock_pos: Vector2 = dock_node.global_position

	# mark pad busy
	if dock_state.has(dock_node):
		dock_state[dock_node]["busy"] = true

	# spawn off-screen on approach axis
	var margin: float = float(max(cols, rows) * cell_size) * 0.6
	var off: Vector2 = Vector2.ZERO
	match approach_dir:
		0: off = Vector2(0, -margin)
		1: off = Vector2(margin, 0)
		2: off = Vector2(0,  margin)
		3: off = Vector2(-margin, 0)

	var spawn: Vector2 = dock_pos + off
	var depart: Vector2 = spawn

	var ship: Node2D = ShipScene.instantiate()
	ship.global_position = spawn
	ship.set_route(dock_pos, depart)   # expected API on Ship.gd
	add_child(ship)
	ship.connect("departed", func():
		if dock_state.has(dock_node):
			dock_state[dock_node]["busy"] = false
			_arm_dock_timer(dock_node)
	)

	# when ship arrives: spawn a visitor, make them do a shop loop, then ask ship to depart
	ship.connect("arrived", func():
		var start_hall := dock_entry_hall_cell(dock_node)
		if start_hall.x == -999:
			ship.request_depart()
			return

	var shops := shop_entry_points()
	if shops.is_empty():
		ship.request_depart()
		return

	var segments: Array = []
	var prev := start_hall
	for s in shops:
		var seg := compute_path_cells(prev, s["hall"])
		if seg.is_empty():
			ship.request_depart()
			return
		seg.append(s["inside"])
		segments.append(seg)
		prev = s["hall"]
	var back_seg := compute_path_cells(prev, start_hall)
	if back_seg.is_empty():
		ship.request_depart()
		return
	segments.append(back_seg)

		var seg_world: Array = []
		for seg in segments:
			seg_world.append(path_cells_to_world(seg))

		var ch := CharacterScene.instantiate()
		var spawn_world := cell_to_world_center(start_hall)
		ch.call("begin_visit", seg_world, ship, spawn_world)
		add_child(ch)
	)

# Converts a direction index to a 4-way unit vector.
func _dir4(d: int) -> Vector2i:
	match d % 4:
		0: return Vector2i(0, -1)  # N
		1: return Vector2i(1, 0)   # E
		2: return Vector2i(0, 1)   # S
		3: return Vector2i(-1, 0)  # W
	return Vector2i.ZERO

# Returns all grid cells in the straight "air corridor" from the dock's approach face to the map edge.
# Does NOT include the dock's own footprint cells.
func dock_approach_cells(origin: Vector2i, size_cells: Vector2i, approach_dir: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var step := _dir4(approach_dir)
	# iterate along the dock's approach edge and cast a ray outward to the edge
	if approach_dir == 0: # N: cast upward from the row above the top edge
		for x in range(origin.x, origin.x + size_cells.x):
			var c := Vector2i(x, origin.y - 1)
			while c.y >= 0:
				out.append(c)
				c += step
	elif approach_dir == 1: # E
		for y in range(origin.y, origin.y + size_cells.y):
			var c := Vector2i(origin.x + size_cells.x, y)
			while c.x < cols:
				out.append(c)
				c += step
	elif approach_dir == 2: # S
		for x in range(origin.x, origin.x + size_cells.x):
			var c := Vector2i(x, origin.y + size_cells.y)
			while c.y < rows:
				out.append(c)
				c += step
	else: # W
		for y in range(origin.y, origin.y + size_cells.y):
			var c := Vector2i(origin.x - 1, y)
			while c.x >= 0:
				out.append(c)
				c += step
	return out

# Check that the corridor is clear of existing modules (ignores the dock's own footprint).
func is_dock_approach_clear(origin: Vector2i, size_cells: Vector2i, approach_dir: int) -> bool:
	for c in dock_approach_cells(origin, size_cells, approach_dir):
		if occupied.has(c):
			return false
	return true

# Build a set of all protected approach cells for currently-placed docks (used to prevent blocking).
func all_existing_dock_approach_cells() -> Dictionary:
	var blocked := {}
	for rec in dock_records:
		var o: Vector2i = rec["origin"]
		var sz: Vector2i = rec["size"]
		var dir: int = rec["dir"]
		for c in dock_approach_cells(o, sz, dir):
			blocked[c] = true
	return blocked

# Finds a hall cell connected to the dock's internal door.
func dock_entry_hall_cell(dock_node: Node2D) -> Vector2i:
	var rot: int = int(dock_node.get_meta("rot"))
	var origin_dic: Dictionary = (dock_node.get_meta("origin") as Dictionary)
	var origin: Vector2i = Vector2i(int(origin_dic.get("x", 0)), int(origin_dic.get("y", 0)))

	var doors: Array = rotated_doors("DOCK", rot)
	if doors.is_empty():
		return Vector2i(-999, -999)

	var door_local: Vector2i = Vector2i(doors[0])      # inner door (local space)
	var door_cell: Vector2i = origin + door_local      # grid cell of the door

	for n in _neighbors4(door_cell):
		if hall_cells.has(n):
			return n
	return Vector2i(-999, -999)

# ---------- Rotation math ----------
# Returns the size of a module after applying rotation.
func rotated_size(id: String, rot: int) -> Vector2i:
	var base: Vector2i = defs[id].get("size", Vector2i(1,1))
	if defs[id].get("type","") == "tool":
		return base
	return (base if rot % 2 == 0 else Vector2i(base.y, base.x))

# Rotates a local grid point 90 degrees clockwise within a rectangle.
func rotate_point_cw(p: Vector2i, size: Vector2i) -> Vector2i:
	return Vector2i(size.y - 1 - p.y, p.x)

# Rotates a local grid point 90 degrees counter-clockwise within a rectangle.
func rotate_point_ccw(p: Vector2i, size: Vector2i) -> Vector2i:
	return Vector2i(p.y, size.x - 1 - p.x)

# Returns the door positions of a module adjusted for rotation.
func rotated_doors(id: String, rot: int) -> Array:
	var base_size: Vector2i = defs[id].get("size", Vector2i(1,1))
	var doors: Array = defs[id].get("doors", [])
	if defs[id].get("type","") == "tool":
		return []
	var pts: Array[Vector2i] = []
	for d in doors: pts.append(Vector2i(d))

	var s := base_size
	var rpts := pts
	if rot == 1:
		var tmp: Array[Vector2i] = []
		for p in rpts: tmp.append(rotate_point_cw(p, s))
		rpts = tmp; s = Vector2i(s.y, s.x)
	elif rot == 2:
		var tmp2: Array[Vector2i] = []
		for p in rpts: tmp2.append(Vector2i(s.x - 1 - p.x, s.y - 1 - p.y))
		rpts = tmp2
	elif rot == 3:
		var tmp3: Array[Vector2i] = []
		for p in rpts: tmp3.append(rotate_point_ccw(p, s))
		rpts = tmp3; s = Vector2i(s.y, s.x)
	return rpts

# ---------- Placement rules ----------
# Validates whether a module can be placed at a grid origin with rotation.
func can_place_at(origin: Vector2i, id: String, rot: int) -> bool:
	var d: Dictionary = defs[id]
	var size_cells: Vector2i = rotated_size(id, rot)

	# 1) bounds & overlap
	if not in_bounds_rect(origin, size_cells): return false
	for c in cells_for(origin, size_cells):
		if occupied.has(c): return false

	# 2) do not allow blocking any existing dock's approach corridor (halls included)
	var blocked: Dictionary = all_existing_dock_approach_cells()
	for c in cells_for(origin, size_cells):
		if blocked.has(c):
			return false

	# 3) halls
	if d["type"] == "hall":
		if not has_any_modules(): return true
		for c in cells_for(origin, size_cells):
			if any_neighbor_hall(c) or _cell_neighbors_anything(c):
				return true
		return false

	# 4) docks: must touch hall via inner door and have a clear approach
	if d["type"] == "dock":
		var doors := rotated_doors(id, rot)
		var touches_hall := false
		for local in doors:
			if any_neighbor_hall(origin + local):
				touches_hall = true
				break
		if not touches_hall: return false

		var approach_dir := dock_space_side(rot)
		if not is_dock_approach_clear(origin, size_cells, approach_dir): return false
		return true

	# 5) rooms: at least one rotated door must touch a hall
	if not has_any_modules(): return false
	var doors := rotated_doors(id, rot)
	for local in doors:
		if any_neighbor_hall(origin + local):
			return true
	return false

# Returns true if any neighbor cell is occupied by any module.
func _cell_neighbors_anything(cell: Vector2i) -> bool:
	for d in DIR4:
		var n: Vector2i = cell + d
		if occupied.has(n): return true
	return false

# Rebuilds the set of all hall cells from the occupied map.
func _refresh_hall_set() -> void:
	hall_cells.clear()
	for cell in occupied.keys():
		if occupied[cell]["type"] == "hall":
			hall_cells[cell] = true

# Updates hall visuals to show connected edges.
func refresh_hall_visuals() -> void:
	_refresh_hall_set()
	for cell in hall_cells.keys():
		var node: Node2D = occupied[cell]["node"]
		if not is_instance_valid(node): continue
		var m := 0
		if hall_cells.has(cell + Vector2i(0,-1)): m |= 1  # N
		if hall_cells.has(cell + Vector2i(1,0)):  m |= 2  # E
		if hall_cells.has(cell + Vector2i(0,1)):  m |= 4  # S
		if hall_cells.has(cell + Vector2i(-1,0)): m |= 8  # W
		if "set_mask" in node:
			node.set_mask(m)

# ---------- Instantiation (single source of truth) ----------
# Creates a module instance, registers it in the occupied map and returns it.
func _instantiate_register(id: String, origin: Vector2i, rot: int) -> Node2D:
	var d: Dictionary = defs[id]
	var inst: Node2D = d["scene"].instantiate()
	var size: Vector2i = rotated_size(id, rot)
	var top_left: Vector2 = cell_to_world_top_left(origin)
	var size_px: Vector2 = Vector2(size.x * cell_size, size.y * cell_size)
	inst.position = top_left + size_px * 0.5
	inst.set("cell_size", cell_size)
	if "size_cells" in inst:
		inst.size_cells = size

	# core metas
	inst.set_meta("id", id)
	inst.set_meta("origin", {"x": origin.x, "y": origin.y})
	inst.set_meta("rot", rot)

	# sensible defaults if not already present
	if not inst.has_meta("level"):
		inst.set_meta("level", 1)
	if id == "HAB" and not inst.has_meta("beds"):
		inst.set_meta("beds", 2)
	if id == "SHOP" and not inst.has_meta("income"):
		inst.set_meta("income", 6)
	if id == "DOCK" and not inst.has_meta("turnaround"):
		inst.set_meta("turnaround", 1)

	inst.queue_redraw()
	modules_root.add_child(inst)

	for c in cells_for(origin, size):
		occupied[c] = {"id": id, "node": inst, "type": d["type"], "rot": rot}

	if d["type"] == "dock":
		if "approach_dir" in inst:
			inst.approach_dir = dock_space_side(rot)
		dock_records.append({
			"node": inst,
			"origin": origin,
			"size": size,
			"dir": dock_space_side(rot)
		})
		_start_dock_timer(inst)

	return inst

# Attempts to build a module at the given origin.
func place(id: String, origin: Vector2i, rot: int) -> void:
	var d: Dictionary = defs[id]
	if credits < d.get("cost", 0): return
	if not can_place_at(origin, id, rot): return

	credits -= d.get("cost", 0)
	ui.call("set_credits", credits)

	_instantiate_register(id, origin, rot)
	refresh_hall_visuals()
	if id == "HAB" and current_population() == 0:
		spawn_resident()

# Places a module without cost or validation (used when loading saves).
func place_from_save(id: String, origin: Vector2i, rot: int) -> void:
	_instantiate_register(id, origin, rot)
	refresh_hall_visuals()

# ---------- Erase ----------
# Checks if a cell is occupied and can be deleted.
func can_delete_at(cell: Vector2i) -> bool:
	return occupied.has(cell)

# Removes the module occupying the given cell and refunds part of its cost.
func erase_at(cell: Vector2i) -> void:
	if not occupied.has(cell): return
	var node: Node2D = occupied[cell]["node"]
	var id: String = occupied[cell]["id"]
	# collect all cells linked to this node
	var cells: Array[Vector2i] = []
	for k in occupied.keys():
		if occupied[k]["node"] == node:
			cells.append(k)
	for c in cells: occupied.erase(c)
	if is_instance_valid(node): node.queue_free()

	# dock cleanup
	if id == "DOCK":
		for i in range(dock_records.size()-1, -1, -1):
			if dock_records[i]["node"] == node:
				dock_records.remove_at(i)
				break
		if dock_state.has(node):
			var t: Timer = dock_state[node]["timer"]
			if is_instance_valid(t):
				t.stop()
				t.queue_free()
			dock_state.erase(node)

	# refund
	var cost := int(defs.get(id, {}).get("cost", 0))
	credits += int(round(cost * refund_rate))
	ui.call("set_credits", credits)

	refresh_hall_visuals()

# ---------- Input ----------
# Handles build/erase clicks, rotation shortcuts and camera control.
func _unhandled_input(event: InputEvent) -> void:
	# place / erase
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cell := world_to_cell(get_global_mouse_position())

		# 1) ERASE tool
		if current_id == "ERASE":
			if not can_delete_at(cell): return
			if Input.is_key_pressed(KEY_SHIFT):
				erase_at(cell)
			else:
				pending_erase_cell = cell
				ui.call("ask_confirm_erase")
			return

		# 2) BUILD tool selected → place once (unless Shift held)
		if current_id != NONE and defs.has(current_id):
			place(current_id, cell, current_rot)
			if not Input.is_key_pressed(KEY_SHIFT):
				current_id = NONE
				_update_ghost_def()
			return

		# 3) NOTHING selected (inspect mode) → click to inspect / click empty to hide
		if occupied.has(cell):
			var rec: Dictionary = occupied[cell]  # {id,node,type,rot}
			ui.call("show_inspect", rec["id"], rec["node"])
		else:
			ui.call("hide_inspect")
		return

	# rotate (R = CW, Q = CCW)
	if event.is_action_pressed("ui_page_down") or (event is InputEventKey and event.pressed and event.keycode == KEY_R):
		current_rot = (current_rot + 1) % 4
		_update_ghost_def()
	if event.is_action_pressed("ui_page_up") or (event is InputEventKey and event.pressed and event.keycode == KEY_Q):
		current_rot = (current_rot + 3) % 4
		_update_ghost_def()

	# quick toggle eraser
	if event is InputEventKey and event.pressed and event.keycode == KEY_X:
		current_id = ("ERASE" if current_id != "ERASE" else "HALL")
		_update_ghost_def()

	# panning & zoom
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			is_panning = true
			pan_origin_screen = get_viewport().get_mouse_position()
			cam_origin = cam.position
		else:
			is_panning = false

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_by(0.9)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_by(1.1)

	if event is InputEventMouseMotion and is_panning:
		var delta_screen := get_viewport().get_mouse_position() - pan_origin_screen
		cam.position = cam_origin - delta_screen * cam.zoom.x

# Zooms the camera by the given factor with limits.
func _zoom_by(factor: float) -> void:
	var new_zoom := cam.zoom * Vector2(factor, factor)
	new_zoom.x = clamp(new_zoom.x, 0.3, 2.5)
	new_zoom.y = clamp(new_zoom.y, 0.3, 2.5)
	cam.zoom = new_zoom

# ---------- Save/Load ----------
# Serializes current modules and credits to a dictionary for saving.
func serialize_world() -> Dictionary:
	var items: Array = []
	for child in modules_root.get_children():
		if not is_instance_valid(child):
			continue
		if not child.has_meta("id"):
			continue
		var origin_meta := child.get_meta("origin") as Dictionary
		var rot_meta := int(child.get_meta("rot"))
		items.append({
			"id": String(child.get_meta("id")),
			"origin": origin_meta,        # {x:int, y:int}
			"rot": rot_meta
		})
	return {
		"version": 1,
		"cols": cols,
		"rows": rows,
		"cell_size": cell_size,
		"credits": credits,
		"items": items
	}

# Writes the current world state to disk.
func save_game(path: String = "user://save.json") -> void:
	var data: Dictionary = serialize_world()
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
		f.close()

# Clears all placed modules from the world.
func clear_world() -> void:
	for child in modules_root.get_children():
		if is_instance_valid(child):
			child.queue_free()
	occupied.clear()
	refresh_hall_visuals()

# Loads world data from disk and rebuilds modules.
func load_game(path: String = "user://save.json") -> void:
	if not FileAccess.file_exists(path):
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not f:
		return
	var txt: String = f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed as Dictionary

	clear_world()

	credits = int(data.get("credits", starting_credits))
	ui.call("set_credits", credits)

	var items: Array = data.get("items", []) as Array
	for it in items:
		var item: Dictionary = it as Dictionary
		var id: String = String(item.get("id", "HALL"))
		var origin_dic: Dictionary = item.get("origin", {}) as Dictionary
		var ox: int = int(origin_dic.get("x", 0))
		var oy: int = int(origin_dic.get("y", 0))
		var origin: Vector2i = Vector2i(ox, oy)
		var rot: int = int(item.get("rot", 0))
		place_from_save(id, origin, rot)

# ---------- Residents ----------
# Four-way neighbor coordinates helper.
func _neighbors4(c: Vector2i) -> Array[Vector2i]:
	return [Vector2i(c.x+1,c.y), Vector2i(c.x-1,c.y), Vector2i(c.x,c.y+1), Vector2i(c.x,c.y-1)]

# Returns a hall cell adjacent to the provided cell (for room doors).
func adjacent_hall_for(cell: Vector2i) -> Vector2i:
	for n in _neighbors4(cell):
		if hall_cells.has(n):
			return n
	return cell

# Breadth-first search through halls for a path between cells.
func compute_path_cells(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if start == goal:
		return [start]

	var start_in_hall := hall_cells.has(start)
	var goal_in_hall := hall_cells.has(goal)
	var start_hall := (start if start_in_hall else adjacent_hall_for(start))
	var goal_hall := (goal if goal_in_hall else adjacent_hall_for(goal))

	if not hall_cells.has(start_hall) or not hall_cells.has(goal_hall):
		return []

	var frontier: Array[Vector2i] = [start_hall]
	var came: Dictionary = {}
	came[start_hall] = Vector2i(-999, -999)

	var idx := 0
	while idx < frontier.size():
		var cur: Vector2i = frontier[idx]; idx += 1
		if cur == goal_hall: break
		for n in _neighbors4(cur):
			if not hall_cells.has(n): continue
			if came.has(n): continue
			came[n] = cur
			frontier.append(n)
	# reconstruct
	if not came.has(goal_hall):
		return []
	var path: Array[Vector2i] = [goal_hall]
	var p := goal_hall
	while came.has(p) and came[p] != Vector2i(-999, -999):
		p = came[p]
		path.append(p)
	path.reverse()
	if not start_in_hall:
		path.insert(0, start)
	if not goal_in_hall:
		path.append(goal)
	return path

# Converts a list of grid cells to world-space coordinates.
func path_cells_to_world(path_cells: Array[Vector2i]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for c in path_cells:
		out.append(cell_to_world_center(c))
	return out

# Computes a world-space path from a start cell to a goal cell.
func get_path_world(start_cell: Vector2i, goal_cell: Vector2i) -> Array[Vector2]:
	return path_cells_to_world(compute_path_cells(start_cell, goal_cell))

# Picks a random hall cell from existing hall network.
func random_hall() -> Vector2i:
	if hall_cells.is_empty():
		return Vector2i(0, 0)
	var keys := hall_cells.keys()
	return keys[randi() % keys.size()]

# Collects entry points for rooms where residents can wander inside.
func room_entry_points() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for cell in occupied.keys():
		var rec = occupied[cell]
		if rec["type"] != "room":
			continue
		var node: Node = rec["node"]
		if seen.has(node):
			continue
		seen[node] = true
		var origin_dic: Dictionary = node.get_meta("origin")
		var origin: Vector2i = Vector2i(int(origin_dic.get("x", 0)), int(origin_dic.get("y", 0)))
		var rot: int = int(rec["rot"])
		var doors: Array[Vector2i] = rotated_doors(rec["id"], rot)
		if doors.is_empty():
			continue
		var door_local: Vector2i = doors[0]
		var door_cell: Vector2i = origin + door_local
		for n in _neighbors4(door_cell):
			if hall_cells.has(n):
				out.append({"hall": n, "inside": door_cell})
				break
	return out

# Chooses a random hall or room entry for a resident to travel to.
func random_resident_target() -> Dictionary:
	var opts: Array = []
	for cell in hall_cells.keys():
		opts.append({"hall": cell, "inside": cell})
	opts += room_entry_points()
	if opts.is_empty():
		return {"hall": Vector2i(0,0), "inside": Vector2i(0,0)}
	return opts[randi() % opts.size()]

# Returns entry points for all shops: hall cell and inside door cell.
func shop_entry_points() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for cell in occupied.keys():
		var rec = occupied[cell]
		if rec["id"] != "SHOP":
			continue
		var node: Node = rec["node"]
		if seen.has(node):
			continue
		seen[node] = true
		var origin_dic: Dictionary = node.get_meta("origin")
		var origin: Vector2i = Vector2i(int(origin_dic.get("x",0)), int(origin_dic.get("y",0)))
		var rot: int = int(rec["rot"])
		var doors: Array[Vector2i] = rotated_doors("SHOP", rot)
		if doors.is_empty():
			continue
		var door_local: Vector2i = doors[0]
		var door_cell: Vector2i = origin + door_local
		for n in _neighbors4(door_cell):
			if hall_cells.has(n):
			out.append({"hall": n, "inside": door_cell})
			break
	return out

# Returns hall cells adjacent to hab modules for spawning residents.
func hab_adjacent_hall_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen: Dictionary = {}
	for cell in occupied.keys():
		if occupied[cell]["id"] == "HAB":
			var node: Node = occupied[cell]["node"]  # explicit type
			if seen.has(node):
				continue
			seen[node] = true
			# collect one hall cell adjacent to the HAB's door (fallback to any)
			var origin_dic: Dictionary = node.get_meta("origin") as Dictionary
			var origin: Vector2i = Vector2i(int(origin_dic.get("x",0)), int(origin_dic.get("y",0)))
			var rot: int = int(occupied[cell]["rot"])
			var doors: Array[Vector2i] = rotated_doors("HAB", rot)
			var added := false
			if not doors.is_empty():
				var door_cell: Vector2i = origin + doors[0]
				for n in _neighbors4(door_cell):
					if hall_cells.has(n):
						out.append(n)
						added = true
						break
			if not added:
				# fallback: any adjacent hall to any HAB footprint cell
				for n in _neighbors4(cell):
					if hall_cells.has(n):
						out.append(n)
						break
	return out

# Number of resident nodes currently in the scene.
func current_population() -> int:
	return residents_root.get_child_count()

# Total available bed capacity from all hab modules.
func capacity_from_habs() -> int:
	var cap := 0
	var seen: Dictionary = {}
	for v in occupied.values():
		if v["id"] == "HAB":
			var n: Node = v["node"]
			if seen.has(n): continue
			seen[n] = true
			cap += int(n.get_meta("beds", 2))
	return cap

# Sum of income produced by all shops.
func total_shop_income() -> int:
	var inc := 0
	var seen: Dictionary = {}
	for v in occupied.values():
		if v["id"] == "SHOP":
			var n: Node = v["node"]
			if seen.has(n): continue
			seen[n] = true
			inc += int(n.get_meta("income", 6))
	return inc

# Spawns a new resident at a random hab door.
func spawn_resident() -> void:
	var spawns := hab_adjacent_hall_cells()
	if spawns.is_empty():
		return
	var start_cell: Vector2i = spawns[randi() % spawns.size()]
	var inst: Node2D = ResidentScene.instantiate()
	inst.set("cell_size", cell_size)
	inst.call("set_spawn", start_cell, cell_to_world_center(start_cell))
	# wire callbacks
	inst.set("request_new_path_cells", Callable(self, "compute_path_cells"))
	inst.set("random_walk_target", Callable(self, "random_resident_target"))
	residents_root.add_child(inst)

# Applies income and upkeep each economy tick.
func _on_economy_tick() -> void:
	var income := total_shop_income()
	var upkeep := current_population() * upkeep_per_resident
	credits += (income - upkeep)
	ui.call("set_credits", credits)

# Upgrades a module, increasing its stats and cost.
func _upgrade_module(n: Node) -> void:
	var id: String = String(n.get_meta("id", ""))
	var lvl: int = int(n.get_meta("level", 1))

	# simple cost curve
	var cost := 100 * lvl
	if credits < cost:
		return  # TODO: toast "not enough credits"

	credits -= cost
	ui.call("set_credits", credits)

	# apply level & stat bumps
	lvl += 1
	n.set_meta("level", lvl)
	match id:
		"HAB":
			var beds := int(n.get_meta("beds", 2)) + 1
			n.set_meta("beds", beds)
		"SHOP":
			var inc := int(n.get_meta("income", 6)) + 3
			n.set_meta("income", inc)
		"DOCK":
			var turn := int(n.get_meta("turnaround", 1)) + 1
			n.set_meta("turnaround", turn)

	# optional: visual refresh here (change color, add badge, etc.)

	# refresh inspect panel
	ui.call("show_inspect", id, n)

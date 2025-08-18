extends Resource
class_name BuildDefs

static func all() -> Dictionary:
	return {
		"HALL": {
			"scene": preload("res://scenes/modules/Hall.tscn"),
			"cost": 10,
			"size": Vector2i(1,1),
			"doors": [Vector2i(0,0)],
			"type": "hall"
		},
		"HAB": {
			"scene": preload("res://scenes/modules/Hab.tscn"),
			"cost": 120,
			"size": Vector2i(2,2),
			"doors": [Vector2i(1,0), Vector2i(0,1)],
			"type": "room"
		},
		"SHOP": {
			"scene": preload("res://scenes/modules/Hab.tscn"), # temp visual
			"cost": 180,
			"size": Vector2i(3,2),
			"doors": [Vector2i(1,1)],
			"type": "room"
		},
		"DOCK": {
			"scene": preload("res://scenes/modules/Dock.tscn"),
			"cost": 250,
			"size": Vector2i(2,1),           # base (rotated in code)
			"doors": [Vector2i(0,0)],        # inner door at left cell (rotated in code)
			"type": "dock"
		},
		"ERASE": { "type": "tool", "size": Vector2i(1,1), "doors": [] }
	}

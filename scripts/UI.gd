extends Control

@onready var btn_hall:  Button = $BuildBar/HBoxContainer/BtnHall
@onready var btn_hab:   Button = $BuildBar/HBoxContainer/BtnHab
@onready var btn_shop:  Button = $BuildBar/HBoxContainer/BtnShop
@onready var btn_dock:  Button = $BuildBar/HBoxContainer/BtnDock
@onready var btn_erase: Button = $BuildBar/HBoxContainer/BtnErase

@onready var credits_label: Label = $TopBar/HBoxContainer/CreditsLabel
@onready var btn_save: Button = $TopBar/HBoxContainer/BtnSave
@onready var btn_load: Button = $TopBar/HBoxContainer/BtnLoad

# ↓↓↓ Inspect panel nodes — match your scene tree
@onready var inspect_panel: Panel  = $InspectPanel
@onready var inspect_name:  Label  = $InspectPanel/VBoxContainer/ModuleLabel
@onready var inspect_stats: RichTextLabel  = $InspectPanel/VBoxContainer/StatsLabel
@onready var btn_upgrade:   Button = $InspectPanel/VBoxContainer/BtnUpgrade

signal choose_blueprint(id: String)
signal confirm_erase_ok
signal save_pressed
signal load_pressed
signal upgrade_pressed(node: Node)   # new

var _inspected_node: Node = null     # store target for Upgrade

func _ready() -> void:
	btn_hall.pressed.connect(func(): emit_signal("choose_blueprint", "HALL"))
	btn_hab.pressed.connect(func(): emit_signal("choose_blueprint", "HAB"))
	btn_shop.pressed.connect(func(): emit_signal("choose_blueprint", "SHOP"))
	btn_dock.pressed.connect(func(): emit_signal("choose_blueprint", "DOCK"))
	btn_erase.pressed.connect(func(): emit_signal("choose_blueprint", "ERASE"))

	$ConfirmErase.confirmed.connect(func(): emit_signal("confirm_erase_ok"))
	btn_save.pressed.connect(func(): emit_signal("save_pressed"))
	btn_load.pressed.connect(func(): emit_signal("load_pressed"))

	# Upgrade button emits with the currently inspected node
	btn_upgrade.pressed.connect(func():
		if _inspected_node:
			emit_signal("upgrade_pressed", _inspected_node)
	)

	# Make the panel visible and readable
	inspect_panel.visible = false
	inspect_panel.z_index = 50
	inspect_panel.custom_minimum_size = Vector2(260, 140)
	inspect_panel.position = Vector2(16, 56)  # top-left, adjust as you like

	# Make stats wrap and be visible
	inspect_stats.bbcode_enabled = false
	inspect_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspect_stats.custom_minimum_size = Vector2(0, 60)   # give it some height

	# Ensure text is readable on the dark panel
	inspect_name.add_theme_color_override("font_color", Color(1, 1, 1))
	inspect_stats.add_theme_color_override("default_color", Color(1, 1, 1))

	# Add a simple dark background so it's not transparent
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.75)
	sb.border_color = Color(1,1,1,0.2)
	sb.border_width_top = 1
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	inspect_panel.add_theme_stylebox_override("panel", sb)

	# Make stats wrap nicely
	inspect_stats.bbcode_enabled = false
	inspect_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func set_credits(value: int) -> void:
	credits_label.text = "₡ %d" % value

func ask_confirm_erase() -> void:
	$ConfirmErase.popup_centered()

func show_inspect(id: String, node: Node) -> void:
	_inspected_node = node
	inspect_panel.visible = true
	inspect_name.visible = true
	inspect_stats.visible = true

	inspect_name.text = id

	var lvl := int(node.get_meta("level", 1))
	var text := "Level: %d" % lvl
	if id == "HAB":
		text += "\nBeds: %d" % int(node.get_meta("beds", 2))
	elif id == "SHOP":
		text += "\nIncome/tick: %d" % int(node.get_meta("income", 6))
	elif id == "DOCK":
		text += "\nTurnaround: %d" % int(node.get_meta("turnaround", 1))

	inspect_stats.text = text
	# print("INSPECT:", id, " -> ", text)  # uncomment once to confirm it's being set

func hide_inspect() -> void:
	inspect_panel.visible = false
	_inspected_node = null

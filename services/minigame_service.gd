class_name MinigameService
extends Service
## Hosts every minigame as a tool in a tool tray. Each tool opens in its own window.

## Tool tray listing the minigames.
@export var tray: Control
## Container the tray spawns tool windows into.
@export var window_layer: Control
## Display name of the minigame to open on startup. Empty = none.
@export var startup_minigame := ""
@export var window_size := Vector2(1000.0, 580.0)
@export var window_position := Vector2(76.0, 30.0)


## Called by MainSc after all services are loaded.
func bind_nodes() -> void:
	# Spawned windows use anchor-based sizes from their scene; give them a usable size instead.
	window_layer.child_entered_tree.connect(_on_window_spawned)
	if not startup_minigame.is_empty():
		open_minigame(startup_minigame)


## Opens the window for the minigame with this display name (e.g. "Rhythm").
func open_minigame(display_name: String) -> void:
	# tool_buttons is a Dictionary[ToolDefinition, CheckBox] on the tray's script.
	var buttons: Dictionary = tray.get("tool_buttons")
	for tool: ToolDefinition in buttons:
		if tool.display_name == display_name:
			(buttons[tool] as BaseButton).button_pressed = true
			return
	push_warning("MinigameService: no minigame named '%s'" % display_name)


func _on_window_spawned(window: Node) -> void:
	_size_window.call_deferred(window)


func _size_window(window: Control) -> void:
	window.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_KEEP_SIZE)
	window.size = window_size
	window.position = window_position

class_name MinigameService
extends Service
## Hosts every minigame as a tool in a tool tray. Each tool opens in its own window.
##
## A minigame scene reports its results with two signals, both optional:
##   solved  - the player succeeded
##   failed  - the player failed
## and says which kind of data a success produces with an exported `data_category` string.
## This service forwards those as its own signals, so other services never touch the windows.

## A minigame window opened (true) or the last open one closed (false).
signal minigame_active_changed(active: bool)
## A minigame was completed. `data_category` is the minigame's own `data_category`.
signal minigame_solved(data_category: String)
## A minigame was failed.
signal minigame_failed(minigame_name: String)

## Tool tray listing the minigames.
@export var tray: Control
## Container the tray spawns tool windows into.
@export var window_layer: Control
## Display name of the minigame to open on startup. Empty = none.
@export var startup_minigame := ""
@export var window_size := Vector2(956.0, 560.0)
@export var window_position := Vector2(12.0, 46.0)

var _minigame_active := false


## Called by MainSc after all services are loaded.
func bind_nodes() -> void:
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


func is_minigame_active() -> bool:
	return _minigame_active


func _on_window_spawned(window: Node) -> void:
	_size_window.call_deferred(window)
	(window as Control).visibility_changed.connect(_refresh_active)
	_refresh_active.call_deferred()

	# The window fills in its minigame a moment after it is created.
	var content_root := window.get_node_or_null("Content/Body/ContentRoot")
	if content_root:
		content_root.child_entered_tree.connect(_on_minigame_added)


func _size_window(window: Control) -> void:
	# Spawned windows use anchor-based sizes from their scene; give them a usable size instead.
	window.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_KEEP_SIZE)
	window.size = window_size
	window.position = window_position


func _on_minigame_added(minigame: Node) -> void:
	if minigame.has_signal("solved"):
		minigame.connect("solved", _on_minigame_solved.bind(minigame))
	if minigame.has_signal("failed"):
		minigame.connect("failed", _on_minigame_failed.bind(minigame))


func _on_minigame_solved(minigame: Node) -> void:
	var category = minigame.get("data_category")
	if category is String and not (category as String).is_empty():
		minigame_solved.emit(category)
	else:
		push_warning("MinigameService: '%s' has no data_category" % minigame.name)


func _on_minigame_failed(minigame: Node) -> void:
	minigame_failed.emit(String(minigame.name))


## True while at least one minigame window is open.
func _refresh_active() -> void:
	var active := false
	for window in window_layer.get_children():
		if window is Control and (window as Control).visible:
			active = true
			break
	if active != _minigame_active:
		_minigame_active = active
		minigame_active_changed.emit(active)

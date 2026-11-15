class_name MinigameService
extends Service
## Hosts the tools (Mission Planner, Mission Control) in a tool tray. Each tool opens in its own window.
##
## A tool scene talks to the rest of the game through optional signals and properties:
##   solved / failed       - the player succeeded / failed at a minigame
##   data_category         - which kind of data a success produces
##   playing               - true while minigames are running (drives the faster clock and drain)
##   playing_changed       - emitted when `playing` changes
##   launch_requested      - the Mission Planner asks to launch (carries the mission settings)
##   configure(params)     - called when the tool opens, with the current mission settings
## This service forwards those as its own signals, so other services never touch the windows.

## Minigames started playing (true) or stopped (false). With the Mission Control tool this is
## true only while a session is running, not just while its window is open.
signal minigame_active_changed(active: bool)
## A minigame was completed. `data_category` is the minigame's own `data_category`.
signal minigame_solved(data_category: String)
## A minigame was failed.
signal minigame_failed(minigame_name: String)
## The Mission Planner's launch button was pressed. `params` holds the player's choices.
signal tool_launch_requested(params: Dictionary)

## Tool tray listing the tools.
@export var tray: Control
## Container the tray spawns tool windows into.
@export var window_layer: Control
## Display name of the tool to open on startup. Empty = none.
@export var startup_minigame := ""
@export var window_size := Vector2(956.0, 560.0)
@export var window_position := Vector2(12.0, 46.0)

var _minigame_active := false
var _all_tools: Array[ToolDefinition] = []
var _mission_params: Dictionary = {}


## Called by MainSc after all services are loaded.
func bind_nodes() -> void:
	var data: TrayDefinition = tray.get("tools_data")
	if data:
		_all_tools.assign(data.tools)
	window_layer.child_entered_tree.connect(_on_window_spawned)
	if not startup_minigame.is_empty():
		open_minigame(startup_minigame)


## Opens the window for the tool with this display name (e.g. "Mission Control").
func open_minigame(display_name: String) -> void:
	# tool_buttons is a Dictionary[ToolDefinition, CheckBox] on the tray's script.
	var buttons: Dictionary = tray.get("tool_buttons")
	for tool: ToolDefinition in buttons:
		if tool.display_name == display_name:
			(buttons[tool] as BaseButton).button_pressed = true
			return
	push_warning("MinigameService: no tool named '%s'" % display_name)


## Shows only the named tools in the tray and closes every open window, so any other
## tool disappears from the player. An empty list removes all tools.
func set_available_tools(names: Array) -> void:
	for window in window_layer.get_children():
		window_layer.remove_child(window)
		window.queue_free()

	var source: TrayDefinition = tray.get("tools_data")
	var data := TrayDefinition.new()
	if source:
		data.display_name = source.display_name
		data.description = source.description
	for tool in _all_tools:
		if tool.display_name in names:
			data.tools.append(tool)
	tray.set("tools_data", data)
	_refresh_active()


## Settings handed to each tool when it opens (see `configure` above).
func set_mission_params(params: Dictionary) -> void:
	_mission_params = params


func is_minigame_active() -> bool:
	return _minigame_active


func _on_window_spawned(window: Node) -> void:
	_size_window.call_deferred(window)
	(window as Control).visibility_changed.connect(_refresh_active)
	_refresh_active.call_deferred()

	# The window fills in its tool a moment after it is created.
	var content_root := window.get_node_or_null("Content/Body/ContentRoot")
	if content_root:
		content_root.child_entered_tree.connect(_on_minigame_added)


func _size_window(window: Control) -> void:
	if not is_instance_valid(window) or not window.is_inside_tree():
		return
	# Spawned windows use anchor-based sizes from their scene; give them a usable size instead.
	window.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_KEEP_SIZE)
	window.size = window_size
	window.position = window_position


func _on_minigame_added(minigame: Node) -> void:
	# This runs before the tool's own _ready, so configure() can set it up first.
	if minigame.has_method("configure"):
		minigame.call("configure", _mission_params)
	if minigame.has_signal("solved"):
		minigame.connect("solved", _on_minigame_solved.bind(minigame))
	if minigame.has_signal("failed"):
		minigame.connect("failed", _on_minigame_failed.bind(minigame))
	if minigame.has_signal("launch_requested"):
		minigame.connect("launch_requested", tool_launch_requested.emit)
	# Tools with a start/stop session (like Mission Control) say when they are playing.
	if minigame.has_signal("playing_changed"):
		minigame.connect("playing_changed", _refresh_active.unbind(1))
	_refresh_active.call_deferred()


func _on_minigame_solved(minigame: Node) -> void:
	var category = minigame.get("data_category")
	if category is String and not (category as String).is_empty():
		minigame_solved.emit(category)
	else:
		push_warning("MinigameService: '%s' has no data_category" % minigame.name)


func _on_minigame_failed(minigame: Node) -> void:
	minigame_failed.emit(String(minigame.name))


## True while at least one visible window has a tool that is playing.
func _refresh_active() -> void:
	var active := false
	for window in window_layer.get_children():
		if window is Control and (window as Control).visible and _is_playing(window):
			active = true
			break
	if active != _minigame_active:
		_minigame_active = active
		minigame_active_changed.emit(active)


## A window counts as playing unless its content has a `playing` flag that is false.
func _is_playing(window: Control) -> bool:
	var content_root := window.get_node_or_null("Content/Body/ContentRoot")
	if content_root == null or content_root.get_child_count() == 0:
		return false
	var playing: Variant = content_root.get_child(0).get("playing")
	return playing == null or bool(playing)

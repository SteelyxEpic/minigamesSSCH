@tool
extends Control

var stuff: Array = [1, 2, 3]

@export var refresh_tray: bool = false:
	set(value):
		refresh_tray = value
		if value:
			_on_data_changed()
			refresh_tray = false

## TrayDefinition resource
@export var tools_data: TrayDefinition:
	set(value):
		if tools_data and tools_data.changed.is_connected(_on_data_changed):
			tools_data.changed.disconnect(_on_data_changed)

		tools_data = value

		if tools_data and not tools_data.changed.is_connected(_on_data_changed):
			tools_data.changed.connect(_on_data_changed)

		_on_data_changed()

## The scene of the window frame we are spawning
@export var window_scene: PackedScene

## Where the windows should be spawned (e.g., a CanvasLayer)
@export var spawn_parent: Node

# Keeps track of spawned windows
var active_windows: Dictionary = {}

# Maps ToolDefinition to its CheckButton so we can search the data
var tool_buttons: Dictionary = {} 

@onready var grid_container: GridContainer = $Content/Body/ContentRoot/GridContainer
@onready var search_bar: LineEdit = $Foot/SearchBar
@onready var tray_button: BaseButton = $Head/Title/TrayButton

# Animation variables
var is_tray_open: bool = true
var slide_tween: Tween


func _ready() -> void:
	if tools_data and not tools_data.changed.is_connected(_on_data_changed):
		tools_data.changed.connect(_on_data_changed)
	
	if search_bar and not search_bar.text_changed.is_connected(_on_search_bar_text_changed):
		search_bar.text_changed.connect(_on_search_bar_text_changed)
	
	if tray_button and not tray_button.toggled.is_connected(_on_tray_button_toggled):
		tray_button.toggled.connect(_on_tray_button_toggled)
	
	_on_data_changed()

func _on_data_changed() -> void:
	
	if not is_node_ready():
		await ready
	
	if not grid_container:
		return
	
	var title_label = get_node_or_null("Head/Title/TrayButton")
	var desc_label = get_node_or_null("Content/Desc")
	
	if title_label and desc_label:
		if not tools_data:
			title_label.text = "Empty Tool Tray"
			desc_label.text = ""
		else:
			title_label.text = tools_data.display_name
			desc_label.text = tools_data.description
	
	#clear existing buttons from the GridContainer
	for child in grid_container.get_children():
		child.queue_free()
	
	active_windows.clear()
	tool_buttons.clear()
	
	#if no tray data, stop here (leaves it empty)
	if not tools_data:
		return
	
	#create buttons for each tool inside the GridContainer
	for tool in tools_data.tools:
		var btn = CheckBox.new()
		btn.text = tool.display_name
		btn.tooltip_text = tool.display_name
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		btn.toggled.connect(_on_tool_toggled.bind(tool, btn))
		
		grid_container.add_child(btn)
		
		tool_buttons[tool] = btn 

func _on_tool_toggled(is_pressed: bool, tool: ToolDefinition, btn: BaseButton) -> void:
	if not window_scene or not spawn_parent:
		push_error("UToolTray: window_scene or spawn_parent is not set!")
		return
	
	if is_pressed:
		# OPEN / SHOW WINDOW
		if not active_windows.has(tool):
			var new_window = window_scene.instantiate()
			new_window.tool_data = tool
			spawn_parent.add_child(new_window)
			active_windows[tool] = new_window
			
			# Sync the window's visibility back to this button
			if not new_window.visibility_changed.is_connected(_on_window_visibility_changed):
				new_window.visibility_changed.connect(_on_window_visibility_changed.bind(new_window, btn))
		else:
			active_windows[tool].visible = true
	else:
		# HIDE WINDOW
		if active_windows.has(tool):
			active_windows[tool].visible = false

func _on_window_visibility_changed(window: Control, btn: BaseButton) -> void:
	
	# Prevent infinite loops by checking state
	var close_button = window.get_node_or_null("Content/Head/Title/HBoxContainer/VisiButton")
	
	if btn.button_pressed != window.visible:
		btn.button_pressed = window.visible
	
	if not close_button :
		return
	if close_button.button_pressed != window.visible :
		close_button.button_pressed = window.visible


func _on_search_bar_text_changed(new_text: String) -> void:
	var search_text = new_text.to_lower()
	
	# If search is empty, show everything
	if search_text.is_empty():
		for btn in tool_buttons.values():
			btn.visible = true
		return

	# Loop through our dictionary of tools and buttons
	for tool in tool_buttons:
		var btn = tool_buttons[tool]
		var is_match = false
		
		# Check Display Name
		if tool.display_name.to_lower().contains(search_text):
			is_match = true
			
		# Check Keywords (if name didn't match)
		if not is_match:
			for keyword in tool.keywords:
				if keyword.to_lower().contains(search_text):
					is_match = true
					break # Stop checking keywords once we find a match
					
		# Show or hide the button based on the result
		btn.visible = is_match

func _on_tray_button_toggled(is_pressed: bool) -> void:
	is_tray_open = is_pressed
	animate_slide()

func animate_slide() -> void:
	# Kill any existing animation to prevent glitches if clicked rapidly
	if slide_tween and slide_tween.is_valid():
		slide_tween.kill()
	
	slide_tween = create_tween()
	
	# Set animation style (Smooth ease in/out)
	slide_tween.set_ease(Tween.EASE_IN_OUT)
	slide_tween.set_trans(Tween.TRANS_SINE)
	
	# Calculate target Y position
	var target_y: float = 0.0
	
	if not is_tray_open:
		# Slide completely off the top of the screen
		target_y = -size.y 
		
	# Animate the 'position:y' property over 0.3 seconds
	slide_tween.tween_property(self, "position:y", target_y, 0.3)

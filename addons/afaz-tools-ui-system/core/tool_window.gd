@tool
extends Control

@export var refresh_window: bool = false:
	set(value):
		if value:
			_on_data_changed()
			call_deferred("set", "force_refresh", false)

## ToolDefinition resource
@export var tool_data: ToolDefinition:
	set(value):
		if tool_data and tool_data.changed.is_connected(_on_data_changed):
			tool_data.changed.disconnect(_on_data_changed)
		
		tool_data = value
		
		if tool_data:
			tool_data.changed.connect(_on_data_changed)
		
		_on_data_changed()

## The scene of the content we are spawning for the tool
var contentScene: PackedScene:
	set(value):
		if contentScene == value: 
			return
			
		contentScene = value
		_update_content()

@onready var head_bar: Control = $Content/Head
@onready var content_root: Control = $Content/Body/ContentRoot
@onready var visi_button: CheckButton = $Content/Head/Title/HBoxContainer/VisiButton

var is_dragging = false
var is_resizing = false
var resize_dir = 0 # Bitmask for current resize direction

# Constraints for resizing and clamping
const MIN_WINDOW_SIZE = Vector2(200, 150)
const MIN_ON_SCREEN = 50.0 # Pixels that must remain visible on screen
const RESIZE_MARGIN = 8.0 # Pixels from the edge to trigger resize

# Direction bitmasks
const DIR_NONE = 0
const DIR_LEFT = 1
const DIR_RIGHT = 2
const DIR_TOP = 4
const DIR_BOTTOM = 8

func _ready():
	if head_bar:
		head_bar.gui_input.connect(_on_title_bar_gui_input)
	if visi_button:
		visi_button.toggled.connect(_on_visi_button_toggled)
		visi_button.button_pressed = true # Start as visible/checked
	
	# Connect the root node's input to handle edge resizing
	gui_input.connect(_on_root_gui_input)
	
	# Enforce minimum size so it can't be shrunk to nothing
	custom_minimum_size = MIN_WINDOW_SIZE
	
	if tool_data and is_inside_tree():
		_on_data_changed()

func _on_data_changed():
	
	if not is_node_ready():
		await ready
		
	var title_label = get_node_or_null("Content/Head/Title")
	
	if title_label:
		if not tool_data:
			title_label.text = "Empty Tool"
			# CRITICAL If tool_data is cleared, we must set contentScene to null 
			# to trigger _update_content() and clear the old ui
			if contentScene != null:
				contentScene = null
		else:
			title_label.text = tool_data.display_name
			
			if contentScene != tool_data.scene:
				contentScene = tool_data.scene

func _update_content():
	if not is_node_ready():
		await ready
		
	if not content_root:
		return
	
	for child in content_root.get_children():
		content_root.remove_child(child)
		child.queue_free()
	
	if contentScene:
		var content_instance = contentScene.instantiate()
		content_root.add_child(content_instance)
		
		var scroll_body = content_root.get_parent()
		if scroll_body:
			scroll_body.queue_sort()
			# TODO I should be using minimum_size_changed() somehow but I'll
			# do that later to prevent the smoothscroll plugin error

# --- DRAGGING ---

func _on_title_bar_gui_input(event):
	# mouse button press/release
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = event.pressed
			
			# bring to front
			if is_dragging and get_parent():
				get_parent().move_child(self, get_parent().get_child_count() - 1)
	
	# mouse movement
	elif event is InputEventMouseMotion:
		if is_dragging:
			position += event.relative
			_clamp_to_screen()

# --- WINDOWS-STYLE EDGE RESIZING ---

func _on_root_gui_input(event):
	# Ignore if we are currently dragging the title bar
	if is_dragging:
		return

	if event is InputEventMouseMotion:
		var dir = _get_resize_dir(event.position)
		_update_cursor(dir)
		
		if is_resizing:
			_perform_resize(event.relative, resize_dir)
			
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var dir = _get_resize_dir(event.position)
			if event.pressed and dir != DIR_NONE:
				is_resizing = true
				resize_dir = dir
				# bring to front
				if get_parent():
					get_parent().move_child(self, get_parent().get_child_count() - 1)
			elif not event.pressed:
				is_resizing = false
				resize_dir = DIR_NONE

func _get_resize_dir(pos: Vector2) -> int:
	var dir = DIR_NONE
	if pos.x < RESIZE_MARGIN: 
		dir |= DIR_LEFT
	elif pos.x > size.x - RESIZE_MARGIN: 
		dir |= DIR_RIGHT
		
	if pos.y < RESIZE_MARGIN: 
		dir |= DIR_TOP
	elif pos.y > size.y - RESIZE_MARGIN: 
		dir |= DIR_BOTTOM
		
	return dir

func _update_cursor(dir: int):
	if dir == DIR_LEFT or dir == DIR_RIGHT: 
		mouse_default_cursor_shape = Control.CURSOR_HSIZE
	elif dir == DIR_TOP or dir == DIR_BOTTOM: 
		mouse_default_cursor_shape = Control.CURSOR_VSIZE
	elif dir == (DIR_LEFT | DIR_TOP) or dir == (DIR_RIGHT | DIR_BOTTOM): 
		mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	elif dir == (DIR_RIGHT | DIR_TOP) or dir == (DIR_LEFT | DIR_BOTTOM): 
		mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
	else: 
		mouse_default_cursor_shape = Control.CURSOR_ARROW

func _perform_resize(relative: Vector2, dir: int):
	var new_size = size
	var new_pos = position

	# Adjust size and position based on which edges are being pulled
	if dir & DIR_RIGHT: 
		new_size.x += relative.x
	if dir & DIR_LEFT:
		new_size.x -= relative.x
		new_pos.x += relative.x # Move position to keep right edge stationary
	if dir & DIR_BOTTOM: 
		new_size.y += relative.y
	if dir & DIR_TOP:
		new_size.y -= relative.y
		new_pos.y += relative.y # Move position to keep bottom edge stationary

	# Enforce minimum size constraints
	if new_size.x < MIN_WINDOW_SIZE.x:
		if dir & DIR_LEFT: 
			new_pos.x -= (MIN_WINDOW_SIZE.x - new_size.x)
		new_size.x = MIN_WINDOW_SIZE.x
	if new_size.y < MIN_WINDOW_SIZE.y:
		if dir & DIR_TOP: 
			new_pos.y -= (MIN_WINDOW_SIZE.y - new_size.y)
		new_size.y = MIN_WINDOW_SIZE.y

	size = new_size
	position = new_pos
	_clamp_to_screen()

# --- UTILITIES ---

func _clamp_to_screen():
	var screen_size = get_viewport_rect().size
	
	# Calculate the boundaries. 
	# We allow the window to go slightly off-screen, but keep MIN_ON_SCREEN pixels visible.
	var min_x = -(size.x - MIN_ON_SCREEN)
	var max_x = screen_size.x - MIN_ON_SCREEN
	
	var min_y = -(size.y - MIN_ON_SCREEN)
	var max_y = screen_size.y - MIN_ON_SCREEN
	
	# Clamp the position
	position.x = clamp(position.x, min_x, max_x)
	position.y = clamp(position.y, min_y, max_y)

func _on_visi_button_toggled(is_pressed: bool) -> void:
	visible = is_pressed

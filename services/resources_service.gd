class_name ResourcesService
extends Service
## Shows the colony's Oxygen, Food and Water as three bars along the top of the screen.

## Emitted whenever a level changes. `level` is 0 to 100.
signal level_changed(resource: String, level: float)
## Emitted when a resource reaches 0.
signal depleted(resource: String)

const MAX_LEVEL := 100.0
const RESOURCES := {
	"Oxygen": Color("7fd4ff"),
	"Food": Color("ffb45a"),
	"Water": Color("5a9bff"),
}

## Level every resource starts at.
@export var start_level := 100.0

@export_group("Drain")
## Turns the slow decrease on or off.
@export var drain_enabled := true
## Percent lost per real second. 100 / rate = seconds until empty.
@export_range(0.0, 5.0, 0.01, "or_greater") var oxygen_drain := 0.25
@export_range(0.0, 5.0, 0.01, "or_greater") var food_drain := 0.15
@export_range(0.0, 5.0, 0.01, "or_greater") var water_drain := 0.2

var _levels: Dictionary = {}  # resource name -> float
var _sliders: Dictionary = {}  # resource name -> HSlider
var _value_labels: Dictionary = {}  # resource name -> Label

@onready var bars: HBoxContainer = $UI/Bars


## Called by MainSc after all services are loaded.
func bind_nodes() -> void:
	for resource_name: String in RESOURCES:
		_add_row(resource_name, RESOURCES[resource_name])
		set_level(resource_name, start_level)


func _process(delta: float) -> void:
	if not drain_enabled:
		return
	for resource_name: String in _levels:
		var level: float = _levels[resource_name]
		if level > 0.0:
			set_level(resource_name, level - get_drain(resource_name) * delta)


## Percent lost per second by this resource.
func get_drain(resource_name: String) -> float:
	match resource_name:
		"Oxygen":
			return oxygen_drain
		"Food":
			return food_drain
		"Water":
			return water_drain
	return 0.0


func get_level(resource_name: String) -> float:
	return _levels.get(resource_name, 0.0)


func set_level(resource_name: String, level: float) -> void:
	if not _sliders.has(resource_name):
		push_warning("ResourcesService: unknown resource '%s'" % resource_name)
		return
	level = clampf(level, 0.0, MAX_LEVEL)
	_levels[resource_name] = level
	(_sliders[resource_name] as HSlider).value = level
	(_value_labels[resource_name] as Label).text = "%d%%" % int(round(level))
	level_changed.emit(resource_name, level)
	if level <= 0.0:
		depleted.emit(resource_name)


func add_level(resource_name: String, amount: float) -> void:
	set_level(resource_name, get_level(resource_name) + amount)


func _add_row(resource_name: String, color: Color) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)

	var name_label := Label.new()
	name_label.text = resource_name
	name_label.custom_minimum_size = Vector2(54.0, 0.0)
	name_label.add_theme_font_size_override("font_size", 14)

	# A read-only gauge: it shows the level but ignores the mouse and keyboard.
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = MAX_LEVEL
	slider.step = 0.1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(90.0, 0.0)
	slider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slider.focus_mode = Control.FOCUS_NONE
	slider.self_modulate = color
	# Hide the draggable knob so it reads as a plain bar.
	var no_knob := ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))
	for icon_name in ["grabber", "grabber_highlight", "grabber_disabled"]:
		slider.add_theme_icon_override(icon_name, no_knob)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(44.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 14)

	row.add_child(name_label)
	row.add_child(slider)
	row.add_child(value_label)
	bars.add_child(row)

	_sliders[resource_name] = slider
	_value_labels[resource_name] = value_label

class_name ResourcesService
extends Service
## Shows the colony's Oxygen, Food and Water as three rows of 10 icons along the top of the screen.
## Like Minecraft's hunger bar, each icon goes full -> half -> empty as its resource runs out,
## and the rightmost icon empties first.
##
## Also handles: faster food/water drain during minigames, the oxygen penalty for a failed
## minigame, low-resource warnings, and the screen blur when oxygen is low.

## Emitted whenever a level changes. `level` is 0 to 100.
signal level_changed(resource: String, level: float)
## Emitted when a resource reaches 0.
signal depleted(resource: String)
## Emitted when a low-resource warning appears (`active` true) or goes away (false).
signal warning_changed(resource: String, active: bool)

const MAX_LEVEL := 100.0
const ICON_COUNT := 10
const POINTS_PER_ICON := MAX_LEVEL / ICON_COUNT
## Width and height of one frame in each icon sheet.
const FRAME_SIZE := 24
const FRAME_FULL := 0
const FRAME_HALF := 1
const FRAME_EMPTY := 2
## Each sheet is 3 frames side by side: full, half, empty.
const RESOURCES := {
	"Oxygen": preload("res://oxygen_icon.png"),
	"Food": preload("res://food_icon.asperite.png"),
	"Water": preload("res://water_icon.png"),
}
## Text shown when the player hovers over each row.
const TOOLTIPS := {
	"Oxygen": "Oxygen",
	"Food": "Hunger",
	"Water": "Thirst",
}
## Text shown next to a warning symbol.
const WARNING_TEXT := {
	"Oxygen": "LOW OXYGEN",
	"Food": "HUNGRY",
	"Water": "THIRSTY",
}
const WARNING_COLOR := Color("ff4a4a")
## Resources that drain faster while a minigame is open.
const FASTER_IN_MINIGAMES := ["Food", "Water"]

## Level every resource starts at.
@export var start_level := 100.0

@export_group("Drain")
## Turns the slow decrease on or off.
@export var drain_enabled := true
## Percent lost per real second. 100 / rate = seconds until empty.
@export_range(0.0, 5.0, 0.01, "or_greater") var oxygen_drain := 0.25
@export_range(0.0, 5.0, 0.01, "or_greater") var food_drain := 0.15
@export_range(0.0, 5.0, 0.01, "or_greater") var water_drain := 0.2
## Food and water drain this many times faster while a minigame is open (1 = no change).
@export_range(1.0, 5.0, 0.05, "or_greater") var minigame_drain_multiplier := 1.75

@export_group("Penalties")
## Oxygen (percent) lost each time a minigame is failed. 0 turns the penalty off.
@export_range(0.0, 50.0, 0.5, "or_greater") var fail_oxygen_penalty := 4.0

@export_group("Warnings")
## A warning appears when a resource drops below this level (percent).
@export_range(0.0, 100.0, 1.0) var warning_threshold := 25.0
## The warning only disappears once the level is this far above the threshold,
## so it doesn't flicker when the level hovers around it.
@export_range(0.0, 20.0, 0.5) var warning_clear_margin := 5.0

@export_group("Oxygen Vision")
## Blur begins below this oxygen level (percent) and reaches full strength at 0.
@export_range(1.0, 100.0, 1.0) var blur_start_level := 40.0
## How fast the blur fades in or out, in full-strength units per second.
@export_range(0.05, 5.0, 0.05, "or_greater") var blur_response := 0.5

var _levels: Dictionary = {}  # resource name -> float
var _icons: Dictionary = {}  # resource name -> Array[TextureRect]
var _percent_labels: Dictionary = {}  # resource name -> Label
var _frames: Dictionary = {}  # resource name -> Array[AtlasTexture] (full, half, empty)
var _warned: Dictionary = {}  # resource name -> bool
var _warning_nodes: Dictionary = {}  # resource name -> Control
var _minigame_active := false
var _blur := 0.0

@onready var bars: HBoxContainer = $UI/Bars
@onready var warnings: HBoxContainer = $UI/Warnings
@onready var blur_rect: ColorRect = $Vision/Blur


## Called by MainSc after all services are loaded.
func bind_nodes() -> void:
	for resource_name: String in RESOURCES:
		_add_row(resource_name, RESOURCES[resource_name])
		_add_warning(resource_name)
		set_level(resource_name, start_level)


func _process(delta: float) -> void:
	if drain_enabled:
		for resource_name: String in _levels:
			var level: float = _levels[resource_name]
			if level > 0.0:
				set_level(resource_name, level - get_drain(resource_name) * delta)

	_update_blur(delta)
	# Gentle pulse so warnings catch the eye.
	warnings.modulate.a = 0.75 + 0.25 * sin(Time.get_ticks_msec() / 1000.0 * 6.0)


## Tells the service whether a minigame is currently open.
func set_minigame_active(active: bool) -> void:
	_minigame_active = active


## Takes oxygen away for one failed minigame. Call once per failure.
func apply_failure_penalty() -> void:
	if fail_oxygen_penalty > 0.0:
		add_level("Oxygen", -fail_oxygen_penalty)


## Percent lost per second by this resource right now.
func get_drain(resource_name: String) -> float:
	var rate := 0.0
	match resource_name:
		"Oxygen":
			rate = oxygen_drain
		"Food":
			rate = food_drain
		"Water":
			rate = water_drain
	if _minigame_active and resource_name in FASTER_IN_MINIGAMES:
		rate *= minigame_drain_multiplier
	return rate


func get_level(resource_name: String) -> float:
	return _levels.get(resource_name, 0.0)


func set_level(resource_name: String, level: float) -> void:
	if not _icons.has(resource_name):
		push_warning("ResourcesService: unknown resource '%s'" % resource_name)
		return
	level = clampf(level, 0.0, MAX_LEVEL)
	_levels[resource_name] = level
	_update_icons(resource_name, level)
	_update_warning(resource_name, level)
	level_changed.emit(resource_name, level)
	if level <= 0.0:
		depleted.emit(resource_name)


func add_level(resource_name: String, amount: float) -> void:
	set_level(resource_name, get_level(resource_name) + amount)


func _update_icons(resource_name: String, level: float) -> void:
	var icons: Array = _icons[resource_name]
	var frames: Array = _frames[resource_name]
	for i in ICON_COUNT:
		# How much of this icon's share of the level is left, 0 to POINTS_PER_ICON.
		var left := clampf(level - i * POINTS_PER_ICON, 0.0, POINTS_PER_ICON)
		var frame := FRAME_EMPTY
		if left > POINTS_PER_ICON * 0.5:
			frame = FRAME_FULL
		elif left > 0.0:
			frame = FRAME_HALF
		(icons[i] as TextureRect).texture = frames[frame]

	# Hovering any icon (or the percentage) shows e.g. "Thirst: 87%".
	var percent := "%d%%" % int(round(level))
	var tooltip := "%s: %s" % [TOOLTIPS[resource_name], percent]
	for icon: TextureRect in icons:
		icon.tooltip_text = tooltip
	var label: Label = _percent_labels[resource_name]
	label.text = percent
	label.tooltip_text = tooltip


func _update_warning(resource_name: String, level: float) -> void:
	var warned: bool = _warned.get(resource_name, false)
	if not warned and level < warning_threshold:
		_set_warning(resource_name, true)
	elif warned and level >= warning_threshold + warning_clear_margin:
		_set_warning(resource_name, false)


func _set_warning(resource_name: String, active: bool) -> void:
	_warned[resource_name] = active
	(_warning_nodes[resource_name] as Control).visible = active
	var label: Label = _percent_labels[resource_name]
	if active:
		label.add_theme_color_override("font_color", WARNING_COLOR)
	else:
		label.remove_theme_color_override("font_color")
	warning_changed.emit(resource_name, active)


## Eases the blur toward a target set by the oxygen level, so it fades in and out smoothly.
func _update_blur(delta: float) -> void:
	# 0 above blur_start_level, rising to 1 at 0 oxygen. Squared so it starts gently
	# and gets much stronger as oxygen becomes critical.
	var severity := clampf((blur_start_level - get_level("Oxygen")) / blur_start_level, 0.0, 1.0)
	_blur = move_toward(_blur, severity * severity, blur_response * delta)

	blur_rect.visible = _blur > 0.002  # skip the full-screen pass when there is no effect
	if blur_rect.visible:
		(blur_rect.material as ShaderMaterial).set_shader_parameter("blur", _blur)


func _add_row(resource_name: String, sheet: Texture2D) -> void:
	var frames: Array[AtlasTexture] = []
	for frame in 3:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(frame * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
		frames.append(atlas)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 1)

	var icons: Array[TextureRect] = []
	for i in ICON_COUNT:
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(FRAME_SIZE, FRAME_SIZE)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # keep the pixel art sharp
		icon.mouse_filter = Control.MOUSE_FILTER_STOP  # must receive the mouse to show its tooltip
		row.add_child(icon)
		icons.append(icon)

	var label := Label.new()
	label.custom_minimum_size = Vector2(38.0, 0.0)
	label.add_theme_font_size_override("font_size", 12)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(label)

	bars.add_child(row)
	_percent_labels[resource_name] = label
	_icons[resource_name] = icons
	_frames[resource_name] = frames


## Builds a hidden warning: red triangle with "!", the resource's icon, and a short word.
func _add_warning(resource_name: String) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.visible = false
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sign_holder := Control.new()
	sign_holder.custom_minimum_size = Vector2(28.0, 26.0)
	sign_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var triangle := Polygon2D.new()
	triangle.polygon = PackedVector2Array([Vector2(14.0, 1.0), Vector2(27.0, 25.0), Vector2(1.0, 25.0)])
	triangle.color = WARNING_COLOR
	sign_holder.add_child(triangle)
	var mark := Label.new()
	mark.text = "!"
	mark.position = Vector2(0.0, 4.0)
	mark.size = Vector2(28.0, 22.0)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.add_theme_font_size_override("font_size", 15)
	mark.add_theme_color_override("font_color", Color.BLACK)
	sign_holder.add_child(mark)
	box.add_child(sign_holder)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(FRAME_SIZE, FRAME_SIZE)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = (_frames[resource_name] as Array)[FRAME_HALF]
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)

	var text := Label.new()
	text.text = WARNING_TEXT[resource_name]
	text.add_theme_font_size_override("font_size", 14)
	text.add_theme_color_override("font_color", WARNING_COLOR)
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(text)

	warnings.add_child(box)
	_warning_nodes[resource_name] = box
	_warned[resource_name] = false

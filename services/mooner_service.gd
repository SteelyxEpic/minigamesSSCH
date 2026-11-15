class_name MoonerService
extends Service
## The mooner mascot in the bottom right corner. While the mouse is over him, a small text box
## sprite follows the pointer, and clicking him starts a conversation using the Dialogue Manager
## add-on. What he says is picked at random from mooner_lines.json.

## Every line he can say, in groups. A group holds single lines, except "dialogue_chains",
## where each entry is a short run of lines said one after another.
const LINES_PATH := "res://mooner_lines.json"
## How likely each group is to be picked when he is clicked (relative weights).
## The rare lines have the lowest chance.
const CATEGORY_WEIGHTS := {
	"idle": 18,
	"space_observations": 14,
	"machinery": 14,
	"essentials": 14,
	"dialogue_chains": 10,
	"mistakes": 8,
	"success": 8,
	"away_messages": 6,
	"fourth_wall": 6,
	"rare": 2,
}
## The title that random chats are built with.
const DIALOGUE_START := "start"
const HOVER_BRIGHTEN := Color(1.2, 1.2, 1.2)
## The text box sits this far below and to the right of the mouse pointer.
const TOOLTIP_OFFSET := Vector2(16.0, 18.0)

var _talking := false
var _hovering := false
var _away := false
var _dialogue_path := ""  # empty = random chat from mooner_lines.json
var _dialogue_title := DIALOGUE_START
var _lines: Dictionary = {}
var _last_first_line := ""

@onready var mooner: AnimatedSprite2D = $UI/Anchor/Mooner
@onready var hit_area: Control = $UI/Anchor/HitArea
@onready var tooltip: TextureRect = $UI/Tooltip


func _ready() -> void:
	_lines = _load_lines()
	hit_area.mouse_entered.connect(_on_hover.bind(true))
	hit_area.mouse_exited.connect(_on_hover.bind(false))
	hit_area.gui_input.connect(_on_hit_area_input)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)


func _process(_delta: float) -> void:
	if not tooltip.visible:
		return
	# Follow the mouse, but stay on screen. The sprite keeps its own square shape (24x24, drawn 2x).
	var mouse := get_viewport().get_mouse_position()
	var screen := get_viewport().get_visible_rect().size
	var drawn_size := tooltip.size * tooltip.scale
	tooltip.position = (mouse + TOOLTIP_OFFSET).clamp(Vector2.ZERO, screen - drawn_size)


## Starts the conversation. Does nothing if he is already talking or away.
func talk() -> void:
	if _talking or _away:
		return
	var dialogue: DialogueResource
	if _dialogue_path.is_empty():
		dialogue = _random_chat()
	else:
		dialogue = load(_dialogue_path) as DialogueResource
	if dialogue == null:
		push_warning("MoonerService: he has nothing to say (%s)" % _dialogue_path)
		return
	_talking = true
	_update_tooltip()
	DialogueManager.show_dialogue_balloon(dialogue, _dialogue_title)


## Changes what he says when clicked, e.g. to repeat the advice for a tutorial step.
func set_topic(dialogue_path: String, title: String) -> void:
	_dialogue_path = dialogue_path
	_dialogue_title = title


## Goes back to his normal random chat.
func reset_topic() -> void:
	_dialogue_path = ""
	_dialogue_title = DIALOGUE_START


func _load_lines() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LINES_PATH))
	if parsed is Dictionary:
		return parsed
	push_warning("MoonerService: could not read %s" % LINES_PATH)
	return {}


## Builds a short conversation out of a random group of lines.
func _random_chat() -> DialogueResource:
	var lines := _pick_lines()
	if lines.is_empty():
		return null
	var text := "~ %s\n" % DIALOGUE_START
	for line in lines:
		text += "Mooner: %s\n" % line
	text += "=> END\n"
	return DialogueManager.create_resource_from_text(text) as DialogueResource


## Picks a group by its weight, then a random line (or chain of lines) from it. It tries not to
## repeat what he said last time.
func _pick_lines() -> Array[String]:
	for attempt in 3:
		var group: Array = _lines.get(_pick_category(), [])
		if group.is_empty():
			continue
		var entry: Variant = group.pick_random()
		var chosen: Array[String] = []
		if entry is Array:
			for line in entry:
				chosen.append(str(line))
		else:
			chosen.append(str(entry))
		if chosen[0] != _last_first_line or attempt == 2:
			_last_first_line = chosen[0]
			return chosen
	return []


func _pick_category() -> String:
	var total := 0
	for category: String in CATEGORY_WEIGHTS:
		if _lines.has(category):
			total += int(CATEGORY_WEIGHTS[category])
	var roll := randi_range(1, maxi(total, 1))
	for category: String in CATEGORY_WEIGHTS:
		if _lines.has(category):
			roll -= int(CATEGORY_WEIGHTS[category])
			if roll <= 0:
				return category
	return ""


## Mooner fades away and can't be clicked until return_home().
func leave() -> void:
	_away = true
	hit_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hovering = false
	mooner.modulate = Color.WHITE
	_update_tooltip()
	var tween := create_tween()
	tween.tween_property(mooner, "self_modulate:a", 0.0, 1.0)
	await tween.finished
	mooner.visible = false


## Mooner fades back in.
func return_home() -> void:
	_away = false
	mooner.visible = true
	hit_area.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(mooner, "self_modulate:a", 1.0, 1.0)
	await tween.finished


func _on_hover(hovering: bool) -> void:
	_hovering = hovering
	mooner.modulate = HOVER_BRIGHTEN if hovering else Color.WHITE
	_update_tooltip()


## Only shown while the mouse is over him, and not during a conversation.
func _update_tooltip() -> void:
	tooltip.visible = _hovering and not _talking
	if tooltip.visible:
		_process(0.0)  # jump to the mouse right away instead of waiting for the next frame


func _on_hit_area_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		talk()


func _on_dialogue_ended(_resource: DialogueResource) -> void:
	_talking = false
	_update_tooltip()

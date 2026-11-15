class_name IntroDirector
extends Node
## Runs the opening story with Mooner using the Dialogue Manager add-on (intro.dialogue):
## eyes flickering open, the name prompt, the optional delta-V and research tutorials, the launch,
## Mooner leaving for the Moon, and his return.
##
## This node is the "game state" the dialogue calls into: every method the dialogue runs with
## `do` (ask_name, tutorial_delta_v, ...) lives here, and so do the variables it reads
## (player_name). main.gd creates it, sets `main`, and calls run_intro().

## Emitted by notify_launched() once the rocket has launched and the mission has begun.
signal launched
signal _name_entered

const DIALOGUE_PATH := "res://intro.dialogue"
const THEME_PATH := "res://addons/afaz-tools-ui-system/themes/classic/tool_window.tres"
const TOOL_PLANNER := "Mission Planner"
const GOLD := Color("ffd84a")

## How long the player's choice has to stay correct before the tutorial moves on.
@export var settle_seconds := 1.5

## Set by main.gd.
var main: MainSc

var player_name := "Astronaut"
## True from the start of the story until the first mission ends.
var story_active := false

var _research_needed: Array = []
var _waiting_for_return := false
var _planner_opened := false

var _layer: CanvasLayer
var _black: ColorRect
var _card_title: Label
var _card_subtitle: Label
var _prompt: PanelContainer
var _name_edit: LineEdit


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 90
	add_child(_layer)

	# Black screen used for the eyes opening and the launch cards.
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_STOP
	_black.visible = false
	_layer.add_child(_black)

	_card_title = _make_card_label("PROJECT BLAST OFF", 72, 0.0)
	_card_title.add_theme_color_override("font_color", GOLD)
	_card_title.add_theme_color_override("font_outline_color", Color(0.25, 0.1, 0.0))
	_card_title.add_theme_constant_override("outline_size", 12)
	_card_subtitle = _make_card_label("Lunar orbit reached", 28, 90.0)

	_build_name_prompt()


# --- Story ---

## Starts the opening: the eyes open, then the conversation begins.
func run_intro() -> void:
	story_active = true
	_black.color.a = 1.0
	_black.visible = true  # covers the screen right away, before anything is drawn
	await _eyes_open()
	var dialogue := load(DIALOGUE_PATH) as DialogueResource
	if dialogue == null:
		push_warning("IntroDirector: could not load %s" % DIALOGUE_PATH)
		main.begin_planning()
		return
	DialogueManager.show_dialogue_balloon(dialogue, "intro", [self])


## Called by main.gd once the mission has begun.
func on_mission_launched(params: Dictionary) -> void:
	_research_needed = params.get("research", [])
	var mission := main.get_service("MissionService") as MissionService
	if mission:
		mission.set_return_locked(true)


## Called by main.gd when the launch cards are over. Lets the dialogue continue.
func notify_launched() -> void:
	launched.emit()


## The first mission is over (the player returned or died): the story is finished.
func end_story() -> void:
	if not story_active:
		return
	story_active = false
	_waiting_for_return = false
	_clear_hint()
	var mission := main.get_service("MissionService") as MissionService
	if mission:
		mission.set_return_locked(false)
		mission.set_status("")
	var mooner := _mooner()
	if mooner:
		mooner.return_home()


func _process(_delta: float) -> void:
	if not _waiting_for_return:
		return
	var data := main.get_service("MissionDataService") as MissionDataService
	var mission := main.get_service("MissionService") as MissionService
	if data == null:
		return

	# Mooner is back once every experiment that was brought has produced data.
	var done := 0
	for id: String in _research_needed:
		if data.get_count(id) >= 1:
			done += 1
	if done >= _research_needed.size():
		_waiting_for_return = false
		if mission:
			mission.set_status("")
		_mooner_comes_back()
	elif mission:
		mission.set_status("Research finished: %d / %d\nFinish all your research to bring Mooner back" % [done, _research_needed.size()])


func _mooner_comes_back() -> void:
	var mooner := _mooner()
	if mooner:
		await mooner.return_home()
	var dialogue := load(DIALOGUE_PATH) as DialogueResource
	if dialogue:
		DialogueManager.show_dialogue_balloon(dialogue, "return_home", [self])


# --- Called from the dialogue with `do` ---

## Asks for the player's name.
func ask_name() -> void:
	_name_edit.text = ""
	_prompt.visible = true
	_name_edit.grab_focus()
	await _name_entered
	player_name = _name_edit.text.strip_edges()
	if player_name.is_empty():
		player_name = "Astronaut"
	_prompt.visible = false


func open_planner() -> void:
	await _get_planner()


## Tutorial: the player sets a delta-V that is enough to reach the Moon.
func tutorial_delta_v() -> void:
	var planner := await _get_planner()
	_set_hint("hint_delta_v")
	planner.set_delta_v(0.0)
	await _wait_until(Callable(planner, "is_delta_v_valid"))
	_clear_hint()


## Tutorial: the player packs research machines that fit in the rocket's power.
func tutorial_research() -> void:
	var planner := await _get_planner()
	_set_hint("hint_research")
	planner.clear_apparatus()
	await _wait_until(Callable(planner, "is_payload_valid"))
	_clear_hint()


## Waits for the big red button. main.gd calls notify_launched() when the mission has begun.
func wait_for_launch() -> void:
	await _get_planner()
	await launched


## Mooner walks off. From here the research decides when he returns.
func mooner_leave() -> void:
	var mooner := _mooner()
	if mooner:
		await mooner.leave()
	_waiting_for_return = true


## The RETURN button works again.
func unlock_return() -> void:
	var mission := main.get_service("MissionService") as MissionService
	if mission:
		mission.set_return_locked(false)


# --- Screens ---

## The screen flickers open like eyes that are still waking up.
func _eyes_open() -> void:
	_black.visible = true
	_black.color.a = 1.0
	var tween := create_tween()
	tween.tween_property(_black, "color:a", 0.55, 0.3)
	tween.tween_property(_black, "color:a", 1.0, 0.25)
	tween.tween_property(_black, "color:a", 0.3, 0.3)
	tween.tween_property(_black, "color:a", 1.0, 0.2)
	tween.tween_property(_black, "color:a", 0.0, 1.4)
	await tween.finished
	_black.visible = false


## First half of the launch cards: fade to black and show the title. The mission begins behind it.
func cards_begin() -> void:
	_black.color.a = 0.0
	_black.visible = true
	var tween := create_tween()
	tween.tween_property(_black, "color:a", 1.0, 0.7)
	tween.tween_property(_card_title, "modulate:a", 1.0, 0.8)
	tween.tween_interval(1.8)
	await tween.finished


## Second half: the Moon's orbit is reached, then the cards fade away.
func cards_end() -> void:
	var tween := create_tween()
	tween.tween_property(_card_title, "modulate:a", 0.0, 0.5)
	tween.tween_property(_card_subtitle, "modulate:a", 1.0, 0.6)
	tween.tween_interval(1.4)
	tween.tween_property(_card_subtitle, "modulate:a", 0.0, 0.5)
	tween.tween_property(_black, "color:a", 0.0, 0.8)
	await tween.finished
	_black.visible = false


func _make_card_label(text: String, font_size: int, extra_top: float) -> Label:
	var label := Label.new()
	label.text = text
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_top = extra_top
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.modulate.a = 0.0
	_layer.add_child(label)
	return label


func _build_name_prompt() -> void:
	_prompt = PanelContainer.new()
	_prompt.theme = load(THEME_PATH) as Theme
	_prompt.visible = false
	_prompt.custom_minimum_size = Vector2(420.0, 0.0)
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 0.5
	_prompt.anchor_bottom = 0.5
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.grow_vertical = Control.GROW_DIRECTION_BOTH
	_layer.add_child(_prompt)
	_prompt.add_theme_stylebox_override("panel", _prompt.get_theme_stylebox("panel", "Panel"))

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_prompt.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var question := Label.new()
	question.text = "What is your name?"
	question.add_theme_font_size_override("font_size", 24)
	question.add_theme_color_override("font_color", GOLD)
	box.add_child(question)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name"
	_name_edit.max_length = 16
	_name_edit.add_theme_font_size_override("font_size", 22)
	_name_edit.text_submitted.connect(func(_text: String) -> void: _name_entered.emit())
	box.add_child(_name_edit)

	var ok := Button.new()
	ok.text = "OK"
	ok.custom_minimum_size = Vector2(0.0, 40.0)
	ok.pressed.connect(func() -> void: _name_entered.emit())
	box.add_child(ok)


# --- Helpers ---

func _mooner() -> MoonerService:
	return main.get_service("MoonerService") as MoonerService


## Opens the Mission Planner if needed and returns its content once it exists.
func _get_planner() -> Node:
	var minigames := main.get_service("MinigameService") as MinigameService
	if not _planner_opened:
		_planner_opened = true
		main.begin_planning()
	var planner := minigames.get_tool_content(TOOL_PLANNER)
	while planner == null:
		await get_tree().process_frame
		planner = minigames.get_tool_content(TOOL_PLANNER)
	return planner


## Waits until `condition` has been true for `settle_seconds` in a row.
func _wait_until(condition: Callable) -> void:
	var steady := 0.0
	while steady < settle_seconds:
		await get_tree().create_timer(0.1, false).timeout
		if not condition.is_valid():
			return  # the planner was closed
		steady = steady + 0.1 if condition.call() else 0.0


## Clicking Mooner while a tutorial step runs repeats that step's advice.
func _set_hint(title: String) -> void:
	var mooner := _mooner()
	if mooner:
		mooner.set_topic(DIALOGUE_PATH, title)


func _clear_hint() -> void:
	var mooner := _mooner()
	if mooner:
		mooner.reset_topic()

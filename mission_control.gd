extends Control
## The one tool the player opens. They pick instruments from waste.json, choose how many
## minigames to play, and press START. The instruments they pick set how often each minigame
## comes up: each ticked instrument adds its power cost (watts) to its category's share, so a
## costlier instrument makes its minigame more frequent.
##
## While a session runs the minigames play one after another inside this tool, and the game
## clock runs faster (see ClockService).
##
## This scene reports to MinigameService with the same interface a single minigame uses:
## `solved`, `failed`, and `data_category` (set to the minigame that just finished).

signal solved
signal failed
## The session started (true) or ended (false).
signal playing_changed(playing: bool)

const WASTE_PATH := "res://waste.json"

## waste.json category -> the minigame it controls, and what that minigame collects.
const MINIGAMES := {
	"Elevation and Radar Mapping": {
		"scene": preload("res://minigame.tscn"),
		"controls": "LIDAR scans",
		"data": "lidar",
	},
	"Radiation and Particle Science": {
		"scene": preload("res://minigame_4.tscn"),
		"controls": "Radiation readings",
		"data": "radiation",
	},
	"Dust and Solar Science": {
		"scene": preload("res://minigame_3.tscn"),
		"controls": "Dust samples",
		"data": "dust",
	},
	"Imaging and Cartography": {
		"scene": preload("res://minigame_2.tscn"),
		"controls": "Minerals",
		"data": "minerals",
	},
}
const HEADER_COLOR := Color("ffd84a")
const MUTED_COLOR := Color(1.0, 1.0, 1.0, 0.55)
const POWER_OK_COLOR := Color("4aff7a")
const POWER_NEAR_COLOR := Color("ffd84a")
const POWER_OVER_COLOR := Color("ff4a4a")
## Every button in this tool plays this when pressed.
const BUTTON_SOUND := preload("res://buttonclick.mp3")

## Total power the instruments may draw, in watts. Going over blocks START.
@export_range(1.0, 1000.0, 1.0, "or_greater") var power_budget := 120.0
## How many minigames the planner starts with.
@export_range(1, 50) var default_minigames := 5
## Largest number of minigames a session can have.
@export_range(1, 50) var max_minigames := 20
## Seconds a result stays on screen before the next minigame starts.
@export var result_delay := 1.3

## Kind of data the minigame that just finished produces. Read by MinigameService.
var data_category := ""
## True while a session is running. Read by MinigameService.
var playing := false

var _checks: Dictionary = {}  # category -> Array[CheckBox]
var _frequency_labels: Dictionary = {}  # category -> Label
var _total := 0
var _played := 0
var _solved_count := 0
var _failed_count := 0
var _session := 0  # bumped whenever a session starts or ends, so stale timers do nothing
var _resolving := false
var _current: Control
var _click_player: AudioStreamPlayer
var _brought: Array = []  # instruments brought on the rocket (empty and unrestricted = all)
var _restricted := false

@onready var setup: Control = $Setup
@onready var power_bar: HSlider = $Setup/PowerRow/PowerBar
@onready var power_value: Label = $Setup/PowerRow/PowerValue
@onready var columns: HBoxContainer = $Setup/Columns
@onready var count_box: SpinBox = $Setup/Footer/Count
@onready var info: Label = $Setup/Footer/Info
@onready var start_button: Button = $Setup/Footer/StartButton
@onready var play: Control = $Play
@onready var area: Control = $Play/Area
@onready var progress: Label = $Play/Progress
@onready var end_button: Button = $Play/EndButton
@onready var summary: Control = $Play/Summary
@onready var summary_detail: Label = $Play/Summary/Margin/Box/Detail
@onready var back_button: Button = $Play/Summary/Margin/Box/BackButton


## Receives the mission settings from the Mission Planner when this tool opens. Runs before
## _ready. Instruments that were not brought are locked and the power budget is the one chosen.
func configure(params: Dictionary) -> void:
	_restricted = params.has("apparatus")
	_brought = params.get("apparatus", [])
	if params.has("power"):
		power_budget = float(params["power"])


func _ready() -> void:
	count_box.min_value = 1
	count_box.max_value = max_minigames
	count_box.value = default_minigames

	# The power bar only displays the total; hide the knob so it reads as a gauge.
	var no_knob := ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))
	for icon_name in ["grabber", "grabber_highlight", "grabber_disabled"]:
		power_bar.add_theme_icon_override(icon_name, no_knob)

	_build_columns(load_waste())
	start_button.pressed.connect(_start_session)
	end_button.pressed.connect(_end_session)
	back_button.pressed.connect(_show_setup)

	_click_player = AudioStreamPlayer.new()
	_click_player.stream = BUTTON_SOUND
	_click_player.bus = AudioSettings.SFX
	add_child(_click_player)
	_wire_button_sounds(self)  # every button built so far, including the instrument checkboxes

	_show_setup()
	_update_frequencies()


# --- Setup screen ---

## Reads waste.json: {category: {instrument: watts}}. Also used by the Mission Planner.
static func load_waste() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(WASTE_PATH))
	if parsed is Dictionary:
		return parsed
	push_error("MissionControl: could not read %s" % WASTE_PATH)
	return {}


## One column per minigame: the category's instruments as checkboxes.
func _build_columns(waste: Dictionary) -> void:
	for category: String in MINIGAMES:
		var instruments: Dictionary = waste.get(category, {})
		if instruments.is_empty():
			push_warning("MissionControl: no instruments for '%s' in waste.json" % category)

		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", get_theme_stylebox("panel", "Panel"))
		var margin := MarginContainer.new()
		for side in ["left", "top", "right", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 8)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)

		var title := Label.new()
		title.text = category
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.add_theme_font_size_override("font_size", 14)
		title.add_theme_color_override("font_color", HEADER_COLOR)
		column.add_child(title)

		var controls := Label.new()
		controls.text = "Plays: %s" % MINIGAMES[category].controls
		controls.add_theme_font_size_override("font_size", 11)
		controls.add_theme_color_override("font_color", MUTED_COLOR)
		column.add_child(controls)

		var frequency := Label.new()
		frequency.add_theme_font_size_override("font_size", 12)
		column.add_child(frequency)
		_frequency_labels[category] = frequency

		column.add_child(HSeparator.new())

		var checks: Array[CheckBox] = []
		for instrument: String in instruments:
			# waste.json gives each instrument's power cost in watts.
			var watts := float(instruments[instrument])

			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)

			# Instruments that were not brought on the rocket are locked.
			var brought := not _restricted or instrument in _brought

			var check := CheckBox.new()
			check.text = instrument
			check.tooltip_text = "%s (%d W)" % [instrument, int(watts)]
			if not brought:
				check.disabled = true
				check.tooltip_text = "%s - not brought on this mission" % instrument
				row.modulate.a = 0.4
			check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			check.clip_text = true
			check.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			check.add_theme_font_size_override("font_size", 11)
			check.set_meta("watts", watts)
			check.toggled.connect(_on_instrument_toggled)
			row.add_child(check)

			var cost := Label.new()
			cost.text = ("%d W" % int(watts)) if brought else "locked"
			cost.custom_minimum_size = Vector2(40.0, 0.0)
			cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cost.add_theme_font_size_override("font_size", 11)
			cost.add_theme_color_override("font_color", MUTED_COLOR)
			row.add_child(cost)

			column.add_child(row)
			checks.append(check)
		_checks[category] = checks

		margin.add_child(column)
		panel.add_child(margin)
		columns.add_child(panel)

	# Start with one instrument per category. This waits until every column exists, because
	# ticking a box updates the frequencies of all columns.
	for category: String in _checks:
		for check: CheckBox in _checks[category]:
			if not check.disabled:
				check.button_pressed = true
				break


## Makes every button under `node` play the button sound when pressed.
func _wire_button_sounds(node: Node) -> void:
	if node is BaseButton and not node.has_meta("click_wired"):
		node.set_meta("click_wired", true)
		(node as BaseButton).pressed.connect(_play_button_sound)
	for child in node.get_children():
		_wire_button_sounds(child)


func _play_button_sound() -> void:
	_click_player.play()


func _on_instrument_toggled(_pressed: bool) -> void:
	_update_frequencies()


## How often a category's minigame comes up: the combined power cost (watts) of the
## ticked instruments in that category. A costlier instrument adds more.
func _weight(category: String) -> float:
	var watts := 0.0
	for check: CheckBox in _checks[category]:
		if check.button_pressed:
			watts += float(check.get_meta("watts", 0.0))
	return watts


## True if at least one of the category's instruments was brought (is not locked).
func _has_available(category: String) -> bool:
	for check: CheckBox in _checks[category]:
		if not check.disabled:
			return true
	return false


func _total_weight() -> float:
	var total := 0.0
	for category: String in MINIGAMES:
		total += _weight(category)
	return total


func _update_frequencies() -> void:
	var total := _total_weight()
	for category: String in MINIGAMES:
		var weight := _weight(category)
		var label: Label = _frequency_labels[category]
		if not _has_available(category):
			label.text = "Frequency: locked"
			label.add_theme_color_override("font_color", MUTED_COLOR)
		elif weight == 0:
			label.text = "Frequency: off"
			label.add_theme_color_override("font_color", MUTED_COLOR)
		else:
			label.text = "Frequency: %d%%" % int(round(100.0 * weight / total))
			label.remove_theme_color_override("font_color")
	_update_power()


## Total watts of every ticked instrument.
func _power_used() -> float:
	var used := 0.0
	for category: String in MINIGAMES:
		for check: CheckBox in _checks[category]:
			if check.button_pressed:
				used += float(check.get_meta("watts", 0.0))
	return used


## Updates the power bar. Going over the budget blocks START.
func _update_power() -> void:
	var used := _power_used()
	var over := used > power_budget
	var empty := _total_weight() == 0

	power_bar.max_value = power_budget
	power_bar.value = minf(used, power_budget)
	if over:
		power_bar.self_modulate = POWER_OVER_COLOR
		power_value.add_theme_color_override("font_color", POWER_OVER_COLOR)
	else:
		power_bar.self_modulate = POWER_NEAR_COLOR if used >= power_budget * 0.85 else POWER_OK_COLOR
		power_value.remove_theme_color_override("font_color")
	power_value.text = "%d / %d W" % [int(used), int(power_budget)]

	start_button.disabled = empty or over
	if over:
		info.text = "Over budget by %d W. Remove an instrument." % int(ceil(used - power_budget))
	elif empty:
		info.text = "Select at least one instrument"
	else:
		info.text = "Game time runs 2x faster while playing"


func _show_setup() -> void:
	setup.visible = true
	play.visible = false
	summary.visible = false
	end_button.visible = true
	progress.visible = true


# --- Playing a session ---

func _start_session() -> void:
	if _total_weight() == 0 or _power_used() > power_budget:
		return
	_session += 1
	_total = int(count_box.value)
	_played = 0
	_solved_count = 0
	_failed_count = 0
	_resolving = false

	setup.visible = false
	play.visible = true
	summary.visible = false
	end_button.visible = true
	progress.visible = true
	_set_playing(true)
	_next_minigame()


## Stops the session early and returns to the planner.
func _end_session() -> void:
	_session += 1
	_resolving = false
	_clear_minigame()
	_set_playing(false)
	_show_setup()


func _finish_session() -> void:
	_clear_minigame()
	_set_playing(false)
	progress.visible = false
	end_button.visible = false
	summary_detail.text = "Solved: %d     Failed: %d" % [_solved_count, _failed_count]
	summary.visible = true


func _next_minigame() -> void:
	if _played >= _total:
		_finish_session()
		return

	var category := _pick_category()
	var scene: PackedScene = MINIGAMES[category].scene
	_current = scene.instantiate() as Control
	# One round per turn: this tool decides what plays next (ignored by minigames without it).
	_current.set("single_round", true)
	area.add_child(_current)
	_wire_button_sounds(_current)  # e.g. the Geiger STOP button
	_current.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_current.connect("solved", _on_minigame_result.bind(true))
	if _current.has_signal("failed"):
		_current.connect("failed", _on_minigame_result.bind(false))

	progress.text = "Minigame %d / %d" % [_played + 1, _total]


## Picks a category at random, weighted by the power cost of its ticked instruments.
func _pick_category() -> String:
	var roll := randf() * _total_weight()
	var last := ""
	for category: String in MINIGAMES:
		var weight := _weight(category)
		if weight == 0:
			continue
		last = category
		roll -= weight
		if roll <= 0.0:
			return category
	return last


func _on_minigame_result(success: bool) -> void:
	if _resolving or _current == null:
		return
	_resolving = true
	var session := _session

	# Report to MinigameService, which handles the oxygen penalty and the data counters.
	data_category = str(_current.get("data_category"))
	if success:
		_solved_count += 1
		solved.emit()
	else:
		_failed_count += 1
		failed.emit()
	_played += 1

	await get_tree().create_timer(result_delay, false).timeout
	if session != _session:
		return  # the session was ended or restarted while waiting
	_resolving = false
	_clear_minigame()
	_next_minigame()


func _clear_minigame() -> void:
	if _current:
		_current.queue_free()
		_current = null


func _set_playing(value: bool) -> void:
	playing = value
	playing_changed.emit(value)

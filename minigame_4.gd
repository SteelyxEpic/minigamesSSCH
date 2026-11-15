extends Control
## Geiger counter: slide along the surface, listen to the clicks (faster = more radiation),
## and press STOP where you think the radiation is highest.

signal solved
## STOP was pressed away from the hot spot.
signal failed

const CLICK_SOUND := preload("res://click.mp3")
const POOL_SIZE := 6
const PEAK_SAMPLES := 200
const BACKGROUND_RADIATION := 0.04

## Kind of mission data a success produces (see MissionDataService).
@export var data_category := "radiation"
## Clicks per second at the strongest spot.
@export var max_rate := 25.0
## Fraction of the peak reading that counts as having found the hot spot.
@export var success_ratio := 0.85
@export var result_delay := 1.8

var _peaks: Array[Vector3] = []  # x = center, y = width, z = height
var _peak_value := 1.0
var _stopped := false
var _counts := 0
var _led := 0.0
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _result_tween: Tween

@onready var hint: RichTextLabel = $Stage/Hint
@onready var slider: HSlider = $Stage/Slider
@onready var stop_button: Button = $Stage/StopButton
@onready var result: RichTextLabel = $Stage/Result


func _ready() -> void:
	# Several players so fast clicks can overlap instead of cutting each other off.
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.stream = CLICK_SOUND
		add_child(player)
		_players.append(player)

	result.pivot_offset = result.size / 2.0
	stop_button.pressed.connect(_on_stop_pressed)
	hint.text = "[center][font_size=30]Find the strongest reading[/font_size]\n" \
			+ "[font_size=16]Move the slider and listen. Fast = more.[/font_size][/center]"
	_new_round()


func _process(delta: float) -> void:
	_led = maxf(_led - delta * 6.0, 0.0)
	if is_visible_in_tree() and not _stopped:
		# Random (Poisson) clicks: the chance of a click this frame grows with the radiation.
		var rate := max_rate * _radiation_at(slider.value) / _peak_value
		if randf() < 1.0 - exp(-rate * delta):
			_click()
	queue_redraw()


func _new_round() -> void:
	_stopped = false
	_counts = 0
	_led = 0.0
	slider.editable = true
	slider.value = 0.0
	result.text = ""
	if _result_tween:
		_result_tween.kill()
	result.scale = Vector2.ONE

	# One strong hot spot plus a weaker decoy somewhere else.
	var main_center := randf_range(0.12, 0.88)
	var direction := 1.0 if main_center < 0.5 else -1.0
	var decoy_center := main_center + direction * randf_range(0.28, 0.45)
	_peaks = [
		Vector3(main_center, randf_range(0.06, 0.1), 1.0),
		Vector3(decoy_center, randf_range(0.05, 0.09), randf_range(0.4, 0.7)),
	]
	_peak_value = 0.0
	for i in PEAK_SAMPLES + 1:
		_peak_value = maxf(_peak_value, _radiation_at(float(i) / PEAK_SAMPLES))


func _radiation_at(x: float) -> float:
	var total := BACKGROUND_RADIATION
	for peak in _peaks:
		total += peak.z * exp(-pow((x - peak.x) / peak.y, 2.0))
	return total


func _click() -> void:
	_counts += 1
	_led = 1.0
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % POOL_SIZE
	player.pitch_scale = randf_range(0.92, 1.08)
	player.play()


func _on_stop_pressed() -> void:
	if _stopped:
		return
	_stopped = true
	slider.editable = false

	var ratio := _radiation_at(slider.value) / _peak_value
	var success := ratio >= success_ratio
	var text := "[color=#ffd84a]Hot spot found![/color]" if success else "[color=#ff7a5a]Not the highest. Keep looking.[/color]"
	result.text = "[center][font_size=30][b]%s[/b][/font_size]\n[font_size=20]Reading: %d%% of the peak[/font_size][/center]" % [text, int(round(ratio * 100.0))]

	result.scale = Vector2(0.5, 0.5)
	if _result_tween:
		_result_tween.kill()
	_result_tween = create_tween()
	_result_tween.tween_property(result, "scale", Vector2.ONE, 0.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if success:
		solved.emit()
	else:
		failed.emit()
	await get_tree().create_timer(result_delay).timeout
	if not is_inside_tree():
		return
	if success:
		_new_round()
	else:
		_stopped = false
		slider.editable = true
		result.text = ""


func _draw() -> void:
	# Laid out in the centered stage's coordinates.
	draw_set_transform($Stage.position)
	var font := ThemeDB.fallback_font
	var panel := Rect2(40.0, 70.0, 900.0, 160.0)
	draw_rect(panel, Color(0.1, 0.11, 0.14))
	draw_rect(panel, Color(0.45, 0.47, 0.55), false, 2.0)

	# Click lamp: flashes on every click.
	var lamp := Vector2(110.0, 150.0)
	draw_circle(lamp, 30.0, Color(0.2, 0.05, 0.05))
	draw_circle(lamp, 30.0, Color(1.0, 0.25, 0.2, _led))
	draw_arc(lamp, 30.0, 0.0, TAU, 48, Color(0.6, 0.6, 0.65), 3.0, true)

	draw_string(font, Vector2(170.0, 130.0), "CLICKS", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(1, 1, 1, 0.6))
	draw_string(font, Vector2(170.0, 180.0), str(_counts), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 44, Color(1, 1, 1, 0.9))
	draw_string(font, Vector2(80.0, 252.0), "Surface scan", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(1, 1, 1, 0.5))

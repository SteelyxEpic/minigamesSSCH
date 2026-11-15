extends Control

## The player hit the beat (perfect, early or late all count).
signal solved
## The player missed the beat.
signal failed

enum Timing { PERFECT, EARLY, LATE }

## Kind of mission data a success produces (see MissionDataService).
@export var data_category := "lidar"

const CLICK_SOUND := preload("uid://dqdspqodnnicj")
const BEAT_SOUND := preload("uid://drj8n1qbll8ki")

const TIMING_TEXT := {
	Timing.PERFECT: "[color=#ffd84a]PERFECT![/color]",
	Timing.EARLY: "[color=#4ac8ff]EARLY[/color]",
	Timing.LATE: "[color=#ff9a4a]LATE[/color]",
}
const MISS_TEXT := "[color=#ff4a4a]MISS[/color]"

## Width and height of one sprite in lidar.asprite.png.
const FRAME_SIZE := 24

const BAR_IDLE_COLOR := Color("5a6a7a")
const BAR_ACTIVE_COLOR := Color("4aff7a")
const EARLY_ZONE_COLOR := Color(0.29, 0.78, 1.0, 0.55)
const PERFECT_ZONE_COLOR := Color(1.0, 0.85, 0.29, 0.8)
const LATE_ZONE_COLOR := Color(1.0, 0.6, 0.29, 0.55)

@export_group("Rhythm")
@export var min_beats := 3
@export var max_beats := 6
@export var min_interval := 1.0
@export var max_interval := 3.0
@export var result_pause := 1.0

@export_group("Timing Windows")
## Clicks within this many seconds of the beat count as PERFECT.
@export var perfect_window := 0.08
## Clicks up to this many seconds before the beat still pass (EARLY).
@export var early_window := 0.25
## Clicks up to this many seconds after the beat still pass (LATE).
@export var late_window := 0.25

@export_group("Difficulty")
## Shows the colored zones and green fill that reveal where to click. Off = harder.
@export var show_hint_colors := false

@export_group("Audio")
@export var pitch_step := 0.05
@export var miss_pitch := 0.5

@export_group("Feedback Animation")
@export var feedback_pop_time := 0.4
@export var feedback_hold_time := 0.4
@export var feedback_fade_time := 0.25
@export var feedback_rise := 30.0

var misses := 0
var _waiting_for_click := false
var _clicked_in_time := false
var _timing := Timing.PERFECT
var _beat_duration := 0.0
var _round_start := 0.0  # seconds, from Time.get_ticks_msec()
var _target_time := 0.0  # seconds after _round_start that the player should click
var _beat_tween: Tween
var _feedback_tween: Tween
var _feedback_rest_pos: Vector2
var _atlas: AtlasTexture
var _frame_count := 1
var _bar_active := false
var _bar_tween: Tween
var _bar_fill: StyleBoxFlat
var _early_zone: ColorRect
var _perfect_zone: ColorRect
var _late_zone: ColorRect

@onready var timing_bar: ProgressBar = $Stage/TimingBar
@onready var zones: Control = $Stage/TimingBar/Zones
@onready var label: RichTextLabel = $Stage/RichTextLabel
@onready var feedback_label: RichTextLabel = $Stage/FeedbackLabel
@onready var audio: AudioStreamPlayer2D = $AudioStreamPlayer2D
@onready var texture: TextureRect = $Stage/TextureRect


func _ready() -> void:
	_atlas = texture.texture as AtlasTexture
	_frame_count = maxi(floori(float(_atlas.atlas.get_width()) / FRAME_SIZE), 1)
	_feedback_rest_pos = feedback_label.position
	feedback_label.pivot_offset = feedback_label.size / 2.0
	_setup_timing_bar()
	_run_beat_loop()


func _process(_delta: float) -> void:
	if not _bar_active:
		return
	var elapsed := _now() - _round_start
	timing_bar.value = clampf(elapsed / (_target_time + late_window), 0.0, 1.0)
	# Brighten the fill once clicking counts.
	if show_hint_colors:
		var in_window := elapsed >= _target_time - early_window
		_bar_fill.bg_color = BAR_ACTIVE_COLOR if in_window else BAR_IDLE_COLOR


func _gui_input(event: InputEvent) -> void:
	if not _waiting_for_click:
		return
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_register_hit()


func _register_hit() -> void:
	# Offset from the beat: negative = early, positive = late.
	var offset := _now() - _round_start - _target_time
	if offset < -early_window:
		return  # too soon to count; keep waiting

	_waiting_for_click = false  # ignore any further clicks this round
	_clicked_in_time = true
	_play_sound(CLICK_SOUND, 1.0)  # instant feedback

	if absf(offset) <= perfect_window:
		_timing = Timing.PERFECT
	elif offset < 0.0:
		_timing = Timing.EARLY
	else:
		_timing = Timing.LATE
	_show_feedback(TIMING_TEXT[_timing])


func _run_beat_loop() -> void:
	while is_inside_tree():
		await _run_round()


func _run_round() -> void:
	# Idle while the minigame's window is hidden.
	while not is_visible_in_tree():
		await get_tree().process_frame

	var beats := maxi(randi_range(min_beats, max_beats), 1)
	_beat_duration = randf_range(min_interval, max_interval) / beats

	# Beat N lands after N-1 beat lengths (beat 1 is at t=0).
	_target_time = _beat_duration * (beats - 1)
	label.text = "[center]Hit on the %d beat[/center]" % beats
	var pitch := 1.0

	# The bar covers the whole round, from the first beat to the end of the late window.
	_round_start = _now()
	_clicked_in_time = false
	_waiting_for_click = true  # clicks before the early window are ignored in _register_hit
	_show_timing_bar()

	# Warm-up beats
	for i in beats - 1:
		pitch += pitch_step
		_play_sound(BEAT_SOUND, pitch)
		await _fade_beat(_beat_duration)

	# The player's beat: show the pulse silently (their click makes the sound).
	# Clicks count from `early_window` before it until `late_window` after it.
	_fade_beat(_beat_duration)
	while not _clicked_in_time and _now() - _round_start < _target_time + late_window:
		await get_tree().process_frame
	_waiting_for_click = false
	_hide_timing_bar()

	if _clicked_in_time:
		solved.emit()  # sound and feedback already handled on click
	else:
		_play_sound(BEAT_SOUND, miss_pitch)
		_show_feedback(MISS_TEXT)
		misses += 1
		failed.emit()

	await get_tree().create_timer(result_pause).timeout


func _fade_beat(duration: float) -> void:
	if _beat_tween:
		_beat_tween.kill()
	texture.modulate.a = 1.0
	_set_frame(0)
	_beat_tween = create_tween()
	_beat_tween.tween_property(texture, "modulate:a", 0.0, duration)
	# Play the sprite sheet across the beat.
	_beat_tween.parallel().tween_method(_play_frame, 0.0, float(_frame_count), duration)
	await _beat_tween.finished


func _play_frame(progress: float) -> void:
	_set_frame(int(progress))


func _set_frame(frame: int) -> void:
	_atlas.region = Rect2(clampi(frame, 0, _frame_count - 1) * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)


func _show_feedback(bbcode: String) -> void:
	if _feedback_tween:
		_feedback_tween.kill()

	feedback_label.text = "[center][wave amp=10.0 freq=6.0][b]%s[/b][/wave][/center]" % bbcode
	feedback_label.modulate.a = 0.0
	feedback_label.scale = Vector2(0.3, 0.3)
	feedback_label.position = _feedback_rest_pos + Vector2(0.0, feedback_rise)

	_feedback_tween = create_tween()
	# Pop in: overshoot scale, quick fade, rise into place.
	_feedback_tween.set_parallel(true)
	_feedback_tween.tween_property(feedback_label, "scale", Vector2.ONE, feedback_pop_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_feedback_tween.tween_property(feedback_label, "modulate:a", 1.0, feedback_pop_time * 0.5)
	_feedback_tween.tween_property(feedback_label, "position", _feedback_rest_pos, feedback_pop_time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Then hold and fade away.
	_feedback_tween.chain().tween_interval(feedback_hold_time)
	_feedback_tween.chain().tween_property(feedback_label, "modulate:a", 0.0, feedback_fade_time)


func _setup_timing_bar() -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.1, 0.12, 0.16, 0.9)
	_bar_fill = StyleBoxFlat.new()
	_bar_fill.bg_color = BAR_IDLE_COLOR
	for box: StyleBoxFlat in [background, _bar_fill]:
		box.set_corner_radius_all(8)
	timing_bar.add_theme_stylebox_override("background", background)
	timing_bar.add_theme_stylebox_override("fill", _bar_fill)

	_early_zone = _make_zone(EARLY_ZONE_COLOR)
	_perfect_zone = _make_zone(PERFECT_ZONE_COLOR)
	_late_zone = _make_zone(LATE_ZONE_COLOR)


func _make_zone(color: Color) -> ColorRect:
	var zone := ColorRect.new()
	zone.color = color
	zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zones.add_child(zone)
	return zone


## Places the early / perfect / late zones along the bar for this round.
func _layout_zones() -> void:
	var total := _target_time + late_window
	var width := timing_bar.size.x
	var height := timing_bar.size.y
	var early_start := maxf(_target_time - early_window, 0.0)
	var perfect_start := maxf(_target_time - perfect_window, early_start)
	var perfect_end := minf(_target_time + perfect_window, total)
	_place_zone(_early_zone, early_start, perfect_start, total, width, height)
	_place_zone(_perfect_zone, perfect_start, perfect_end, total, width, height)
	_place_zone(_late_zone, perfect_end, total, total, width, height)


func _place_zone(zone: ColorRect, from_t: float, to_t: float, total: float, width: float, height: float) -> void:
	zone.position = Vector2(width * from_t / total, 0.0)
	zone.size = Vector2(width * (to_t - from_t) / total, height)


func _show_timing_bar() -> void:
	if _bar_tween:
		_bar_tween.kill()
	zones.visible = show_hint_colors
	_layout_zones()
	timing_bar.value = 0.0
	_bar_fill.bg_color = BAR_IDLE_COLOR
	_bar_active = true
	_bar_tween = create_tween()
	_bar_tween.tween_property(timing_bar, "modulate:a", 1.0, 0.15)


func _hide_timing_bar() -> void:
	_bar_active = false
	if _bar_tween:
		_bar_tween.kill()
	_bar_tween = create_tween()
	_bar_tween.tween_interval(0.4)  # let the player see where they landed
	_bar_tween.tween_property(timing_bar, "modulate:a", 0.0, 0.25)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _play_sound(stream: AudioStream, pitch: float) -> void:
	audio.stream = stream
	audio.pitch_scale = pitch
	audio.play()

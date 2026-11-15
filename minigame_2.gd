extends Control
## Turn the knobs until the bottom graph matches the top (target) graph.

signal solved

## Kind of mission data a success produces (see MissionDataService).
@export var data_category := "minerals"

## Highest per-line RMS error that still counts as matching.
@export var tolerance := 0.15
## Seconds all three lines must stay matched before the round is solved.
@export var hold_time := 0.4
## Seconds the MATCHED message shows before the next target appears.
@export var next_round_delay := 1.8

## Error at which a line counts as 0% matched (for the percentage display).
const MAX_ERROR := 0.8
const UNMATCHED_DOT_COLOR := "#555555"

var _errors: Array[float] = [1.0, 1.0, 1.0]
var _all_matched := false
var _held := 0.0
var _solved := false
var _status_tween: Tween

@onready var knobs: Array[Knob] = [$Stage/Knob1 as Knob, $Stage/Knob2 as Knob, $Stage/Knob3 as Knob]
@onready var target_graph: WaveGraph = $Stage/TargetGraph
@onready var player_graph: WaveGraph = $Stage/PlayerGraph
@onready var status: RichTextLabel = $Stage/Status


func _ready() -> void:
	status.pivot_offset = status.size / 2.0
	for i in knobs.size():
		knobs[i].turned.connect(_on_knob_turned.bind(i))
		# Match each knob's pointer to its line color.
		knobs[i].pointer_color = target_graph.line_colors[i]
	_new_round()


func _process(delta: float) -> void:
	if _solved:
		return
	if _all_matched:
		_held += delta
		if _held >= hold_time:
			_solve()
	else:
		_held = 0.0


func _on_knob_turned(total_degrees: float, index: int) -> void:
	if _solved:
		return
	player_graph.set_phase_degrees(index, total_degrees)
	_update_match()


func _new_round() -> void:
	_solved = false
	_held = 0.0
	if _status_tween:
		_status_tween.kill()
	status.scale = Vector2.ONE
	status.modulate.a = 1.0

	for i in knobs.size():
		knobs[i].angle_degrees = 0.0
		player_graph.set_phase_degrees(i, 0.0)

	# Pick a target that is clearly different from the starting position on every line.
	for _attempt in 20:
		for i in knobs.size():
			target_graph.set_phase_degrees(i, randf_range(0.0, 720.0))
		_update_match()
		if _errors.all(func(e: float) -> bool: return e > tolerance * 2.5):
			break


func _update_match() -> void:
	var percent_sum := 0.0
	var dots := ""
	_all_matched = true
	for i in knobs.size():
		var error := player_graph.distance_to(target_graph, i)
		_errors[i] = error
		percent_sum += clampf(1.0 - error / MAX_ERROR, 0.0, 1.0)
		var matched := error <= tolerance
		_all_matched = _all_matched and matched
		var color := "#" + target_graph.line_colors[i].to_html(false) if matched else UNMATCHED_DOT_COLOR
		dots += "[color=%s]●[/color] " % color

	var percent := int(round(percent_sum / knobs.size() * 100.0))
	status.text = "[center]Match\n[font_size=40]%d%%[/font_size]\n[font_size=28]%s[/font_size][/center]" % [percent, dots]


func _solve() -> void:
	_solved = true
	solved.emit()

	status.text = "[center][wave amp=8.0 freq=6.0][color=#ffd84a][b][font_size=28]MATCHED![/font_size][/b][/color][/wave][/center]"
	status.scale = Vector2(0.4, 0.4)
	if _status_tween:
		_status_tween.kill()
	_status_tween = create_tween()
	_status_tween.tween_property(status, "scale", Vector2.ONE, 0.45) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(next_round_delay, false).timeout
	if is_inside_tree():
		_new_round()

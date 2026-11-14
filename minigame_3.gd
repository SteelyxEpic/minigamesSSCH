extends Control
## Lunar dust collector: find the belt that carries dust, move the sticky plate over it,
## and hold the left mouse button to extend the plate and pick the dust up.

signal solved

class Speck:
	var pos := Vector2.ZERO
	var radius := 4.0
	var stuck := false
	var offset := Vector2.ZERO  # position on the plate once stuck, as a fraction of its size

@export var dust_goal := 10
@export var belt_speed := 140.0
## Seconds the plate takes to fully extend.
@export var extend_time := 0.2
@export var next_round_delay := 1.6

const BELT_COUNT := 3
const BELT_LEFT := 40.0
const BELT_WIDTH := 900.0
const BELT_TOP := 110.0
const BELT_HEIGHT := 70.0
const BELT_GAP := 30.0
const RAIL_Y := 70.0
const PLATE_SIZE := Vector2(110.0, 70.0)
const DUST_PER_BELT := 24
const PEBBLES_PER_BELT := 6
const STRIPE_SPACING := 40.0
## How far the plate must be extended before it picks anything up.
const STICK_EXTENSION := 0.8

const DUST_COLOR := Color("d9b98a")
const PEBBLE_COLOR := Color("73737f")

var _specks: Array = []  # one Array[Speck] per belt
var _speeds: Array[float] = []
var _scroll: Array[float] = []
var _dust_belt := 0
var _collected := 0
var _done := false
var _plate_pos := Vector2(490.0, 240.0)
var _extension := 0.0
var _hint_tween: Tween

@onready var stage: Control = $Stage
@onready var hint: RichTextLabel = $Stage/Hint


func _ready() -> void:
	hint.pivot_offset = hint.size / 2.0
	_new_round()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return

	for b in BELT_COUNT:
		_scroll[b] = fposmod(_scroll[b] + _speeds[b] * delta, BELT_WIDTH)
		for speck: Speck in _specks[b]:
			if speck.stuck:
				continue
			speck.pos.x += _speeds[b] * delta
			if speck.pos.x > BELT_LEFT + BELT_WIDTH:
				speck.pos = Vector2(BELT_LEFT, _random_belt_y(b))

	var mouse := stage.get_local_mouse_position()
	var inside := Rect2(Vector2.ZERO, stage.size).has_point(mouse)
	if inside:
		_plate_pos = Vector2(
				clampf(mouse.x, PLATE_SIZE.x / 2.0, stage.size.x - PLATE_SIZE.x / 2.0),
				clampf(mouse.y, RAIL_Y + PLATE_SIZE.y / 2.0 + 10.0, stage.size.y - 100.0))

	var pressing := inside and not _done and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_extension = move_toward(_extension, 1.0 if pressing else 0.0, delta / extend_time)
	if _extension >= STICK_EXTENSION and not _done:
		_collect()

	queue_redraw()


func _new_round() -> void:
	_done = false
	_collected = 0
	_extension = 0.0
	_dust_belt = randi() % BELT_COUNT
	_specks.clear()
	_speeds.clear()
	_scroll.clear()

	for b in BELT_COUNT:
		var is_dust := b == _dust_belt
		var list: Array[Speck] = []
		for i in (DUST_PER_BELT if is_dust else PEBBLES_PER_BELT):
			var speck := Speck.new()
			speck.pos = Vector2(BELT_LEFT + randf() * BELT_WIDTH, _random_belt_y(b))
			speck.radius = randf_range(2.5, 4.5) if is_dust else randf_range(5.0, 8.0)
			list.append(speck)
		_specks.append(list)
		_speeds.append(belt_speed if is_dust else belt_speed * randf_range(0.6, 1.4))
		_scroll.append(0.0)

	if _hint_tween:
		_hint_tween.kill()
	hint.scale = Vector2.ONE
	hint.text = "[center][font_size=28]Find the belt[/font_size]\n" \
			+ "[font_size=16]Move the sticky plate over the dust and hold the left mouse button[/font_size][/center]"


func _random_belt_y(belt: int) -> float:
	var top := _belt_top(belt)
	return randf_range(top + 10.0, top + BELT_HEIGHT - 10.0)


func _belt_top(belt: int) -> float:
	return BELT_TOP + belt * (BELT_HEIGHT + BELT_GAP)


func _plate_rect() -> Rect2:
	var plate_size := PLATE_SIZE * (1.0 + 0.3 * _extension)
	return Rect2(_plate_pos - plate_size / 2.0, plate_size)


func _collect() -> void:
	var rect := _plate_rect()
	for speck: Speck in _specks[_dust_belt]:
		if not speck.stuck and rect.has_point(speck.pos):
			speck.stuck = true
			# Stored as a fraction of the plate size so it stays on the plate as it resizes.
			speck.offset = (speck.pos - _plate_pos) / rect.size
			_collected += 1
	if _collected >= dust_goal:
		_finish()


func _finish() -> void:
	_done = true
	solved.emit()

	hint.text = "[center][wave amp=6.0 freq=6.0][color=#ffd84a][b][font_size=30]Sample collected![/font_size][/b][/color][/wave][/center]"
	hint.scale = Vector2(0.5, 0.5)
	if _hint_tween:
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_property(hint, "scale", Vector2.ONE, 0.45) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(next_round_delay).timeout
	if is_inside_tree():
		_new_round()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.09, 0.09, 0.12))
	# Everything below is laid out in the centered stage's coordinates.
	draw_set_transform(stage.position)

	# Belts: dark body with stripes that scroll with the belt.
	for b in BELT_COUNT:
		var top := _belt_top(b)
		draw_rect(Rect2(BELT_LEFT, top, BELT_WIDTH, BELT_HEIGHT), Color(0.2, 0.21, 0.26))
		for i in int(BELT_WIDTH / STRIPE_SPACING):
			var x := BELT_LEFT + fposmod(_scroll[b] + i * STRIPE_SPACING, BELT_WIDTH)
			draw_line(Vector2(x, top), Vector2(x, top + BELT_HEIGHT), Color(0.13, 0.14, 0.18), 3.0)
		draw_rect(Rect2(BELT_LEFT, top, BELT_WIDTH, BELT_HEIGHT), Color(0.45, 0.47, 0.55), false, 2.0)

		for speck: Speck in _specks[b]:
			if not speck.stuck:
				draw_circle(speck.pos, speck.radius, DUST_COLOR if b == _dust_belt else PEBBLE_COLOR)

	# Rail, arm and sticky plate.
	var rect := _plate_rect()
	draw_rect(Rect2(BELT_LEFT, RAIL_Y - 5.0, BELT_WIDTH, 10.0), Color(0.4, 0.42, 0.5))
	draw_line(Vector2(_plate_pos.x, RAIL_Y), Vector2(_plate_pos.x, rect.position.y), Color(0.6, 0.62, 0.7), 8.0)
	draw_rect(Rect2(_plate_pos.x - 14.0, RAIL_Y - 10.0, 28.0, 20.0), Color(0.7, 0.72, 0.8))
	if _extension > 0.0:  # shadow grows as the plate drops toward the belt
		draw_rect(Rect2(rect.position + Vector2(6.0, 8.0) * _extension, rect.size), Color(0, 0, 0, 0.35 * _extension))
	var plate_color := Color("ffcf40").lerp(Color("fff08a"), _extension)
	draw_rect(rect, plate_color)
	draw_rect(rect, Color(0.5, 0.35, 0.0), false, 3.0)

	for speck: Speck in _specks[_dust_belt]:
		if speck.stuck:
			draw_circle(_plate_pos + speck.offset * rect.size, speck.radius, DUST_COLOR.darkened(0.15))

	# Progress.
	var bar := Rect2(BELT_LEFT, stage.size.y - 40.0, BELT_WIDTH, 16.0)
	draw_rect(bar, Color(0.15, 0.16, 0.2))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(_collected) / dust_goal, bar.size.y)), DUST_COLOR)
	draw_rect(bar, Color(0.45, 0.47, 0.55), false, 2.0)
	draw_string(font, bar.position + Vector2(0.0, -6.0), "Dust collected: %d / %d" % [_collected, dust_goal],
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(1, 1, 1, 0.8))

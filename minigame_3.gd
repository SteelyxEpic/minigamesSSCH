extends Control
## Lunar dust collector: find the belt that carries dust, move the vacuum over it,
## and hold the left mouse button to lower the sticky pad and pick the dust up.

signal solved

class Speck:
	var pos := Vector2.ZERO
	var radius := 4.0
	var stuck := false
	var offset := Vector2.ZERO  # position relative to the pad's center once stuck

## Kind of mission data a success produces (see MissionDataService).
@export var data_category := "dust"
@export var dust_goal := 10
@export var belt_speed := 140.0
## Seconds the pad takes to fully extend.
@export var extend_time := 0.2
@export var next_round_delay := 1.6

## conveyor.asprite.png: a repeating 24x24 belt tile.
const CONVEYOR := preload("res://conveyor.asprite.png")
## vacuum.aseprites.png (24x131): a thin shaft at the top, a short neck, then the 24x24 sticky pad.
const VACUUM := preload("res://vacuum.aseprites.png")

const SPRITE_SCALE := 3.0
const TILE := 24.0
const TILE_PX := TILE * SPRITE_SCALE
const SHAFT_SLICE_ROW := 60  # any row inside the shaft; it is stretched to the length needed
const NECK_ROW := 100  # first row of the neck, just above the pad
const PAD_ROW := 107  # first row of the sticky pad
const VACUUM_ROWS := 131
const NECK_PX := (PAD_ROW - NECK_ROW) * SPRITE_SCALE
const PAD_SIZE := Vector2(TILE, TILE) * SPRITE_SCALE
## How far the pad drops toward the belt when extended.
const PAD_DROP := 12.0

const BELT_COUNT := 3
const BELT_WIDTH := TILE_PX * 12.0
const BELT_LEFT := (980.0 - BELT_WIDTH) / 2.0
const BELT_TOP := 110.0
const BELT_HEIGHT := TILE_PX
const BELT_GAP := 24.0
const RAIL_Y := 70.0
const DUST_PER_BELT := 24
const PEBBLES_PER_BELT := 6
## How far the pad must be extended before it picks anything up.
const STICK_EXTENSION := 0.8

const DUST_COLOR := Color("d9b98a")
const PEBBLE_COLOR := Color("73737f")

var _specks: Array = []  # one Array[Speck] per belt
var _speeds: Array[float] = []
var _scroll: Array[float] = []
var _dust_belt := 0
var _collected := 0
var _done := false
var _plate_pos := Vector2(490.0, 240.0)  # where the pad sits when retracted
var _extension := 0.0
var _hint_tween: Tween

@onready var stage: Control = $Stage
@onready var hint: RichTextLabel = $Stage/Hint


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # keep the pixel art sharp
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
				clampf(mouse.x, PAD_SIZE.x / 2.0, stage.size.x - PAD_SIZE.x / 2.0),
				clampf(mouse.y, RAIL_Y + NECK_PX + PAD_SIZE.y / 2.0 + 6.0, stage.size.y - 100.0))

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
			speck.radius = randf_range(3.0, 5.0) if is_dust else randf_range(6.0, 9.0)
			list.append(speck)
		_specks.append(list)
		_speeds.append(belt_speed if is_dust else belt_speed * randf_range(0.6, 1.4))
		_scroll.append(0.0)

	if _hint_tween:
		_hint_tween.kill()
	hint.scale = Vector2.ONE
	hint.text = "[center][font_size=28]Find the belt[/font_size]\n" \
			+ "[font_size=16]Move the vacuum over the dust and hold the left mouse button[/font_size][/center]"


func _random_belt_y(belt: int) -> float:
	var top := _belt_top(belt)
	return randf_range(top + 14.0, top + BELT_HEIGHT - 14.0)


func _belt_top(belt: int) -> float:
	return BELT_TOP + belt * (BELT_HEIGHT + BELT_GAP)


## Center of the sticky pad, which drops a little as the vacuum extends.
func _pad_center() -> Vector2:
	return _plate_pos + Vector2(0.0, PAD_DROP * _extension)


func _pad_rect() -> Rect2:
	return Rect2(_pad_center() - PAD_SIZE / 2.0, PAD_SIZE)


func _collect() -> void:
	var rect := _pad_rect()
	var center := _pad_center()
	for speck: Speck in _specks[_dust_belt]:
		if not speck.stuck and rect.has_point(speck.pos):
			speck.stuck = true
			speck.offset = speck.pos - center
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

	await get_tree().create_timer(next_round_delay, false).timeout
	if is_inside_tree():
		_new_round()


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.09, 0.09, 0.12))
	# Everything below is laid out in the centered stage's coordinates.
	draw_set_transform(stage.position)

	for b in BELT_COUNT:
		_draw_belt(b)
		for speck: Speck in _specks[b]:
			if not speck.stuck:
				draw_circle(speck.pos, speck.radius, DUST_COLOR if b == _dust_belt else PEBBLE_COLOR)

	_draw_vacuum()

	# Progress.
	var bar := Rect2(BELT_LEFT, stage.size.y - 40.0, BELT_WIDTH, 16.0)
	draw_rect(bar, Color(0.15, 0.16, 0.2))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(_collected) / dust_goal, bar.size.y)), DUST_COLOR)
	draw_rect(bar, Color(0.45, 0.47, 0.55), false, 2.0)
	draw_string(font, bar.position + Vector2(0.0, -6.0), "Dust collected: %d / %d" % [_collected, dust_goal],
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(1, 1, 1, 0.8))


## Tiles the 24x24 belt sprite along the belt and scrolls it, cropping at both ends.
func _draw_belt(belt: int) -> void:
	var top := _belt_top(belt)
	var offset := fposmod(_scroll[belt], TILE_PX)
	var belt_right := BELT_LEFT + BELT_WIDTH
	for i in range(-1, int(BELT_WIDTH / TILE_PX) + 1):
		var tile_x := BELT_LEFT + i * TILE_PX + offset
		var left := maxf(tile_x, BELT_LEFT)
		var right := minf(tile_x + TILE_PX, belt_right)
		if right <= left:
			continue
		draw_texture_rect_region(CONVEYOR,
				Rect2(left, top, right - left, TILE_PX),
				Rect2((left - tile_x) / SPRITE_SCALE, 0.0, (right - left) / SPRITE_SCALE, TILE))


## Rail, then the vacuum: a stretched shaft from the rail down to the neck and sticky pad.
func _draw_vacuum() -> void:
	var rect := _pad_rect()
	var neck_top := rect.position.y - NECK_PX

	draw_rect(Rect2(BELT_LEFT, RAIL_Y - 5.0, BELT_WIDTH, 10.0), Color(0.4, 0.42, 0.5))

	var shaft_length := neck_top - RAIL_Y
	if shaft_length > 0.0:
		draw_texture_rect_region(VACUUM,
				Rect2(rect.position.x, RAIL_Y, PAD_SIZE.x, shaft_length),
				Rect2(0.0, SHAFT_SLICE_ROW, TILE, 1.0))
	draw_texture_rect_region(VACUUM,
			Rect2(rect.position.x, neck_top, PAD_SIZE.x, NECK_PX + PAD_SIZE.y),
			Rect2(0.0, NECK_ROW, TILE, VACUUM_ROWS - NECK_ROW))

	var center := _pad_center()
	for speck: Speck in _specks[_dust_belt]:
		if speck.stuck:
			draw_circle(center + speck.offset, speck.radius, DUST_COLOR.darkened(0.15))

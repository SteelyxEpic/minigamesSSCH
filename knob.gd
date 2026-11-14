class_name Knob
extends Control
## A knob the player spins by clicking and dragging around its center.

## Emitted whenever the knob turns. `total_degrees` is cumulative (not wrapped to 360).
signal turned(total_degrees: float)

@export_group("Look")
@export var body_color := Color("3a4452")
@export var body_color_active := Color("4b586b")
@export var rim_color := Color("9fb0c4")
@export var pointer_color := Color("ffd84a")
@export var tick_count := 12

## Cumulative rotation in degrees. 0 points straight up; positive is clockwise.
var angle_degrees := 0.0:
	set(value):
		angle_degrees = value
		queue_redraw()

var _dragging := false
var _last_mouse_angle := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(120.0, 120.0)
	mouse_default_cursor_shape = Control.CURSOR_DRAG


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _is_on_knob(event.position):
			_dragging = true
			_last_mouse_angle = _mouse_angle(event.position)
			queue_redraw()
			accept_event()
		elif not event.pressed and _dragging:
			_dragging = false
			queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mouse_angle := _mouse_angle(event.position)
		# angle_difference handles the wrap at +/-180 degrees.
		angle_degrees += rad_to_deg(angle_difference(_last_mouse_angle, mouse_angle))
		_last_mouse_angle = mouse_angle
		turned.emit(angle_degrees)
		accept_event()


func _draw() -> void:
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0 - 4.0

	draw_circle(center, radius, body_color_active if _dragging else body_color)
	draw_arc(center, radius, 0.0, TAU, 64, rim_color, 4.0, true)

	# Ticks rotate with the knob so the spin is visible even without the pointer.
	for i in tick_count:
		var dir := Vector2.UP.rotated(deg_to_rad(angle_degrees) + TAU * i / tick_count)
		draw_line(center + dir * radius * 0.78, center + dir * radius * 0.92, rim_color, 2.0, true)

	var pointer_dir := Vector2.UP.rotated(deg_to_rad(angle_degrees))
	draw_line(center, center + pointer_dir * radius * 0.7, pointer_color, 5.0, true)
	draw_circle(center, radius * 0.1, pointer_color)


func _is_on_knob(point: Vector2) -> bool:
	var radius := minf(size.x, size.y) / 2.0
	return point.distance_to(size / 2.0) <= radius


func _mouse_angle(point: Vector2) -> float:
	return (point - size / 2.0).angle()

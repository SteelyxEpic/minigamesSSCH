class_name WaveGraph
extends Control
## Draws three wave lines. Each line's phase is driven by one knob.
##
## Line 1: sine plus a third harmonic (a squarish wave).
## Line 2: cosine with a slow amplitude envelope (it swells and fades).
## Line 3: sine whose phase wobbles with a second wave (it stretches and squeezes).

@export_group("Look")
@export var line_colors: Array[Color] = [
	Color("ff5a5a"),
	Color("5aff80"),
	Color("66a6ff"),
]
@export var background_color := Color(0.08, 0.1, 0.14, 0.95)
@export var grid_color := Color(1.0, 1.0, 1.0, 0.08)
@export var axis_color := Color(1.0, 1.0, 1.0, 0.3)
@export var line_width := 3.0

@export var title := ""

@export_group("Graph")
## Number of points per line.
@export var samples := 200
## How much of the x axis is shown, in radians.
@export var x_span := TAU * 2.0

const LINE_COUNT := 3
## Tallest value any line can reach; used to scale the plot to the control.
const MAX_AMPLITUDE := 1.3

var _phases: Array[float] = [0.0, 0.0, 0.0]  # radians


func _init() -> void:
	custom_minimum_size = Vector2(300.0, 150.0)


## Sets the phase of one line from a knob angle in degrees.
func set_phase_degrees(line: int, degrees: float) -> void:
	if line < 0 or line >= LINE_COUNT:
		return
	_phases[line] = deg_to_rad(degrees)
	queue_redraw()


## Root-mean-square difference between one line of this graph and the same line of `other`.
func distance_to(other: WaveGraph, line: int) -> float:
	const CHECK_POINTS := 96
	var total := 0.0
	for s in CHECK_POINTS:
		var x := x_span * s / CHECK_POINTS
		var diff := wave_value(line, x) - other.wave_value(line, x)
		total += diff * diff
	return sqrt(total / CHECK_POINTS)


## Value of line `line` at `x`, in the range [-MAX_AMPLITUDE, MAX_AMPLITUDE].
func wave_value(line: int, x: float) -> float:
	var phase := _phases[line]
	match line:
		0:
			return sin(x + phase) + 0.3 * sin(3.0 * x + phase * 3.0)
		1:
			return cos(x + phase) * cos(0.25 * x + phase * 0.5)
		_:
			return sin(x + phase + 0.8 * sin(2.0 * x))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background_color)

	# Grid and center axis.
	for i in range(1, 8):
		var gx := size.x * i / 8.0
		draw_line(Vector2(gx, 0.0), Vector2(gx, size.y), grid_color, 1.0)
	for i in range(1, 4):
		var gy := size.y * i / 4.0
		draw_line(Vector2(0.0, gy), Vector2(size.x, gy), axis_color if i == 2 else grid_color, 1.0)

	var half_height := size.y / 2.0 * 0.92
	for line in LINE_COUNT:
		var points := PackedVector2Array()
		for s in samples + 1:
			var t := float(s) / samples
			var value := wave_value(line, t * x_span)
			points.append(Vector2(t * size.x, size.y / 2.0 - value / MAX_AMPLITUDE * half_height))
		draw_polyline(points, line_colors[line], line_width, true)

	draw_rect(Rect2(Vector2.ZERO, size), axis_color, false, 2.0)
	if not title.is_empty():
		draw_string(get_theme_default_font(), Vector2(10.0, 20.0), title,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(1.0, 1.0, 1.0, 0.6))

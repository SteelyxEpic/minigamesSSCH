class_name ClockService
extends Service
## In-game clock shown at the bottom left of the screen.
## By default 1 game hour passes every 2 real minutes.

## Emitted when the game hour changes. `hour` is 0 to 23.
signal hour_changed(hour: int)
## Emitted when a new day starts. The first day is day 1.
signal day_changed(day: int)

## Real seconds that make up one game hour (120 = 1 hour per 2 minutes).
@export var real_seconds_per_game_hour := 120.0
## Hour of day 1 the clock starts at.
@export_range(0.0, 24.0, 0.25) var start_hour := 8.0

## Hours elapsed since 00:00 on day 1.
var game_hours := 0.0

@onready var label: Label = $UI/Label


func _ready() -> void:
	game_hours = start_hour
	_update_label()


func _process(delta: float) -> void:
	if real_seconds_per_game_hour <= 0.0:
		return
	var previous_hours := game_hours
	game_hours += delta / real_seconds_per_game_hour

	if int(game_hours) != int(previous_hours):
		hour_changed.emit(get_hour())
	if int(game_hours / 24.0) != int(previous_hours / 24.0):
		day_changed.emit(get_day())
	_update_label()


func get_day() -> int:
	return int(game_hours / 24.0) + 1


func get_hour() -> int:
	return int(game_hours) % 24


func get_minute() -> int:
	return int((game_hours - floorf(game_hours)) * 60.0)


func _update_label() -> void:
	var text := "Day %d  %02d:%02d" % [get_day(), get_hour(), get_minute()]
	if label.text != text:
		label.text = text

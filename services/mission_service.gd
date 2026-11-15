class_name MissionService
extends Service
## Owns the mission's HUD pieces and its payout: the RETURN button at the bottom middle while
## a mission is running, the mission report in the center of the screen, and the player's funds.
##
## It does not start or stop anything else. It only emits `return_requested` and
## `new_mission_requested`, and main.gd reacts to them.

## RETURN was pressed.
signal return_requested
## The report was dismissed and the player wants to plan another mission.
signal new_mission_requested
## RETRY was pressed on the death screen.
signal retry_requested

enum Phase { PLANNING, ACTIVE, REPORT, DEAD }

## What the death screen says for each resource that ran out.
const DEATH_CAUSES := {
	"Oxygen": "You ran out of oxygen.",
	"Food": "You starved.",
	"Water": "You died of thirst.",
}

## Points awarded per item of each kind of data (the keys match MissionDataService.CATEGORIES).
const POINTS_PER_ITEM := {
	"lidar": 10,
	"dust": 8,
	"radiation": 12,
	"minerals": 6,
}
const DEFAULT_POINTS := 5
const GOLD := Color("ffd84a")
const MUTED := Color(1.0, 1.0, 1.0, 0.6)

@export_group("Funds")
## Money the player begins the game with.
@export var starting_funds := 15000
## Before planning a mission, funds are topped up to at least this much (a grant from the
## space agency), so the player can always afford the cheapest mission.
@export var minimum_funds := 8000

@export_group("Payout")
## Money received for each point.
@export var money_per_point := 100
## Every different kind of data after the first multiplies the data points by this much more,
## so a varied mission pays much more than one repeated experiment.
@export_range(0.0, 2.0, 0.05) var diversity_bonus_per_type := 0.5
## Extra points when the Delta-V budget was close to the minimum (see the Mission Planner).
@export var efficient_bonus_points := 25

var phase := Phase.PLANNING
var funds := 0
var grant := 0  # money added by the last top-up, 0 if none

var _params: Dictionary = {}

@onready var return_button: Button = $UI/ReturnButton
@onready var funds_label: Label = $UI/FundsLabel
@onready var status_label: Label = $UI/StatusLabel
@onready var report: PanelContainer = $UI/Report
@onready var rows: GridContainer = $UI/Report/Margin/Box/Rows
@onready var new_mission_button: Button = $UI/Report/Margin/Box/NewMissionButton
@onready var death_screen: Control = $UI/DeathScreen
@onready var death_cause: Label = $UI/DeathScreen/Panel/Margin/Box/Cause
@onready var retry_button: Button = $UI/DeathScreen/Panel/Margin/Box/RetryButton


func _ready() -> void:
	funds = starting_funds
	# Same panel look as the tool windows.
	report.add_theme_stylebox_override("panel", report.get_theme_stylebox("panel", "Panel"))
	return_button.pressed.connect(_on_return_pressed)
	new_mission_button.pressed.connect(new_mission_requested.emit)
	retry_button.pressed.connect(retry_requested.emit)
	_update_funds()
	go_to_planning()


## Back to planning: no RETURN button, no report.
func go_to_planning() -> void:
	phase = Phase.PLANNING
	_params = {}
	grant = maxi(minimum_funds - funds, 0)
	funds += grant
	_update_funds()
	return_button.visible = false
	report.visible = false
	death_screen.visible = false
	set_status("")


## Locks or unlocks the RETURN button (it is locked while Mooner is away on the Moon).
func set_return_locked(locked: bool) -> void:
	return_button.disabled = locked
	return_button.tooltip_text = "Wait for Mooner to return" if locked else ""


## A line of text above the RETURN button, e.g. when Mooner is due back. Empty hides it.
func set_status(text: String) -> void:
	status_label.text = text
	status_label.visible = not text.is_empty()


## RETURN is disabled right away so the leave sound can't be triggered twice.
func _on_return_pressed() -> void:
	return_button.disabled = true
	return_requested.emit()


## The player ran out of `resource_name` during the mission: show the death screen.
func die(resource_name: String) -> void:
	phase = Phase.DEAD
	return_button.visible = false
	report.visible = false
	death_cause.text = DEATH_CAUSES.get(resource_name, "You did not survive.")
	death_screen.visible = true


## A mission was launched with these settings (from the Mission Planner).
func begin(params: Dictionary) -> void:
	phase = Phase.ACTIVE
	_params = params
	funds -= int(params.get("cost", 0))
	_update_funds()
	return_button.disabled = false
	return_button.visible = true
	report.visible = false
	death_screen.visible = false


## Hides RETURN, works out the payout from the collected data, and shows the report.
## `counts` is {data category: items collected}.
func show_report(counts: Dictionary, elapsed_hours: float) -> void:
	phase = Phase.REPORT
	return_button.visible = false
	for child in rows.get_children():
		child.queue_free()

	var data_points := 0
	var types := 0
	for category: String in MissionDataService.CATEGORIES:
		var count := int(counts.get(category, 0))
		var points := count * int(POINTS_PER_ITEM.get(category, DEFAULT_POINTS))
		data_points += points
		if count > 0:
			types += 1
		_add_row("%s: %d" % [MissionDataService.CATEGORIES[category], count], "+%d pts" % points,
				Color.WHITE if count > 0 else MUTED)

	var type_total := MissionDataService.CATEGORIES.size()
	var multiplier := 1.0 + diversity_bonus_per_type * maxi(types - 1, 0)
	var scaled_points := int(round(data_points * multiplier))

	_add_separator()
	_add_row("Diversity: %d of %d data types" % [types, type_total], "x%.2f" % multiplier,
			GOLD if types > 1 else MUTED)
	_add_row("Data points", "%d" % scaled_points)

	var bonus := 0
	if _params.get("efficient", false):
		bonus = efficient_bonus_points
		_add_row("Efficient trajectory (Delta-V %.2f km/s)" % float(_params.get("delta_v", 0.0)),
				"+%d pts" % bonus, GOLD)

	var days := int(elapsed_hours / 24.0)
	var hours := int(elapsed_hours) % 24
	_add_row("Mission length", "%dd %dh" % [days, hours], MUTED)

	var total_points := scaled_points + bonus
	var money := total_points * money_per_point
	funds += money

	_add_separator()
	_add_row("TOTAL POINTS", "%d" % total_points, Color.WHITE, 16)
	_add_row("MONEY RECEIVED", format_money(money), GOLD, 20)

	# The mission's cost was already paid at launch; show it against what the data earned.
	var cost := int(_params.get("cost", 0))
	var net := money - cost
	_add_row("Mission cost", "-" + format_money(cost), Color("ff8a8a"))
	_add_row("NET PROFIT" if net >= 0 else "NET LOSS", format_money(net),
			Color("4aff7a") if net >= 0 else Color("ff4a4a"), 16)
	_add_row("Total funds", format_money(funds), MUTED)

	_update_funds()
	report.visible = true


func _add_row(left: String, right: String, color := Color.WHITE, font_size := 14) -> void:
	var left_label := Label.new()
	left_label.text = left
	left_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_label.add_theme_font_size_override("font_size", font_size)
	left_label.add_theme_color_override("font_color", color)
	rows.add_child(left_label)

	var right_label := Label.new()
	right_label.text = right
	right_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right_label.add_theme_font_size_override("font_size", font_size)
	right_label.add_theme_color_override("font_color", color)
	rows.add_child(right_label)


## A thin line across both columns.
func _add_separator() -> void:
	for i in 2:
		var separator := HSeparator.new()
		separator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_child(separator)


func _update_funds() -> void:
	funds_label.text = "Funds: %s" % format_money(funds)


## 17500 -> "$17,500"
static func format_money(amount: int) -> String:
	var digits := str(absi(amount))
	var text := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			text += ","
		text += digits[i]
	return ("-$" if amount < 0 else "$") + text

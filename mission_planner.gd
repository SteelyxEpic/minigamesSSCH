extends Control
## Mission Planner: set up the trip from Earth orbit to lunar orbit before launch.
##
##  - Power (120-300 W): how much electricity the rocket supplies.
##  - Delta-V budget (0-10 km/s): fuel for the trip. About 4.5-6.0 km/s is needed, and the
##    mission earns bonus points when the budget is close to the 4.5 minimum.
##  - Apparatus: any instrument in waste.json can be brought. Together they must fit in the
##    power budget. Instruments left behind are locked in Mission Control.
##  - Extra food and water packs to bring (0-10). Using one restores some food or water.
## Everything costs money. The total must fit in the player's funds.
## LAUNCH sends all of this out through `launch_requested`.

signal launch_requested(params: Dictionary)

const MissionControlScript := preload("res://mission_control.gd")

## waste.json categories that are not instruments.
const NOT_INSTRUMENTS := ["Spacecraft Electrical Generation Capacity"]
## button.png: two 24x24 frames, not pressed then pressed.
const BUTTON_SHEET := preload("res://button.png")
const HEADER_COLOR := Color("ffd84a")
const MUTED_COLOR := Color(1.0, 1.0, 1.0, 0.55)
const OK_COLOR := Color("4aff7a")
const NEAR_COLOR := Color("ffd84a")
const BAD_COLOR := Color("ff4a4a")

@export_group("Power")
@export var min_power := 120.0
@export var max_power := 300.0
@export var default_power := 150.0
@export var power_step := 10.0

@export_group("Delta-V (km/s)")
## The least delta-V that reaches lunar orbit. Lower budgets cannot launch.
@export var min_delta_v := 4.5
## Top of the range the trip normally needs. More than this is wasted fuel.
@export var max_needed_delta_v := 6.0
## A budget within this much above the minimum earns the efficiency bonus.
@export var efficient_window := 0.25
@export var default_delta_v := 5.0

@export_group("Extra supplies (packs)")
## Food and water are always full at launch. These are extra packs to bring, used to top up.
@export var min_supply := 0.0
@export var max_supply := 10.0
@export var default_supply := 3.0

@export_group("Prices (money)")
## Per watt of power the rocket can supply.
@export var power_cost_per_watt := 15
## Per km/s of delta-V (fuel and tank mass).
@export var fuel_cost_per_km_s := 1000
## Per extra food or water pack.
@export var food_cost_per_unit := 100
@export var water_cost_per_unit := 80
## Every instrument costs this much to build and bring, plus the per-watt amount below.
@export var instrument_base_cost := 150
@export var instrument_cost_per_watt := 40

## Always false: this tool never plays minigames. Read by MinigameService.
var playing := false

var _funds := 0
var _limited_by_funds := false

var _power_slider: HSlider
var _dv_slider: HSlider
var _food_slider: HSlider
var _water_slider: HSlider
var _payload_bar: HSlider
var _cost_bar: HSlider
var _cost_breakdown: Label
var _dv_hint: Label
var _info: Label
var _launch_button: TextureButton
var _launch_frames: Array[AtlasTexture] = []
var _checks: Array[CheckBox] = []


## Receives the player's funds when this tool opens. Runs before _ready.
func configure(params: Dictionary) -> void:
	_limited_by_funds = params.has("funds")
	_funds = int(params.get("funds", 0))


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	var title := Label.new()
	title.text = "MISSION PLANNER  -  Earth orbit to lunar orbit"
	title.add_theme_font_size_override("font_size", 18)
	root.add_child(title)

	# Sliders: power and delta-V on the left, food and water on the right.
	var settings := HBoxContainer.new()
	settings.add_theme_constant_override("separation", 20)
	root.add_child(settings)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	settings.add_child(left)
	_power_slider = _add_slider_row(left, "Power", min_power, max_power, power_step, default_power)
	_dv_slider = _add_slider_row(left, "Delta-V", 0.0, 10.0, 0.05, default_delta_v)
	_dv_hint = Label.new()
	_dv_hint.add_theme_font_size_override("font_size", 11)
	_dv_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_dv_hint)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	settings.add_child(right)
	_food_slider = _add_slider_row(right, "Extra food", min_supply, max_supply, 1.0, default_supply)
	_water_slider = _add_slider_row(right, "Extra water", min_supply, max_supply, 1.0, default_supply)

	# Gauges: the payload's power draw against the power budget, and the cost against funds.
	_payload_bar = _add_gauge_row(root, "PAYLOAD")
	_cost_bar = _add_gauge_row(root, "COST")
	_cost_breakdown = Label.new()
	_cost_breakdown.add_theme_font_size_override("font_size", 11)
	_cost_breakdown.add_theme_color_override("font_color", MUTED_COLOR)
	root.add_child(_cost_breakdown)

	var apparatus_label := Label.new()
	apparatus_label.text = "APPARATUS TO BRING  (power draw in watts, price in the tooltip)"
	apparatus_label.add_theme_font_size_override("font_size", 13)
	apparatus_label.add_theme_color_override("font_color", HEADER_COLOR)
	root.add_child(apparatus_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	_build_apparatus(grid, MissionControlScript.load_waste())

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	root.add_child(footer)
	_info = Label.new()
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.add_theme_font_size_override("font_size", 12)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_info)
	var launch_label := Label.new()
	launch_label.text = "LAUNCH"
	launch_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	launch_label.add_theme_font_size_override("font_size", 20)
	footer.add_child(launch_label)

	# The launch button is a sprite sheet of two 24x24 frames: not pressed, then pressed.
	for frame in 2:
		var atlas := AtlasTexture.new()
		atlas.atlas = BUTTON_SHEET
		atlas.region = Rect2(frame * 24, 0, 24, 24)
		_launch_frames.append(atlas)
	_launch_button = TextureButton.new()
	_launch_button.texture_normal = _launch_frames[0]
	_launch_button.texture_hover = _launch_frames[0]
	_launch_button.texture_pressed = _launch_frames[1]
	_launch_button.texture_disabled = _launch_frames[0]  # shown dimmed while launching is blocked
	_launch_button.ignore_texture_size = true
	_launch_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_launch_button.custom_minimum_size = Vector2(48.0, 48.0)
	_launch_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_launch_button.pressed.connect(_on_launch_pressed)
	footer.add_child(_launch_button)

	# Start with the first instrument of every experiment category packed.
	var packed: Array[String] = []
	for check in _checks:
		var category: String = check.get_meta("category")
		if MissionControlScript.MINIGAMES.has(category) and not packed.has(category):
			packed.append(category)
			check.button_pressed = true
	_refresh()


func _add_slider_row(parent: Control, label_text: String, min_v: float, max_v: float, step: float, value: float) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.custom_minimum_size = Vector2(88.0, 0.0)
	name_label.add_theme_font_size_override("font_size", 13)
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(120.0, 20.0)
	slider.value_changed.connect(_on_value_changed)
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(160.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 13)
	row.add_child(value_label)
	slider.set_meta("value_label", value_label)

	parent.add_child(row)
	return slider


## A read-only bar with a name on the left and a readout on the right.
func _add_gauge_row(parent: Control, label_text: String) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.custom_minimum_size = Vector2(88.0, 0.0)
	name_label.add_theme_font_size_override("font_size", 13)
	row.add_child(name_label)

	var gauge := HSlider.new()
	gauge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gauge.custom_minimum_size = Vector2(0.0, 20.0)
	gauge.step = 0.1
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.focus_mode = Control.FOCUS_NONE
	gauge.scrollable = false
	var no_knob := ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))
	for icon_name in ["grabber", "grabber_highlight", "grabber_disabled"]:
		gauge.add_theme_icon_override(icon_name, no_knob)
	row.add_child(gauge)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(190.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 13)
	row.add_child(value_label)
	gauge.set_meta("value_label", value_label)
	return gauge


## One panel per waste.json category, with a checkbox and a wattage for every instrument.
func _build_apparatus(grid: GridContainer, waste: Dictionary) -> void:
	for category: String in waste:
		if category in NOT_INSTRUMENTS:
			continue
		var instruments: Dictionary = waste[category]

		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		panel.add_theme_stylebox_override("panel", get_theme_stylebox("panel", "Panel"))
		var margin := MarginContainer.new()
		for side in ["left", "top", "right", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 8)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)

		var title := Label.new()
		title.text = category
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.add_theme_font_size_override("font_size", 13)
		title.add_theme_color_override("font_color", HEADER_COLOR)
		column.add_child(title)

		var note := Label.new()
		var runs_experiment: bool = MissionControlScript.MINIGAMES.has(category)
		note.text = "Runs: %s" % MissionControlScript.MINIGAMES[category].controls if runs_experiment \
				else "No experiment yet"
		note.add_theme_font_size_override("font_size", 11)
		note.add_theme_color_override("font_color", MUTED_COLOR)
		column.add_child(note)
		column.add_child(HSeparator.new())

		for instrument: String in instruments:
			var watts := float(instruments[instrument])
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)

			var check := CheckBox.new()
			check.text = instrument
			check.tooltip_text = "%s\n%d W   %s" % [instrument, int(watts), MissionService.format_money(instrument_price(watts))]
			check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			check.clip_text = true
			check.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			check.add_theme_font_size_override("font_size", 11)
			check.set_meta("watts", watts)
			check.set_meta("category", category)
			check.toggled.connect(_on_toggled)
			row.add_child(check)

			var cost := Label.new()
			cost.text = "%d W" % int(watts)
			cost.custom_minimum_size = Vector2(40.0, 0.0)
			cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cost.add_theme_font_size_override("font_size", 11)
			cost.add_theme_color_override("font_color", MUTED_COLOR)
			row.add_child(cost)

			column.add_child(row)
			_checks.append(check)

		margin.add_child(column)
		panel.add_child(margin)
		grid.add_child(panel)


func _on_value_changed(_value: float) -> void:
	_refresh()


func _on_toggled(_pressed: bool) -> void:
	_refresh()


# --- Prices ---

## What it costs to build and bring one instrument with this power draw.
func instrument_price(watts: float) -> int:
	return instrument_base_cost + int(round(watts * instrument_cost_per_watt))


## The mission's cost, split by what it pays for. "total" is the sum.
func _costs() -> Dictionary:
	var instruments := 0
	for check in _checks:
		if check.button_pressed:
			instruments += instrument_price(float(check.get_meta("watts", 0.0)))
	var costs := {
		"Power": int(round(_power_slider.value * power_cost_per_watt)),
		"Fuel": int(round(_dv_slider.value * fuel_cost_per_km_s)),
		"Food": int(round(_food_slider.value * food_cost_per_unit)),
		"Water": int(round(_water_slider.value * water_cost_per_unit)),
		"Instruments": instruments,
	}
	var total := 0
	for amount: int in costs.values():
		total += amount
	costs["total"] = total
	return costs


# --- Payload ---

func _brought() -> Array[String]:
	var names: Array[String] = []
	for check in _checks:
		if check.button_pressed:
			names.append(check.text)
	return names


## Combined power draw of everything brought, in watts.
func _payload() -> float:
	var watts := 0.0
	for check in _checks:
		if check.button_pressed:
			watts += float(check.get_meta("watts", 0.0))
	return watts


## True if at least one brought instrument belongs to a category that has an experiment.
func _has_experiment() -> bool:
	for check in _checks:
		if check.button_pressed and MissionControlScript.MINIGAMES.has(check.get_meta("category")):
			return true
	return false


## True when the delta-V is close enough to the minimum to earn the efficiency bonus.
func _is_efficient(delta_v: float) -> bool:
	return delta_v >= min_delta_v and delta_v <= min_delta_v + efficient_window


# --- Readouts ---

func _value_label(slider: HSlider) -> Label:
	return slider.get_meta("value_label") as Label


## Updates every readout and decides whether the mission can launch.
func _refresh() -> void:
	if _launch_button == null:
		return  # still building the interface

	var power := _power_slider.value
	var payload := _payload()
	var delta_v := _dv_slider.value
	var costs := _costs()
	var total_cost: int = costs["total"]

	_value_label(_power_slider).text = "%d W  %s" % [int(power), MissionService.format_money(costs["Power"])]
	_value_label(_dv_slider).text = "%.2f km/s  %s" % [delta_v, MissionService.format_money(costs["Fuel"])]
	_value_label(_food_slider).text = "%d packs  %s" % [int(_food_slider.value), MissionService.format_money(costs["Food"])]
	_value_label(_water_slider).text = "%d packs  %s" % [int(_water_slider.value), MissionService.format_money(costs["Water"])]

	# Payload gauge.
	_payload_bar.max_value = power
	_payload_bar.value = minf(payload, power)
	var over_power := payload > power
	_payload_bar.self_modulate = BAD_COLOR if over_power else (NEAR_COLOR if payload >= power * 0.85 else OK_COLOR)
	_set_readout(_payload_bar, "%d / %d W" % [int(payload), int(power)], over_power)

	# Cost gauge.
	var over_funds := _limited_by_funds and total_cost > _funds
	var cost_text := MissionService.format_money(total_cost)
	if _limited_by_funds:
		_cost_bar.max_value = maxf(_funds, 1)
		_cost_bar.value = minf(total_cost, _funds)
		_cost_bar.self_modulate = BAD_COLOR if over_funds else (NEAR_COLOR if total_cost >= _funds * 0.85 else OK_COLOR)
		cost_text += " / " + MissionService.format_money(_funds)
	else:
		_cost_bar.max_value = maxf(total_cost, 1)
		_cost_bar.value = total_cost
		_cost_bar.self_modulate = OK_COLOR
	_set_readout(_cost_bar, cost_text, over_funds)

	var parts: Array[String] = []
	for part: String in ["Power", "Fuel", "Food", "Water", "Instruments"]:
		parts.append("%s %s" % [part, MissionService.format_money(costs[part])])
	_cost_breakdown.text = "     ".join(parts)

	# Delta-V guidance.
	var hint_color := MUTED_COLOR
	if delta_v < min_delta_v:
		_dv_hint.text = "Too low. Earth orbit to lunar orbit needs %.1f - %.1f km/s." % [min_delta_v, max_needed_delta_v]
		hint_color = BAD_COLOR
	elif _is_efficient(delta_v):
		_dv_hint.text = "Efficient burn! Close to the %.1f km/s minimum earns bonus points." % min_delta_v
		hint_color = NEAR_COLOR
	elif delta_v <= max_needed_delta_v:
		_dv_hint.text = "Enough to reach the Moon. Closer to %.1f km/s earns bonus points." % min_delta_v
		hint_color = OK_COLOR
	else:
		_dv_hint.text = "More than the trip needs. The extra fuel is wasted."
	_dv_hint.add_theme_color_override("font_color", hint_color)

	# Launch checks.
	var problem := ""
	if delta_v < min_delta_v:
		problem = "Delta-V is too low to reach lunar orbit (needs at least %.1f km/s)." % min_delta_v
	elif over_power:
		problem = "The payload needs %d W but only %d W is available." % [int(payload), int(power)]
	elif not _has_experiment():
		problem = "Bring at least one instrument that can run an experiment."
	elif over_funds:
		problem = "Not enough funds: this mission costs %s more than you have." % MissionService.format_money(total_cost - _funds)
	_launch_button.disabled = not problem.is_empty()
	_launch_button.modulate.a = 0.45 if _launch_button.disabled else 1.0
	if problem.is_empty():
		_info.text = "Ready for launch. Anything left behind will be locked."
		_info.add_theme_color_override("font_color", OK_COLOR)
	else:
		_info.text = problem
		_info.add_theme_color_override("font_color", BAD_COLOR)


## Sets a gauge's readout text, in red when `bad`.
func _set_readout(gauge: HSlider, text: String, bad: bool) -> void:
	var label := _value_label(gauge)
	label.text = text
	if bad:
		label.add_theme_color_override("font_color", BAD_COLOR)
	else:
		label.remove_theme_color_override("font_color")


func _on_launch_pressed() -> void:
	if _launch_button.disabled:
		return
	# One launch only. The button stays down (pressed frame) while the launch sound plays.
	_launch_button.texture_disabled = _launch_frames[1]
	_launch_button.modulate.a = 1.0
	_launch_button.disabled = true
	var delta_v := _dv_slider.value
	launch_requested.emit({
		"power": _power_slider.value,
		"delta_v": delta_v,
		"efficient": _is_efficient(delta_v),
		"food": _food_slider.value,
		"water": _water_slider.value,
		"apparatus": _brought(),
		"cost": int(_costs()["total"]),
	})

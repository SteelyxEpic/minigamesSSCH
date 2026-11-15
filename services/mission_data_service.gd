class_name MissionDataService
extends Service
## Live tally of the data the player has collected through the minigames, shown in a panel
## on the right side of the screen. The counts live here for the whole mission, so closing a
## minigame window never resets them.
##
## To add a data category: add it to CATEGORIES and set `data_category` on the minigame.

## Emitted whenever a counter changes.
signal data_changed(category: String, total: int)

## category id -> text shown in the panel. Order is the display order.
const CATEGORIES := {
	"lidar": "LIDAR scans collected",
	"dust": "Dust samples collected",
	"radiation": "Radiation readings recorded",
	"minerals": "Minerals accounted for",
}
const FLASH_COLOR := Color("ffd84a")
const FLASH_TIME := 0.6

var _counts: Dictionary = {}  # category -> int
var _labels: Dictionary = {}  # category -> Label
var _flash_tweens: Dictionary = {}  # category -> Tween

@onready var panel: PanelContainer = $UI/Panel
@onready var list: VBoxContainer = $UI/Panel/Margin/Layout/List


## Called by MainSc after all services are loaded.
func bind_nodes() -> void:
	# Same panel look as the tool windows. PanelContainer uses its own style name,
	# so borrow the theme's "Panel" style for it.
	panel.add_theme_stylebox_override("panel", panel.theme.get_stylebox("panel", "Panel"))

	for category: String in CATEGORIES:
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 12)
		list.add_child(label)
		_labels[category] = label
		_counts[category] = 0
		_refresh(category)


## Adds `amount` to a category and updates the panel immediately.
func record(category: String, amount: int = 1) -> void:
	if not CATEGORIES.has(category):
		push_warning("MissionDataService: unknown data category '%s'" % category)
		return
	_counts[category] += amount
	_refresh(category)
	_flash(category)
	data_changed.emit(category, _counts[category])


func get_count(category: String) -> int:
	return _counts.get(category, 0)


func _refresh(category: String) -> void:
	(_labels[category] as Label).text = "%s: %d" % [CATEGORIES[category], _counts[category]]


## Briefly tints the label gold so a new reading is easy to notice.
func _flash(category: String) -> void:
	var label: Label = _labels[category]
	if _flash_tweens.has(category):
		(_flash_tweens[category] as Tween).kill()
	label.self_modulate = FLASH_COLOR
	var tween := create_tween()
	tween.tween_property(label, "self_modulate", Color.WHITE, FLASH_TIME)
	_flash_tweens[category] = tween

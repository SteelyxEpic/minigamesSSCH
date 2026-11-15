class_name PauseService
extends Service
## Pause button in the top right corner. Pausing freezes the whole game (the scene tree) and shows
## a translucent "PAUSED" panel. Click the play icon or press Esc to resume.
##
## This node keeps running while everything else is paused, so it can still react to input.

## Emitted when the game is paused (true) or resumed (false).
signal paused_changed(paused: bool)

## pause_and_play.png holds three 24x24 sprites in a row: pause, play, settings.
const SHEET := preload("res://pause_and_play.png")
const FRAME_SIZE := 24
const FRAME_PAUSE := 0
const FRAME_PLAY := 1
const FRAME_SETTINGS := 2  # not used yet

var _icons: Array[AtlasTexture] = []

@onready var button: TextureButton = $UI/PauseButton
@onready var overlay: Control = $UI/Overlay
@onready var panel: PanelContainer = $UI/Overlay/Panel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	for frame in 3:
		var atlas := AtlasTexture.new()
		atlas.atlas = SHEET
		atlas.region = Rect2(frame * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
		_icons.append(atlas)

	# Same panel look as the tool windows.
	panel.add_theme_stylebox_override("panel", panel.get_theme_stylebox("panel", "Panel"))

	button.pressed.connect(toggle)
	_apply(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	set_paused(not get_tree().paused)


func set_paused(paused: bool) -> void:
	if get_tree().paused == paused:
		return
	get_tree().paused = paused
	_apply(paused)
	paused_changed.emit(paused)


func _apply(paused: bool) -> void:
	# Show the action the button will perform: play while paused, pause while running.
	button.texture_normal = _icons[FRAME_PLAY if paused else FRAME_PAUSE]
	button.tooltip_text = "Resume" if paused else "Pause"
	overlay.visible = paused

extends Control
## The start menu: the game's title, a START button, and OPTIONS with SFX and voice volume.
## The sliders change the SFX and Voice audio buses through the AudioSettings autoload.

const GAME_SCENE := "res://main.tscn"
const MUSIC_PATH := "res://title.mpeg.wav"
const CLICK_SOUND := preload("res://buttonclick.mp3")

var _music: AudioStreamPlayer
var _click: AudioStreamPlayer

@onready var main_box: Control = $MainBox
@onready var start_button: Button = $MainBox/StartButton
@onready var options_button: Button = $MainBox/OptionsButton
@onready var options: PanelContainer = $Options
@onready var back_button: Button = $Options/Margin/Box/BackButton
@onready var sfx_slider: HSlider = $Options/Margin/Box/SfxRow/Slider
@onready var sfx_value: Label = $Options/Margin/Box/SfxRow/Value
@onready var voice_slider: HSlider = $Options/Margin/Box/VoiceRow/Slider
@onready var voice_value: Label = $Options/Margin/Box/VoiceRow/Value


func _ready() -> void:
	# Same panel look as the in-game windows.
	options.add_theme_stylebox_override("panel", get_theme_stylebox("panel", "Panel"))

	_click = AudioStreamPlayer.new()
	_click.stream = CLICK_SOUND
	_click.bus = AudioSettings.SFX
	add_child(_click)

	var music_stream := load(MUSIC_PATH) as AudioStream
	if music_stream:
		_music = AudioStreamPlayer.new()
		_music.stream = music_stream
		_music.bus = AudioSettings.MUSIC
		_music.finished.connect(_music.play)  # repeat
		add_child(_music)
		_music.play()

	# Sliders start at the saved volumes.
	sfx_slider.value = AudioSettings.get_volume(AudioSettings.SFX)
	voice_slider.value = AudioSettings.get_volume(AudioSettings.VOICE)
	_update_value_label(sfx_value, sfx_slider.value)
	_update_value_label(voice_value, voice_slider.value)

	sfx_slider.value_changed.connect(_on_volume_changed.bind(AudioSettings.SFX, sfx_value))
	voice_slider.value_changed.connect(_on_volume_changed.bind(AudioSettings.VOICE, voice_value))
	sfx_slider.drag_ended.connect(_on_sfx_drag_ended)
	voice_slider.drag_ended.connect(_on_voice_drag_ended)

	start_button.pressed.connect(_on_start_pressed)
	options_button.pressed.connect(_on_options_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_show_options(false)


func _show_options(open: bool) -> void:
	options.visible = open
	main_box.visible = not open


func _on_start_pressed() -> void:
	start_button.disabled = true  # only one start
	_click.play()
	await _click.finished  # let the click be heard before the scene changes
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_options_pressed() -> void:
	_click.play()
	_show_options(true)


func _on_back_pressed() -> void:
	_click.play()
	AudioSettings.save()
	_show_options(false)


func _on_volume_changed(value: float, bus: StringName, label: Label) -> void:
	AudioSettings.set_volume(bus, value)
	_update_value_label(label, value)


## Letting go of the SFX slider plays a click so the new volume can be heard.
func _on_sfx_drag_ended(_value_changed: bool) -> void:
	AudioSettings.save()
	_click.play()


func _on_voice_drag_ended(_value_changed: bool) -> void:
	AudioSettings.save()


func _update_value_label(label: Label, value: float) -> void:
	label.text = "%d%%" % int(round(value * 100.0))

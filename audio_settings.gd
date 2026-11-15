extends Node
## Autoload that remembers the player's volume choices and applies them to the audio buses
## (see default_bus_layout.tres: Master, Music, SFX, Voice). Volumes are saved to disk and
## applied at startup, so they hold in every scene.

const MUSIC := &"Music"
const SFX := &"SFX"
const VOICE := &"Voice"

const SAVE_PATH := "user://settings.cfg"
const SECTION := "audio"

## Volume (0 to 1) of each bus the player can adjust.
var _volumes := {
	SFX: 1.0,
	VOICE: 1.0,
}


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		for bus: StringName in _volumes:
			_volumes[bus] = clampf(float(config.get_value(SECTION, String(bus), 1.0)), 0.0, 1.0)
	for bus: StringName in _volumes:
		_apply(bus)


## Volume of a bus from 0 (silent) to 1 (full).
func get_volume(bus: StringName) -> float:
	return _volumes.get(bus, 1.0)


## Sets and applies a bus volume. Call save() when the player has finished adjusting.
func set_volume(bus: StringName, volume: float) -> void:
	_volumes[bus] = clampf(volume, 0.0, 1.0)
	_apply(bus)


func save() -> void:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)  # keep any other settings already in the file
	for bus: StringName in _volumes:
		config.set_value(SECTION, String(bus), _volumes[bus])
	config.save(SAVE_PATH)


func _apply(bus: StringName) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index == -1:
		push_warning("AudioSettings: no audio bus named '%s'" % bus)
		return
	var volume: float = _volumes[bus]
	AudioServer.set_bus_mute(index, volume <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))

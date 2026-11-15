extends MainSc
## Connects the services to each other and runs the mission flow. MainSc automatically connects
## every service signal to a method named `_on_<servicename>_<signal>` (service name in
## lowercase), so the handlers below are the only glue needed. Services never reference each other.
##
## Flow:  planning  ->  launch  ->  mission running  ->  RETURN  ->  report  ->  planning again
##                                                   \->  ran out of a resource  ->  death screen  ->  planning

const TOOL_PLANNER := "Mission Planner"
const TOOL_CONTROL := "Mission Control"

const LAUNCH_SOUND := preload("res://enter.mp3")
const RETURN_SOUND := preload("res://leave.mp3")
const DEATH_SOUND := preload("res://death.mp3")

## Background music for the Mission Control area (the file main.mpeg converted to .wav).
const MUSIC_PATH := "res://main.mpeg.wav"
const MUSIC_VOLUME_DB := -8.0

## True while the launch or return sound is playing. Nothing else about the mission changes
## until the sound has finished.
var _busy := false
var _music: AudioStreamPlayer
var _music_wanted := false
var _director: IntroDirector

## Play the opening story (intro.dialogue) when the game starts. Turn off to go straight to planning.
@export var play_intro := true


func _ready() -> void:
	# The director covers the screen first, so create it before anything else is shown.
	_director = IntroDirector.new()
	_director.main = self
	add_child(_director)

	super._ready()
	# The music file is large, so start loading it now. It is ready by the time of the first launch.
	if ResourceLoader.exists(MUSIC_PATH):
		ResourceLoader.load_threaded_request(MUSIC_PATH)

	if play_intro:
		_start_intro()
	else:
		begin_planning()


## The opening story: no tools yet, then Mooner talks to the player.
func _start_intro() -> void:
	var mission := get_service("MissionService") as MissionService
	if mission:
		mission.go_to_planning()
	var minigames := get_service("MinigameService") as MinigameService
	if minigames:
		minigames.set_available_tools([])
	_director.run_intro()


## Only the Mission Planner is available. Nothing is depleting yet.
func begin_planning() -> void:
	var mission := get_service("MissionService") as MissionService
	if mission:
		mission.go_to_planning()
	var minigames := get_service("MinigameService") as MinigameService
	if minigames:
		# The planner needs to know how much money the player has.
		minigames.set_mission_params({"funds": mission.funds} if mission else {})
		minigames.set_available_tools([TOOL_PLANNER])
		minigames.open_minigame(TOOL_PLANNER)


## The planner's LAUNCH button. The launch sound plays in full first. Then the planner
## disappears, Mission Control takes its place, and food, water and oxygen are set up and
## start depleting.
func _on_minigameservice_tool_launch_requested(params: Dictionary) -> void:
	if _busy:
		return
	_busy = true
	await _play_sound(LAUNCH_SOUND)
	var story := _director.story_active
	if story:
		await _director.cards_begin()  # the title card; the mission begins behind it

	var mission := get_service("MissionService") as MissionService
	var minigames := get_service("MinigameService") as MinigameService
	var resources := get_service("ResourcesService") as ResourcesService
	var clock := get_service("ClockService") as ClockService
	var data := get_service("MissionDataService") as MissionDataService

	if mission:
		mission.begin(params)
	if data:
		data.reset()
	if clock:
		clock.restart()
	if resources:
		# Food, water and oxygen start full. "food" and "water" are the extra packs brought.
		resources.start_mission(int(params.get("food", 0)), int(params.get("water", 0)))
	if minigames:
		minigames.set_mission_params(params)
		minigames.set_available_tools([TOOL_CONTROL])
		minigames.open_minigame(TOOL_CONTROL)
	_start_music()
	if story:
		_director.on_mission_launched(params)
		await _director.cards_end()
		_director.notify_launched()  # the conversation continues: Mooner heads off
	_busy = false


## RETURN. The leave sound plays in full first. Then Mission Control is hidden, the three
## values reset, and the report appears.
func _on_missionservice_return_requested() -> void:
	if _busy:
		return
	_busy = true
	await _play_sound(RETURN_SOUND)

	var mission := get_service("MissionService") as MissionService
	var minigames := get_service("MinigameService") as MinigameService
	var resources := get_service("ResourcesService") as ResourcesService
	var clock := get_service("ClockService") as ClockService
	var data := get_service("MissionDataService") as MissionDataService

	if mission and data and clock:
		mission.show_report(data.get_counts(), clock.elapsed_hours())
	_end_mission(minigames, resources, clock, data)
	_busy = false


## The player ran out of oxygen, food or water. Only counts during a running mission.
func _on_resourcesservice_depleted(resource_name: String) -> void:
	var mission := get_service("MissionService") as MissionService
	if _busy or mission == null or mission.phase != MissionService.Phase.ACTIVE:
		return
	_play_sound(DEATH_SOUND)
	mission.die(resource_name)
	_end_mission(
			get_service("MinigameService") as MinigameService,
			get_service("ResourcesService") as ResourcesService,
			get_service("ClockService") as ClockService,
			get_service("MissionDataService") as MissionDataService)


## Shared by RETURN and death: close the tools and reset everything the mission used.
func _end_mission(minigames: MinigameService, resources: ResourcesService, clock: ClockService, data: MissionDataService) -> void:
	_director.end_story()
	_stop_music()
	if minigames:
		minigames.set_available_tools([])
		minigames.set_mission_params({})
	if resources:
		resources.end_mission()
	if clock:
		clock.set_running(false)
	if data:
		data.reset()


func _on_missionservice_new_mission_requested() -> void:
	begin_planning()


## RETRY on the death screen: back to the beginning, planning a new run.
func _on_missionservice_retry_requested() -> void:
	begin_planning()


## Minigames started or stopped playing.
func _on_minigameservice_minigame_active_changed(active: bool) -> void:
	var resources := get_service("ResourcesService") as ResourcesService
	if resources:
		resources.set_minigame_active(active)
	var clock := get_service("ClockService") as ClockService
	if clock:
		clock.set_playing(active)


## The player failed a minigame.
func _on_minigameservice_minigame_failed(_minigame_name: String) -> void:
	var resources := get_service("ResourcesService") as ResourcesService
	if resources:
		resources.apply_failure_penalty()


## The player completed a minigame; its data goes into the matching category.
func _on_minigameservice_minigame_solved(data_category: String) -> void:
	var data := get_service("MissionDataService") as MissionDataService
	if data:
		data.record(data_category)


## Starts the background music, which repeats until _stop_music().
func _start_music() -> void:
	if _music == null:
		var stream := load(MUSIC_PATH) as AudioStream
		if stream == null:
			push_warning("Could not load the background music: %s" % MUSIC_PATH)
			return
		_music = AudioStreamPlayer.new()
		_music.stream = stream
		_music.bus = AudioSettings.MUSIC
		_music.volume_db = MUSIC_VOLUME_DB
		_music.finished.connect(_on_music_finished)
		add_child(_music)
	_music_wanted = true
	if not _music.playing:
		_music.play()


func _stop_music() -> void:
	_music_wanted = false
	if _music:
		_music.stop()


## Plays the track again as long as the player is still in the Mission Control area.
func _on_music_finished() -> void:
	if _music_wanted:
		_music.play()


## Plays a sound once and finishes when it has played all the way through.
func _play_sound(stream: AudioStream) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = AudioSettings.SFX
	add_child(player)
	player.play()
	await player.finished
	player.queue_free()

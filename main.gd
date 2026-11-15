extends MainSc
## Connects the services to each other. MainSc automatically connects every service signal to
## a method named `_on_<servicename>_<signal>` (service name in lowercase), so the handlers
## below are the only glue needed. Services never reference each other directly.


## A minigame window opened or the last one closed.
func _on_minigameservice_minigame_active_changed(active: bool) -> void:
	var resources := get_service("ResourcesService") as ResourcesService
	if resources:
		resources.set_minigame_active(active)


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

@tool
extends Node
class_name MainSc

# Global State Variables
var is_paused: bool = false
var time_warp_multiplier: float = 1.0

@export var bundles: Array[BundleDefinition] = []
var _services: Dictionary[String, Node] = {}

@export var services_node: Node

func _ready() -> void:
	# CRITICAL: Separate editor logic from runtime logic to prevent side effects while editing
	if Engine.is_editor_hint():
		_setup_editor_preview()
	else:
		_initialize_bundles()
		_bind_services()

# EDITOR PREVIEW ---

## Instantiates services in the editor viewport for visual feedback.
func _setup_editor_preview() -> void:
	# CRITICAL: Clear existing preview nodes to prevent duplicates when the script reloads in the editor
	for child in services_node.get_children():
		child.queue_free()

	for bundle in bundles:
		if not bundle: continue

		for service_def in bundle.services:
			if not service_def or not service_def.scene: continue

			# Only instantiate services that have editor_preview enabled in the Inspector
			if service_def.editor_preview:
				var service_node = service_def.scene.instantiate()
				service_node.name = service_def.identity_name
				services_node.add_child(service_node)

				# CRITICAL: Use call_deferred to allow the engine to fully register
				# the script's methods before calling them, preventing "via call" errors.
				if service_node.has_method("bind_nodes"):
					service_node.call_deferred("bind_nodes")
					print(service_node.name + " previewed!")
				else:
					push_warning("Service '", service_node.name, "' is missing bind_nodes(). Check for script syntax errors.")

# INITIALIZATION ---

func _initialize_bundles() -> void:
	for bundle in bundles:
		if not bundle: continue

		for service_def in bundle.services:
			if not service_def or not service_def.scene: continue

			var service_node = service_def.scene.instantiate()
			service_node.name = service_def.identity_name
			services_node.add_child(service_node)

			_services[service_def.identity_name] = service_node
			_auto_connect_signals(service_node)
			print("Service Loaded: ", service_def.identity_name)

func _bind_services() -> void:
	for service in services_node.get_children():
		if service.has_method("bind_nodes"):
			service.bind_nodes()
			print(service.name + " binded!")

func _auto_connect_signals(service_node: Node) -> void:
	for signal_info in service_node.get_signal_list():
		var signal_name: String = signal_info.name
		var handler_name: String = "_on_" + service_node.name.to_lower() + "_" + signal_name

		if has_method(handler_name):
			service_node.connect(signal_name, Callable(self, handler_name))

# API ---

## Tools and scripts use this to find services directly.
func get_service(service_name: String) -> Node:
	if _services.has(service_name):
		return _services[service_name]
	push_error("Service not found: " + service_name)
	return null

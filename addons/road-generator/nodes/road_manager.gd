@tool
@icon("res://addons/road-generator/resources/road_manager.png")
## Manager for all children RoadContainers
class_name RoadManager
extends Node3D


# ------------------------------------------------------------------------------
# Inherited default settings used by RoadContainers
# ------------------------------------------------------------------------------


@export var density: float = 4.0: set = _set_density


# ------------------------------------------------------------------------------
# Editor settings
# ------------------------------------------------------------------------------


# Auto refresh on transforms or other actions on roads. Good to disable if
# you modify roads during runtime and want to manually trigger refreshes on
# specific RoadContainers/RoadPoints at a time.
@export var auto_refresh: bool = true: set = _ui_refresh_set


# ------------------------------------------------------------------------------
# Internal flags
# ------------------------------------------------------------------------------


var _skip_warn_found_rc_child := false


# ------------------------------------------------------------------------------
# Setup and export setter/getters
# ------------------------------------------------------------------------------

func _ready():
	# Without this line, child RoadContainers initialize after
	# the manager initializes (different from _ready), meaning
	# it would default to true even if auto refresh is false here.
	_ui_refresh_set(auto_refresh)


func _get_configuration_warnings() -> PackedStringArray:
	if _skip_warn_found_rc_child:
		return []
	var any_containers := false
	for ch in get_children():
		if ch.has_method("is_road_container"):
			any_containers = true
			break

	if any_containers:
		return []
	else:
		return ["No RoadContainer children. Start creating a road by activating the + mode and clicking in the 3D view"]


# Workaround for cyclic typing
func is_road_manager() -> bool:
	return true


func _set_density(value: float) -> void:
	density = value
	rebuild_all_containers()


func _ui_refresh_set(value: bool) -> void:
	if value:
		call_deferred("rebuild_all_containers")
	auto_refresh = value
	for ch in get_containers():
		# Not an exposed setting on child.
		ch._auto_refresh = value


# ------------------------------------------------------------------------------
# Setup and export setter/getters
# ------------------------------------------------------------------------------


func get_containers() -> Array:
	var res := []
	for ch in get_children():
		if ch.has_method("is_road_container"):
			res.append(ch)
	return res


## Blocking function that will wait until all roads have been generated
func rebuild_all_containers(clear_existing := false) -> void:
	for ch in get_containers():
		ch.rebuild_segments(clear_existing)


## Regenerates each container with a deferred call per container
func rebuild_all_containers_deferred() -> void:
	for ch in get_containers():
		ch._dirty = true
		ch._dirty_rebuild_deferred()

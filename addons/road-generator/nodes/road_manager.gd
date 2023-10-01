## Manager for all children RoadContainers
tool
class_name RoadManager, "../resources/road_manager.png"
extends Spatial


# ------------------------------------------------------------------------------
# Inherited default settings used by RoadContainers
# ------------------------------------------------------------------------------


export(float) var density:float = 2.0  setget _set_density # Mesh density of generated segments.


# ------------------------------------------------------------------------------
# Editor settings
# ------------------------------------------------------------------------------


# Auto refresh on transforms or other actions on roads. Good to disable if
# you modify roads during runtime and want to manually trigger refreshes on
# specific RoadContainers/RoadPoints at a time.
export(bool) var auto_refresh = true setget _ui_refresh_set


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


func _get_configuration_warning() -> String:
	if _skip_warn_found_rc_child:
		return ""
	var any_containers := false
	for ch in get_children():
		if ch.has_method("is_road_container"):
			any_containers = true
			break

	if any_containers:
		return ""
	else:
		return "No RoadContainer children. Start creating a road by activating the + mode and clicking in the 3D view"


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


func rebuild_all_containers() -> void:
	for ch in get_containers():
		ch._dirty = true
		ch._dirty_rebuild_deferred()

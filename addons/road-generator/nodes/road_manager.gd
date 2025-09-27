@tool
@icon("res://addons/road-generator/resources/road_manager.png")
class_name RoadManager
extends Node3D
## Manager for all child [RoadContainer]'s.
##
## This node should be added as the parent of all RoadContainers which are
## meant to be managed by these settings. The exception is where a RoadContainer
## is saved as the root of a tscn saved file.
##
## @tutorial(Getting started): https://github.com/TheDuckCow/godot-road-generator/wiki/A-getting-started-tutorial
## @tutorial(Custom Materials Tutorial): https://github.com/TheDuckCow/godot-road-generator/wiki/Creating-custom-materials
## @tutorial(Custom Mesh Tutorial): https://github.com/TheDuckCow/godot-road-generator/wiki/User-guide:-Custom-road-meshes


# ------------------------------------------------------------------------------
#region Signals/Enums/Const/Exports
# ------------------------------------------------------------------------------


## Emitted when a road segment has been (re)generated, returning the list
## of updated segments of type Array.
signal on_road_updated(updated_segments: Array)

## For internal purposes, to handle drag events in the editor.
signal on_container_transformed(updated_segments: RoadContainer)

const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")
const RoadMaterial = preload("res://addons/road-generator/resources/road_texture.material")


# ------------------------------------------------------------------------------
# How road meshes are generated
@export_group("Road Generation")
# ------------------------------------------------------------------------------

## The material applied to generated meshes.[br][br]
##
## This mateiral is expected to use a specific trimsheet UV layout.[br][br]
##
## Can be overridden by each [RoadContainer].
@export
var material_resource: Material = RoadMaterial:
	set(value):
		material_resource = value
		if auto_refresh:
			rebuild_all_containers(true)

## The material applied to the underside of the generated meshes.[br][br]
##
## Can be overridden by each [RoadContainer].
@export
var material_underside: Material:
	set(value):
		material_underside = value
		rebuild_all_containers()

## Defines the distance in meters between road loop cuts.[br][br]
##
## This mirrors the same term used in native Curve3D objects where a higher
## density means a larger spacing between loops and fewer overall verticies.[br][br]
##
## Can be overridden by each [RoadContainer].
@export
var density: float = RoadSegment.DEFAULT_DENSITY:
	set(value):
		density = value
		if auto_refresh:
			rebuild_all_containers(true)


## Defines the thickness in meters of the underside part of the road.[br][br]
##
## A value of -1 indicates the underside will not be generated at all.
@export var underside_thickness: float = -1.0:
	set(value):
		underside_thickness = value
		rebuild_all_containers()

# ------------------------------------------------------------------------------
# Properties defining how to set up the road's StaticBody3D
@export_group("Collision")
# ------------------------------------------------------------------------------


## The PhysicsMaterial to apply to genrated static bodies.[br][br]
##
## Can be overridden by each [RoadContainer].
@export
var physics_material: PhysicsMaterial:
	set(value):
		physics_material = value
		if auto_refresh:
			rebuild_all_containers(true)

## Group name to assign to the staic bodies created by a RoadSegment.[br][br]
##
## Can be overridden by each [RoadContainer].
@export
var collider_group_name := "":
	set(value):
		collider_group_name = value
		if auto_refresh:
			rebuild_all_containers(true)

## Meta name to assign to the static bodies created by a RoadSegment.[br][br]
##
## Can be overridden by each [RoadContainer].
@export
var collider_meta_name := "":
	set(value):
		collider_meta_name = value
		if auto_refresh:
			rebuild_all_containers(true)

## Collision layer to assign to the StaticBody3D's own collision_layer.[br][br]
##
## Can be overridden by each [RoadContainer] if
## [member RoadContainer.override_collision_layers] is enabled.
@export_flags_3d_physics var collision_layer: int = 1:
	set(value):
		collision_layer = value
		if auto_refresh:
			rebuild_all_containers(true)

## Collision mask to assign to the StaticBody3D's own collision_mask.[br][br]
##
## Can be overridden by each [RoadContainer] if
## [member RoadContainer.override_collision_layers] is enabled.
@export_flags_3d_physics var collision_mask: int = 1:
	set(value):
		collision_mask = value
		if auto_refresh:
			rebuild_all_containers(true)

# ------------------------------------------------------------------------------
# Properties relating to how RoadLanes and AI tooling is set up
@export_group("Lanes and AI")
# ------------------------------------------------------------------------------


## The group name assigned to any procedurally generated [RoadLane].[br][br]
##
## Can be overridden by each [RoadContainer].
@export
var ai_lane_group := "road_lanes":
	set(value):
		ai_lane_group = value
		if auto_refresh:
			rebuild_all_containers(true)


# ------------------------------------------------------------------------------
@export_group("Editor settings")
# ------------------------------------------------------------------------------


## Auto refresh on transforms or other actions on roads. Good to disable if
## you modify roads during runtime and want to manually trigger refreshes on
## specific RoadContainers/RoadPoints at a time.
@export
var auto_refresh: bool = true: set = _ui_refresh_set


# ------------------------------------------------------------------------------
# Internal flags and setup
# ------------------------------------------------------------------------------


var _skip_warn_found_rc_child := false


# ------------------------------------------------------------------------------
#endregion
#region Setup and builtin overrides
# ------------------------------------------------------------------------------


func _ready():
	# Without this line, child RoadContainers initialize after
	# the manager initializes (different from _ready), meaning
	# it would default to true even if auto refresh is false here.
	_ui_refresh_set(auto_refresh)

	rebuild_all_containers(true)


func _enter_tree() -> void:
	pass


func _exit_tree() -> void:
	pass


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


# ------------------------------------------------------------------------------
#endregion
#region Functions
# ------------------------------------------------------------------------------


func get_containers() -> Array[RoadContainer]:
	var res:Array[RoadContainer] = []
	for ch in get_children():
		if ch is RoadContainer:
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


# ------------------------------------------------------------------------------
#endregion
#region Internal functions
# ------------------------------------------------------------------------------


## Propogates upwards signals emitted by child RoadContainers
##
## Note: this function is called directly by each RoadContainer, and results
## are not accumulated across multiple updates but rather one at a time.
func on_container_update(updated_segments: Array) -> void:
	on_road_updated.emit(updated_segments)


func _ui_refresh_set(value: bool) -> void:
	if value:
		call_deferred("rebuild_all_containers") # Call with true?
	auto_refresh = value
	for ch in get_containers():
		# Not an exposed setting on child.
		ch._auto_refresh = value


#endregion
# ------------------------------------------------------------------------------

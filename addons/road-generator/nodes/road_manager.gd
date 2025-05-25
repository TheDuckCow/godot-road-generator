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
var material_resource: Material:
	set(value):
		material_resource = value
		rebuild_all_containers()

## Defines the distance in meters between road loop cuts.[br][br]
##
## This mirrors the same term used in native Curve3D objects where a higher
## density means a larger spacing between loops and fewer overall verticies.[br][br]
##
## Can be overridden by each [RoadContainer].
@export
var density: float = 4.0:
	set(value):
		density = value
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
		rebuild_all_containers()

## Group name to assign to the staic bodies created by a RoadSegment.[br][br]
##
## Can be overridden by each [RoadContainer].
@export
var collider_group_name := "":
	set(value):
		collider_group_name = value
		rebuild_all_containers()

## Meta name to assign to the static bodies created by a RoadSegment.[br][br]
##
## Can be overridden by each [RoadContainer].
@export
var collider_meta_name := "":
	set(value):
		collider_meta_name = value
		rebuild_all_containers()

## Collision layer to assign to the StaticBody3D's own collision_layer.[br][br]
##
## Can be overridden by each [RoadContainer] if
## [member RoadContainer.override_collision_layers] is enabled.
@export_flags_3d_physics var collision_layer: int = 1:
	set(value):
		collision_layer = value
		rebuild_all_containers()

## Collision mask to assign to the StaticBody3D's own collision_mask.[br][br]
##
## Can be overridden by each [RoadContainer] if
## [member RoadContainer.override_collision_layers] is enabled.
@export_flags_3d_physics var collision_mask: int = 1:
	set(value):
		collision_mask = value
		rebuild_all_containers()

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
		rebuild_all_containers()


# ------------------------------------------------------------------------------
@export_group("Editor settings")
# ------------------------------------------------------------------------------


## Auto refresh on transforms or other actions on roads. Good to disable if
## you modify roads during runtime and want to manually trigger refreshes on
## specific RoadContainers/RoadPoints at a time.
@export
var auto_refresh: bool = true: set = _ui_refresh_set


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
	
	# setup_road_container won't work in _ready unless call_deferred is used
	assign_default_material.call_deferred()
	

func assign_default_material() -> void:
	if not material_resource:
		material_resource = RoadMaterial


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

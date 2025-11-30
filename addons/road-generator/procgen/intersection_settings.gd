@tool
@icon("res://addons/road-generator/resources/road_intersection.png")
# @abstract
class_name IntersectionSettings
extends Resource
## Settings for the [RoadIntersection] on which
## this resource is assigned.
##
## @abstract
##
## Defines a [RoadIntersection]'s procedural generation
## (settings, mesh, agent lanes, etc.).
##
## When assigned as default, it should be made unique to avoid
## unexpected side effects on other intersection points when modifying
## the resource.
##
## **Note:** Cannot reference [RoadIntersection] to avoid cyclic dependencies.

# ------------------------------------------------------------------------------
#region Mesh generation
# ------------------------------------------------------------------------------

## @abstract
## returns a Mesh for the intersection based on the input parameters.
##
## The override should return an empty mesh if arrays are empty
## (i.e. the intersection has no points).
##
## Parent transform refers to the [RoadIntersection]'s local transform.
##
## Edges MUST have been sorted by angle from intersection beforehand.
##
## Note: Cannot use [RoadIntersection] for `intersection` due to cyclic typing.
func generate_mesh(intersection: Node3D, edges: Array[RoadPoint], container: RoadContainer) -> Mesh:
	push_error("IntersectionSettings.generate_mesh() not implemented by child class.")
	return null

## Returns true if all the provided edges have sufficient distance
## from the intersection point to have proper mesh generation.
##
## To customize the minimum distance, override [get_min_distance_from_intersection_point].
##
## This should be called in the implemented class's [generate_mesh] override.
func can_generate_mesh(intersection_transform: Transform3D, edges: Array[RoadPoint]) -> bool:
	for edge in edges:
		if edge.position.distance_to(intersection_transform.origin) < get_min_distance_from_intersection_point(edge):
			return false
	return true

## Returns the minimum distance required between a [RoadIntersection]
## and its [RoadPoint] edges for the mesh to generate correctly.
func get_min_distance_from_intersection_point(rp: RoadPoint) -> float:
	return 0.0

# ------------------------------------------------------------------------------
#endregion
# ------------------------------------------------------------------------------

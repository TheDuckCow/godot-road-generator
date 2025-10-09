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

# ------------------------------------------------------------------------------
#region Mesh generation
# ------------------------------------------------------------------------------

## @abstract
## returns a Mesh for the intersection based on the input parameters.
##
## The order of items in array arguments should be consistent
## (matching by index).
##
## The override should return an empty mesh if arrays are empty
## (i.e. the intersection has no points).
func generate_mesh(intersection: Vector3, edges: Array[Vector3], edge_normals: Array[Vector3], edges_thickness: Array[float]) -> Mesh:
    push_error("IntersectionSettings.generate_mesh() not implemented by child class.")
    return null

## Returns true if all the provided edges have sufficient distance
## from the intersection point to have proper mesh generation.
##
## To customize the minimum distance, override [get_min_distance_from_intersection_point].
##
## This should be called in the implemented class's [generate_mesh] override.
func can_generate_mesh(intersection: Vector3, edges: Array[Vector3]) -> bool:
    for edge in edges:
        if edge.distance_to(intersection) < get_min_distance_from_intersection_point():
            return false
    return true

## Returns the minimum distance required between a [RoadIntersection]
## and its [RoadPoint] edges for the mesh to generate correctly.
func get_min_distance_from_intersection_point() -> float:
    return 0.0

# ------------------------------------------------------------------------------
#endregion
# ------------------------------------------------------------------------------

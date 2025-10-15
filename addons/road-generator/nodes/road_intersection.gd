@tool
@icon("res://addons/road-generator/resources/road_intersection.png")
class_name RoadIntersection
extends RoadGraphNode
## Center point of an intersection.
##
## Defines a procedural intersection between multiple [RoadPoint] nodes.
## The position of the [RoadIntersection] node itself represents the origin
## of said intersection.
##
## Should be contained within a [RoadContainer] and a sibling to
## 1+ referenced [RoadPoints] (the "edges"). One [RoadContainer] can contain multiple
## [RoadIntersection] nodes, hence the need to reference edge points.
##
## A [RoadIntersection] cannot connect to another [RoadIntersection],
## both must connect to an intermediate [RoadPoint] in this scenario.
##
## intersection Geometry is a direct child of this node.
##
## @experimental: In active development.

# TODO: potential refactor with [RoadPoint] to reduce duplicate code?

# ------------------------------------------------------------------------------
#region Signals/Enums/Const
# ------------------------------------------------------------------------------

signal on_transform(node: Node3D, low_poly: bool) # TODO in abstract?

# ------------------------------------------------------------------------------
#region Export vars
# ------------------------------------------------------------------------------

@export var settings: IntersectionSettings = null: get = _get_settings, set = _set_settings 

@export var edge_points: Array[RoadPoint] = []: get = _get_edge_points, set = _set_edge_points

var container:RoadContainer ## The managing container node for this road intersection (direct parent).

# internal:

var _mesh: MeshInstance3D = MeshInstance3D.new() # mesh sibling used to display the intersection

# ------------------------------------------------------------------------------
#endregion
#region Export var callbacks
# ------------------------------------------------------------------------------

func _set_edge_points(value: Array[RoadPoint]) -> void:
	for point in value:
		if is_instance_of(point, RoadIntersection):
			push_error("RoadIntersection %s cannot directly connect to another RoadIntersection %s. Use an intermediate RoadPoint." % [self.name, point.name])
	edge_points = value
	if not is_instance_valid(container):
		return  # Might not be initialized yet.
	emit_transform()

func _get_edge_points() -> Array[RoadPoint]:
	return edge_points

func _get_settings() -> IntersectionSettings:
	return settings

func _set_settings(value: IntersectionSettings) -> void:
	settings = value
	# TODO emit transform?

# ------------------------------------------------------------------------------
#endregion
#region Setup and builtin overrides
# ------------------------------------------------------------------------------

func _init() -> void:
	# TODO ensure unique
	settings = IntersectionNGon.new()
	self.add_child(_mesh)

func _ready() -> void:
	if not container or not is_instance_valid(container):
		var par = get_parent()
		# Can't type check, circular dependency -____-
		#if not par is RoadContainer:
		if not par.has_method("is_road_container"):
			push_warning("Parent of RoadPoint %s is not a RoadContainer" % self.name)
		container = par
	on_transform.connect(container.on_point_update)
	refresh_intersection_mesh()


func _get_configuration_warnings() -> PackedStringArray:
	# return ["Intersections not yet implemented"]

	var par = get_parent()
	if par.has_method("is_road_container"):
		return []
	else:
		return ["Intersection should be a direct child of a RoadContainer"]


# Workaround for cyclic typing
func is_road_intersection() -> bool:
	return true

# ------------------------------------------------------------------------------
#endregion
#region Editor interactions
# ------------------------------------------------------------------------------

func emit_transform(low_poly: bool = false) -> void:
	refresh_intersection_mesh()
	# emit_signal("on_transform", self, low_poly) #FIXME

# ------------------------------------------------------------------------------
#endregion
#region Utilities
# ------------------------------------------------------------------------------

func refresh_intersection_mesh() -> void:
	if not is_instance_valid(settings) or not is_instance_valid(container):
		return
	if not container.create_geo:
		return
	
	var mesh: Mesh = settings.generate_mesh(self.transform, edge_points)
	_mesh.mesh = mesh
		

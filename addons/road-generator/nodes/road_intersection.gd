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
#endregion
#region Export vars
# ------------------------------------------------------------------------------

@export var settings: IntersectionSettings = null: get = _get_settings, set = _set_settings 


# -------------------------------------
@export_group("Road Generation")
# -------------------------------------

## Generate the procedural road geometry.[br][br]
##
## Turn this off if you want to swap in your own road mesh geometry and colliders.
@export var create_geo := true:
	set(value):
		if value == create_geo:
			return
		create_geo = value
		_do_roadmesh_creation() # Adds or removes mesh accordingly
		if create_geo:
			emit_transform()

## Flatten terrain when updating or transforming this Intersection.[br][br]
##
## To work, the RoadContainer must also have flatten_terrain enabled.
@export var flatten_terrain: bool = true

@export_group("Internal")

@export var edge_points: Array[RoadPoint] = []: get = _get_edge_points, set = _set_edge_points


var _mesh: MeshInstance3D
var _is_internal_updating: bool = false ## Very special cases to bypass autofix cyclic
var _skip_next_on_transform: bool = false ## To avoid retriggering builds after exiting and re-entering scene
var is_dirty := true ## Flag used to know if prior changes means the mesh needs refreshing.

# ------------------------------------------------------------------------------
#endregion
#region Export var callbacks
# ------------------------------------------------------------------------------

func _set_edge_points(value: Array[RoadPoint]) -> void:
	for point in value:
		if is_instance_of(point, RoadIntersection):
			push_error("RoadIntersection %s cannot directly connect to another RoadIntersection %s. Use an intermediate RoadPoint." % [self.name, point.name])
	edge_points = value
	_sort_edges_clockwise()
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


func _ready() -> void:
	set_notify_transform(true) # TODO: Validate if both are necessary
	set_notify_local_transform(true)
	if not container or not is_instance_valid(container):
		var par = get_parent()
		# Can't type check, circular dependency -____-
		#if not par is RoadContainer:
		if not par.has_method("is_road_container"):
			push_warning("Parent of RoadIntersection %s is not a RoadContainer" % self.name)
		container = par
	on_transform.connect(container.on_point_update)
	
	_do_roadmesh_creation()
	if container.debug_scene_visible and is_instance_valid(_mesh):
		_mesh.owner = container.get_owner()


func _get_configuration_warnings() -> PackedStringArray:
	var par = get_parent()
	if par.has_method("is_road_container"):
		return []
	else:
		return ["Intersection should be a direct child of a RoadContainer"]


func _notification(what):
	if not is_instance_valid(container):
		return  # Might not be initialized yet.
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		if _skip_next_on_transform:
			_skip_next_on_transform = false
			return
		var low_poly = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Engine.is_editor_hint()
		emit_transform(low_poly)


# Workaround for cyclic typing
func is_road_intersection() -> bool:
	return true


# ------------------------------------------------------------------------------
#endregion
#region Public functions
# ------------------------------------------------------------------------------


## Primary way trigger refresh geometry while respecting editor interactions.[br][br]
##
## Geometry refreshing is ontrolled at the RoadContainer level instead of
## directly by the RoadIntersection itself.
func emit_transform(low_poly: bool = false) -> void:
	is_dirty = true
	on_transform.emit(self, low_poly)


## Add an edge to the intersection, sorting edges and updating the mesh afterwards.
## Pushes an error for trying to add an intersection point.
## Does nothing if the edge is already present.
func add_branch(road_point: RoadPoint) -> void:
	if is_instance_of(road_point, RoadIntersection):
		push_error("RoadIntersection %s cannot directly connect to another RoadIntersection %s. Use an intermediate RoadPoint." % [self.name, road_point.name])
		return
	if edge_points.has(road_point):
		push_warning("Already connected to intersection")
		return
	if road_point.container != self.container:
		push_error("Can directly connect RoadPoints and RoadIntersections from the same container")
		return
	edge_points.append(road_point)
	_sort_edges_clockwise()
	
	# Identify the closest facing opene egde of the intersection.
	var is_prior_connected = road_point.is_prior_connected()
	var is_next_connected = road_point.is_next_connected()
	road_point._is_internal_updating = true
	if not is_prior_connected and not is_next_connected:
		# Determine which direction to use.
		var dir_to_inter: Vector3 = self.position - road_point.position 
		var is_fwd_facing:bool = (road_point.global_basis.z.dot(dir_to_inter)) > 0
		if is_fwd_facing:
			road_point.next_pt_init = road_point.get_path_to(self)
		else:
			road_point.prior_pt_init = road_point.get_path_to(self)
	elif is_prior_connected: # TODO: shoudl do if fwd or next prior connected, accounting for cross dirs
		road_point.next_pt_init = road_point.get_path_to(self)
	elif is_next_connected:
		road_point.prior_pt_init = road_point.get_path_to(self)
	else:
		push_error("Cannot connect RoadPoint %s already fully connected" % road_point.name)
		road_point._is_internal_updating = false
		return
	road_point._is_internal_updating = false
	
	container.update_edges()
	is_dirty = true
	emit_transform()


## Remove an edge from the intersection, sorting edges and updating the mesh afterwards.
## Does nothing if the edge is not present.
func remove_branch(road_point: RoadPoint) -> void:
	if not road_point in edge_points:
		push_error("Failed to remove branch, RoadPoint %s not found among edges of RoadIntersection %s" % [
			road_point.name, self.name
		])
	edge_points.erase(road_point)
	if road_point.get_node_or_null(road_point.prior_pt_init) == self:
		road_point.prior_pt_init = ^""
	if road_point.get_node_or_null(road_point.next_pt_init) == self:
		road_point.next_pt_init = ^""
	_sort_edges_clockwise()
	container.update_edges()
	is_dirty = true
	emit_transform()


## Sort edges, then refresh the mesh.
func sort_branches() -> void:
	_sort_edges_clockwise()
	emit_transform()


## Check if mesh needs to be rebuilt.[br][br]
##
## Returns true if rebuild was done, else (including if invalid) false.
func check_rebuild() -> bool:
	if is_queued_for_deletion():
		return false
	if not is_instance_valid(container):
		return false
	if is_dirty:
		_rebuild()
		is_dirty = false
		return true
	return false


## Actually generates or updates the intersection geometry.[br][br]
##
## Generally should only be called by via the RoadContainer to avoid duplicate
## calls to generation.
func refresh_intersection_mesh() -> void:
	_rebuild()


# ------------------------------------------------------------------------------
#endregion
#region Internal utilities
# ------------------------------------------------------------------------------


func _rebuild() -> void:
	if not is_instance_valid(settings) or not is_instance_valid(container):
		return
	if not container.create_geo:
		return

	# To support debugging in editor now, allow for temporary invalid paths
	# while manually populating. In the future, this shoudl auto-correct and
	# clear invalid edges or empty ids in array.
	var valid_edges: Array[RoadPoint] = []
	for _pt in edge_points:
		if not is_instance_valid(_pt):
			continue
		if not _pt is RoadPoint:
			continue
		valid_edges.append(_pt)
	
	if not valid_edges:
		return
	
	var mesh: Mesh = settings.generate_mesh(self, valid_edges, container)
	_mesh.mesh = mesh
	container._create_collisions(_mesh)


func _do_roadmesh_creation():
	var do_create := _should_add_mesh()
	if do_create:
		_add_road_mesh()
	else:
		_remove_road_mesh()


func _should_add_mesh() -> bool:
	var should_add_mesh = true
	if create_geo == false:
		should_add_mesh = false
	if container.create_geo == false:
		should_add_mesh = false
	return should_add_mesh


func _add_road_mesh() -> void:
	if is_instance_valid(_mesh):
		return
	_mesh = MeshInstance3D.new()
	add_child(_mesh)
	_mesh.name = "intersection_mesh"
	_mesh.layers = container.render_layers
	if container.debug_scene_visible and is_instance_valid(_mesh):
		_mesh.owner = container.get_owner()


func _remove_road_mesh():
	if _mesh == null:
		return
	_mesh.queue_free()


## Given the intersection transform's Y axis as
## the rotation reference and plane normal,
## O the intersection origin, OX the transform's X axis representing 0°,
## sorts the edges with position E clockwise,
## based on its angle from OX to OE, where OX and OE
## are projected on the plane defined by the intersection's Y axis.
func _sort_edges_clockwise() -> void:
	#print("debug - sorting")
	if edge_points.size() <= 1:
		return
	var axis: Vector3 = self.transform.basis.y.normalized()
	var plane = Plane(axis)
	var origin = plane.project(self.position)
	var angle_zero: Vector3 = plane.project(self.position + self.transform.basis.x) - origin
	angle_zero = angle_zero.normalized()
	edge_points.sort_custom(func (a,b):
		var projected_oa = plane.project(a.position) - origin
		var projected_ob = plane.project(b.position) - origin
		projected_oa = projected_oa.normalized()
		projected_ob = projected_ob.normalized()
		var angle_a = angle_zero.signed_angle_to(projected_oa, axis)
		var angle_b = angle_zero.signed_angle_to(projected_ob, axis)
		#print("debug - angles: %f / %f" % [angle_a, angle_b])
		#print("debug - vectors: %s / %s" % [projected_oa, projected_ob])
		#print("debug - positions: %s / %s" % [a.position, b.position])
		return angle_a - angle_b > 0 # must be a bool
	)

#endregion
# ------------------------------------------------------------------------------

# Class for defining a directional or bidirectional lane.
#
# Could, but does not have to be, parented to a RoadSegment class object.

tool # Draw in the editor things like path direction and width
extends Path
class_name LaneSegment

const COLOR_PRIMARY = Color(0.6, 0.3, 0,3)
const COLOR_START = Color(0.7, 0.7, 0,7)

signal on_transform

export var reverse_direction:bool = false setget _set_direction, _get_direction
export var lane_left:NodePath # Used to indicate allowed lane changes
export var lane_right:NodePath # Used to indicate allowed lane changes
export var lane_next:NodePath # LaneSegment or intersection
export var lane_previous:NodePath # LaneSegment or intersection
export var draw_in_game = false # Can override to draw if outside the editor

var this_road_segment = null # RoadSegment
var refresh_geom = true
var geom # For tool usage, drawing lane directions and end points

var _vehicles_in_lane = [] # Registration
var _display_fins: bool = false


func _ready():
	set_notify_transform(true)
	set_notify_local_transform(true)
	connect("curve_changed", self, "curve_changed")
	rebuild_geom()


func _set_direction(value):
	reverse_direction = value
	refresh_geom = true
	rebuild_geom()


func _get_direction():
	return reverse_direction


func get_lane_start() -> Vector3:
	var pos
	if reverse_direction:
		pos = curve.get_point_position(curve.get_point_count()-1)
	else:
		pos = curve.get_point_position(0)
	return to_global(pos)


func get_lane_end() -> Vector3:
	var pos
	if reverse_direction:
		pos = curve.get_point_position(0)
	else:
		pos = curve.get_point_position(curve.get_point_count()-1)
	return to_global(pos)


## Register a car to be connected to (on, following) this lane.
func register_vehicle(vehicle: Node) -> void:
	_vehicles_in_lane.append(vehicle)


## Optional but good cleanup of references.
func unregister_vehicle(vehicle: Node) -> void:
	if vehicle in _vehicles_in_lane:
		_vehicles_in_lane.erase(vehicle)


## Return all vehicles registered to this lane, performing cleanup as needed.
func get_vehicles()  -> Array:
	for vehicle in _vehicles_in_lane:
		if not is_instance_valid(vehicle):
			_vehicles_in_lane.erase(vehicle)
			continue
		if not vehicle or not vehicle._ai or vehicle._ai.follow_path != self:
			_vehicles_in_lane.erase(vehicle)
			continue
	return _vehicles_in_lane


func _instantiate_geom() -> void:
	if not _display_fins and (Engine.is_editor_hint() or draw_in_game):
		if geom:
			geom.clear()
		return
	if refresh_geom == false:
		return
	refresh_geom = false
	
	# Setup immediate geo node if not already.
	if geom == null:
		print("Creating new geo + mat")
		geom = ImmediateGeometry.new()
		geom.set_name("geom")
		add_child(geom)
		
		var mat = SpatialMaterial.new()
		mat.flags_unshaded = true
		mat.flags_do_not_receive_shadows = true
		mat.params_cull_mode = mat.CULL_DISABLED
		mat.vertex_color_use_as_albedo = true
		geom.material_override = mat
	
	_draw_shark_fins()


## Generate the triangles along the path, indicating lane direction.
func _draw_shark_fins() -> void:
	var curve_length = curve.get_baked_length()
	var draw_dist = 3 # draw a new triangle at this interval in m
	var tri_count = floor(curve_length / draw_dist)

	var rev = -1 if reverse_direction else 1
	geom.clear()
	for i in range (0, tri_count):
		var f = i * curve_length / tri_count
		var xf = Transform()
		
		xf.origin = curve.interpolate_baked(f)
		var lookat = (
			curve.interpolate_baked(f + 0.1*rev) - xf.origin
		).normalized()
		
		geom.begin(Mesh.PRIMITIVE_TRIANGLES)
		if i == 0:
			geom.set_color(COLOR_START)
		else:
			geom.set_color(COLOR_PRIMARY)
		geom.add_vertex(xf.origin)
		geom.add_vertex(xf.origin + Vector3(0, 0.5, 0) - lookat*0.2)
		geom.add_vertex(xf.origin + lookat * 1)
		geom.end()


func rebuild_geom() -> void:
	if refresh_geom:
		call_deferred("_instantiate_geom")


func curve_changed() -> void:
	refresh_geom = true
	rebuild_geom()


func show_fins(value: bool) -> void:
	_display_fins = value
	rebuild_geom()



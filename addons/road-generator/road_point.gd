## Definition for a single point handle, which 2+ road segments connect to.
tool
extends Spatial
class_name RoadPoint, "road_point.png"

enum LaneType {
	SHOULDER,
	SLOW,
	MIDDLE,
	FAST,
	TWO_WAY,
	ONE_WAY
}

enum LaneDir {
	NONE,
	FORWARD,
	REVERSE,
	BOTH
}

const UI_TIMEOUT = 50 # Time in ms to delay further refrehs updates.
const COLOR_YELLOW = Color(0.7, 0.7, 0,7)
const COLOR_RED = Color(0.7, 0.3, 0.3)

# Assign both the texture to use, as well as the path direction to generate.
# Order is left to right when oriented such that the RoadPoint is facing towards
# the top of the screen in a top down orientation.
export(Array, LaneType) var lanes:Array = [
	LaneType.SLOW, LaneType.FAST, LaneType.FAST, LaneType.SLOW
	] setget _set_lanes, _get_lanes
export(Array, LaneDir) var traffic_dir:Array = [
	LaneDir.REVERSE, LaneDir.REVERSE, LaneDir.FORWARD, LaneDir.FORWARD
	] setget _set_dir, _get_dir

export var lane_width := 4.0 setget _set_width, _get_width
export(NodePath) var prior_pt_init
export(NodePath) var next_pt_init
# Handle magniture
export(float) var prior_mag := 5.0
export(float) var next_mag := 5.0

# Ultimate assignment if any export path specified
var prior_pt:Spatial # Road Point or Junction
var prior_seg # :RoadSegment
var next_pt:Spatial # Road Point or Junction
var next_seg # :RoadSegment

var geom:ImmediateGeometry # For tool usage, drawing lane directions and end points
#var refresh_geom := true

var _last_update_ms # To calculate min updates.


func _ready():
	if prior_pt_init:
		prior_pt = get_node(prior_pt_init)
	if next_pt_init:
		next_pt = get_node(next_pt_init)
	# rebuild_geom()


func _to_string():
	return "RoadPoint of [%s] at %s between [%s]:[%s]" % [
		self.get_parent().name,  self.translation, prior_pt, next_pt]

# ------------------------------------------------------------------------------
# Editor visualizing
# ------------------------------------------------------------------------------

func _set_lanes(values):
	lanes = values
	rebuild_geom()


func _get_lanes():
	return lanes


func _set_dir(values):
	traffic_dir = values
	rebuild_geom()


func _get_dir():
	return traffic_dir


func _set_width(value):
	lane_width = value
	rebuild_geom()
	

func _get_width():
	return lane_width


func _notification(what):
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		on_transform()
		

func on_transform():
	var network = get_parent().get_parent()
	if not network.auto_refresh:
		return
	print("Is transforming, ", prior_seg, next_seg)
	if prior_seg:
		prior_seg.is_dirty = true
		prior_seg.check_refresh()
	if next_seg:
		next_seg.is_dirty = true
		next_seg.check_refresh()
	
	network.update_debug_paths(self)


func show_gizmo():
	rebuild_geom()


func hide_gizmo():
	geom.clear()
	

func rebuild_geom():
	# if refresh_geom:
	call_deferred("_instantiate_geom")


func _instantiate_geom():
	if not Engine.is_editor_hint():
		if geom:
			geom.clear()
		return
	
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
	else:
		geom.clear()
	
	_draw_lane_width()



func _draw_lane_width():
	var offy = Vector3(0, 0.02, 0)
	var half_width = lanes.size() * lane_width / 2.0
	geom.begin(Mesh.PRIMITIVE_TRIANGLES)
	geom.set_color(COLOR_YELLOW)
	geom.add_vertex(Vector3(-half_width, 0, 0))
	geom.add_vertex(Vector3(0, 0, 0.5))
	geom.add_vertex(Vector3(half_width, 0, 0))
	geom.set_color(COLOR_RED)
	# Top triangle
	geom.add_vertex(Vector3(-half_width, 0, -0.5))
	geom.add_vertex(Vector3(half_width, 0, -0.5))
	geom.add_vertex(Vector3(half_width, 0, 0))
	# Bottom triangle
	geom.add_vertex(Vector3(half_width, 0, 0))
	geom.add_vertex(Vector3(-half_width, 0, 0))
	geom.add_vertex(Vector3(-half_width, 0, -0.5))
	
	geom.end()

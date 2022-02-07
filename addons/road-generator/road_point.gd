tool
extends Spatial
class_name RoadPoint, "road_point.png"

const COLOR_YELLOW = Color(0.7, 0.7, 0,7)
const COLOR_RED = Color(0.7, 0.3, 0.3)

# Conceptual: could be a list of points for lane nav ends with direction
export var lanes:Array = [-1, -1, 1, 1] setget _set_lanes, _get_lanes
export var lane_width := 4.0 setget _set_width, _get_width
export(NodePath) var prior_seg_init
export(NodePath) var next_seg_init

# Ultimate assignment if any export path specified
var prior_seg:Spatial # Road Point or Junction
var next_seg:Spatial # Road Point or Junction

var geom:ImmediateGeometry # For tool usage, drawing lane directions and end points
#var refresh_geom := true

func _ready():
	if prior_seg_init:
		prior_seg = get_node(prior_seg_init)
	if next_seg_init:
		next_seg = get_node(next_seg_init)
	rebuild_geom()


func _to_string():
	return "RoadPoint of [%s] at %s between [%s]:[%s]" % [
		self.get_parent().name,  self.translation, prior_seg, next_seg]

# ------------------------------------------------------------------------------
# Editor visualizing
# ------------------------------------------------------------------------------

func _set_lanes(values):
	lanes = values
	rebuild_geom()


func _get_lanes():
	return lanes


func _set_width(value):
	lane_width = value
	rebuild_geom()
	

func _get_width():
	return lane_width


func rebuild_geom():
	# if refresh_geom:
	call_deferred("_instantiate_geom")


func _instantiate_geom():
	if not Engine.is_editor_hint():
		if geom:
			geom.clear()
		return
	print("Set lane?")
	#print("Building geo (if editor/draw enabled)")
	#if refresh_geom == false:
	#	return
	#refresh_geom = false
	
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
	

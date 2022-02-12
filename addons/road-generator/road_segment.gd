## Create and hold the geometry of a segment of road, including its curve.
##
## Assume lazy evaluation, only adding nodes when explicitly requested, so that
## the structure stays light only until needed.
extends Spatial
class_name RoadSegment, "road_segment.png"

export(NodePath) var start_init setget _init_start_set, _init_start_get
export(NodePath) var end_init setget _init_end_set, _init_end_get

var start_point:RoadPoint
var end_point:RoadPoint

var path:Path
var road_mesh:MeshInstance
var material:Material
var density := 5.00  # Distance between loops, bake_interval in m applied to curve for geo creation.

# Likely will need reference of a curve.. do later.
# var curve 


var is_dirty := true


func _ready():
	check_refresh()


## Unique identifier for a segment based on what its connected to.
func get_id():
	# TODO: consider changing so that the smaller resource id is first,
	# so that we avoid bidirectional issues.
	if start_point and end_point:
		name = "%s-%s" % [start_point.get_instance_id(), start_point.get_instance_id()]
	elif start_point:
		name = "%s-x" % start_point.get_instance_id()
	elif end_point:
		name = "x-%s" % end_point.get_instance_id()
	else:
		name = "x-x"
	return name
	

# ------------------------------------------------------------------------------
# Export callbacks
# ------------------------------------------------------------------------------

func _init_start_set(value):
	start_init = value
	is_dirty = true
	check_refresh()


func _init_start_get():
	return start_init


func _init_end_set(value):
	end_init = value
	is_dirty = true
	check_refresh()


func _init_end_get():
	return end_init


func check_refresh():
	if start_init:
		start_point = get_node(start_init)
	start_point.next_seg = self # TODO: won't work if next/prior is flipped for next node.
	if end_init:
		end_point = get_node(end_init)
	end_point.prior_seg = self # TODO: won't work if next/prior is flipped for next node.
	if not start_point or not is_instance_valid(start_point) or not start_point.visible:
		is_dirty = false
	if not end_point or not is_instance_valid(end_point) or not end_point.visible:
		is_dirty = false
	if is_dirty:
		_rebuild()
		is_dirty = false

# ------------------------------------------------------------------------------
# Geometry construction
# ------------------------------------------------------------------------------

## Construct the geometry of this road segment.
func _rebuild():
	get_id()
	if not road_mesh:
		road_mesh = MeshInstance.new()
		add_child(road_mesh)
		road_mesh.name = "road_mesh"
	_update_curve()
	
	# Reposition this node to be physically located between both RoadPoints.
	global_transform.origin = (
		start_point.global_transform.origin + start_point.global_transform.origin) / 2.0
	
	# First, find out the number of lanes that match between the two road points,
	# if they are off by more than 2, then error out (that assumes triangles
	# on both sides).
	if abs(len(start_point.lanes) - len(end_point.lanes)) > 2:
		push_error("Invalid change in lane counts from %s to %s on %s" % [
			len(start_point.lanes), len(end_point.lanes), self.name
		])
		return
	
	# Create a low and high poly road, start with low poly.
	_build_geo()


func _update_curve():
	if not path:
		path = Path.new()
		add_child(path)
		path.name = "seg_path"
	path.curve.clear_points()
	path.curve.bake_interval = density / 2.0 # more points, for sampling.
	path.transform.origin = Vector3.ZERO
	path.transform.scaled(Vector3.ONE)
	# path.transform. clear rotation.
	
	# Setup in handle of curve.
	var pos = to_local(start_point.global_transform.origin)
	#var handle = to_local(start_point.global_transform.basis.z * start_point.prior_mag)# - pos
	var handle = start_point.global_transform.basis.z * start_point.prior_mag
	path.curve.add_point(pos, -handle, handle)
	# TODO: apply tilt to match the control point.
	
	# Out handle.
	pos = to_local(end_point.global_transform.origin)
	#handle = to_local(end_point.global_transform.basis.z * end_point.prior_mag)# - pos
	handle = end_point.global_transform.basis.z * end_point.prior_mag
	path.curve.add_point(pos, -handle, handle)


func _normal_for_offset(curve:Curve3D, offset:float):
	var point1 = curve.interpolate_baked(offset - 0.001)
	var point2 = curve.interpolate_baked(offset + 0.001)
	var uptilt = curve.interpolate_baked_up_vector(offset, true)
	var tangent:Vector3 = (point2 - point1)
	return tangent.cross(uptilt).normalized()


func _build_geo():
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	#st.add_smooth_group(true)
	print("(re)building segment")
	var lane_count = max(len(start_point.lanes), len(end_point.lanes))
	
	var clength = path.curve.get_baked_length()
	# In this context, loop refers to quad faces, not the edges, as it will
	# be a loop of generated faces.
	var loops = int(max(floor(clength / density), 1.0)) # Need to sub 1?
	
	print_debug("%s: Seg gen: %s loops, length: %s, " % [
		self.name, loops, clength])
	
	for loop in range(loops):
		var offset_s = loop * density / clength
		var offset_e = (loop + 1) * density / clength
	
		#if len(start_point.lanes) == len(end_point.lanes):
		var start_loop:Vector3
		var start_basis:Vector3
		var end_loop:Vector3
		var end_basis:Vector3
		if loop == 0:
			start_loop = to_local(start_point.global_transform.origin)
			start_basis = start_point.global_transform.basis.x
		else:
			start_loop = path.curve.interpolate_baked(offset_s)
			start_basis = _normal_for_offset(path.curve, offset_s)
			
		if loop == loops - 1:
			end_loop = to_local(end_point.global_transform.origin)
			end_basis = end_point.global_transform.basis.x
		else:
			start_loop = path.curve.interpolate_baked(offset_e)
			end_basis = _normal_for_offset(path.curve, offset_e)
		
		print("\tRunning loop %s; Start: %s,%s, end: %s,%s" % [
			loop, start_loop, start_basis, end_loop, end_basis
		])
		
		for i in range(lane_count):
			# Prepare attributes for add_vertex.
			# Long edge towards origin, p1
			#st.add_normal(Vector3(0, 1, 0))
			st.add_uv(Vector2(1, 0))
			st.add_vertex(start_loop) # Call last for each vertex, adds the above attributes.
			# p1
			st.add_uv(Vector2(0, 0))
			st.add_vertex(start_loop + start_basis * start_point.lane_width)
			# p3
			st.add_uv(Vector2(1, 1))
			st.add_vertex(end_loop)
			
			# Reverse face, p1
			st.add_uv(Vector2(0, 0))
			st.add_vertex(start_loop + start_basis * start_point.lane_width)
			# p1
			st.add_uv(Vector2(0, 1))
			st.add_vertex(end_loop + end_basis * end_point.lane_width)
			# p3
			st.add_uv(Vector2(1, 1))
			st.add_vertex(end_loop)
			break
			
		#else:
		#push_warning("Non-same number of lanes not implemented yet")
	st.index()
	if material:
		st.set_material(material)
	st.generate_normals()
	road_mesh.mesh = st.commit()
	road_mesh.create_trimesh_collision() # Call deferred?
	road_mesh.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF


## Create and hold the geometry of a segment of road, including its curve.
##
## Assume lazy evaluation, only adding nodes when explicitly requested, so that
## the structure stays light only until needed.
extends Spatial
class_name RoadSegment, "road_segment.png"

const LOWPOLY_FACTOR = 3.0

signal check_rebuild(road_segment)
signal seg_ready(road_segment)

export(NodePath) var start_init setget _init_start_set, _init_start_get
export(NodePath) var end_init setget _init_end_set, _init_end_get

var start_point:RoadPoint
var end_point:RoadPoint

var curve:Curve3D
var road_mesh:MeshInstance
var material:Material
var density := 2.00 # Distance between loops, bake_interval in m applied to curve for geo creation.
var network # The managing network node for this road segment (grandparent).

var is_dirty := true
var low_poly := false  # If true, then was (or will be) generated as low poly.


func _init(_network):
	if not _network:
		push_error("Invalid network assigned")
		return
	network = _network
	curve = Curve3D.new()


func _ready():
	road_mesh = MeshInstance.new()
	add_child(road_mesh)
	road_mesh.name = "road_mesh"
	
	var res = connect("check_rebuild", network, "segment_rebuild")
	assert(res == OK)
	#emit_signal("seg_ready", self)
	#is_dirty = true
	#emit_signal("check_rebuild", self)


## Unique identifier for a segment based on what its connected to.
func get_id():
	# TODO: consider changing so that the smaller resource id is first,
	# so that we avoid bidirectional issues.
	if start_point and end_point:
		name = "%s-%s" % [start_point.get_instance_id(), end_point.get_instance_id()]
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
	#emit_signal("check_rebuild", self)
func _init_start_get():
	return start_init


func _init_end_set(value):
	end_init = value
	is_dirty = true
	#emit_signal("check_rebuild", self)
func _init_end_get():
	return end_init


func check_rebuild():
	start_point.next_seg = self # TODO: won't work if next/prior is flipped for next node.
	end_point.prior_seg = self # TODO: won't work if next/prior is flipped for next node.
	if not start_point or not is_instance_valid(start_point) or not start_point.visible:
		push_warning("Undirtied as node unready: start_point %s" % start_point)
		is_dirty = false
	if not end_point or not is_instance_valid(end_point) or not end_point.visible:
		push_warning("Undirtied as node unready: end_point %s" % end_point)
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
	if network and network.density > 0:
		density = network.density
	
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
	
	_update_curve()
	
	# Create a low and high poly road, start with low poly.
	_build_geo()


func _update_curve():
	curve.clear_points()
	curve.bake_interval = density / 4.0 # more points, for sampling.
	# path.transform.origin = Vector3.ZERO
	# path.transform.scaled(Vector3.ONE)
	# path.transform. clear rotation.
	
	# Setup in handle of curve
	var pos = to_local(start_point.global_transform.origin)
	var handle = start_point.global_transform.basis.z * start_point.next_mag
	curve.add_point(pos, -handle, handle)
	curve.set_point_tilt(0, start_point.rotation.z)
	
	# Out handle.
	pos = to_local(end_point.global_transform.origin)
	handle = end_point.global_transform.basis.z * end_point.prior_mag
	curve.add_point(pos, -handle, handle)
	curve.set_point_tilt(1, end_point.rotation.z)


func _normal_for_offset(curve:Curve3D, offset:float):
	var point1 = curve.interpolate_baked(offset - 0.001) # avoid below 0
	var point2 = curve.interpolate_baked(offset + 0.001) # avoid over maxlen
	var uptilt = curve.interpolate_baked_up_vector(offset, true)
	var tangent:Vector3 = (point2 - point1)
	return uptilt.cross(tangent).normalized()


func _build_geo():
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	#st.add_smooth_group(true)
	var lane_count = max(len(start_point.lanes), len(end_point.lanes))
	
	var clength = curve.get_baked_length()
	# In this context, loop refers to "quad" faces, not the edges, as it will
	# be a loop of generated faces.
	var loops
	if low_poly: # one third the geo
		# Remove all loops between road points, so it's a straight mesh with no
		# loops. In the future, this could be reduce to just a lower density.
		# This makes interactivity in the UI much faster, but could also work for
		# in-game LODs.
		loops = int(max(floor(clength / density / LOWPOLY_FACTOR), 1.0)) # Need at least 1 loop.
	else:
		loops = int(max(floor(clength / density), 1.0)) # Need at least 1 loop.
	
	# Keep track of UV position over lane, to be seamless within the segment.
	var lane_uvs_length = []
	for ln in range(lane_count):
		lane_uvs_length.append(0)
	
	# Number of times the UV will wrap, to ensure seamless at next RoadPoint.
	#
	# Use the minimum sized road width for counting.
	var min_road_width = min(start_point.lane_width, end_point.lane_width)
	# Aim for real-world texture proportions width:height of 2:1 matching texture,
	# but then the hight of 1 full UV is half the with across all lanes, so another 2x
	var single_uv_height = min_road_width * 4.0
	var target_uv_tiles:int = int(clength / single_uv_height)
	var per_loop_uv_size = float(target_uv_tiles) / float(loops)
	var uv_width = 0.125 # 1/8 for breakdown of texture.
	
	
	#print_debug("(re)building %s: Seg gen: %s loops, length: %s, lp: %s" % [
	#	self.name, loops, clength, low_poly])
	
	for loop in range(loops):
		# One loop = row of quads left to right across the road, spanning lanes.
		var offset_s = float(loop) / float(loops)
		var offset_e = float(loop + 1) / float(loops)
	
		#if len(start_point.lanes) == len(end_point.lanes):
		var start_loop:Vector3
		var start_basis:Vector3
		var end_loop:Vector3
		var end_basis:Vector3
		if loop == 0:
			start_loop = to_local(start_point.global_transform.origin)
			start_basis = start_point.global_transform.basis.x
		else:
			start_loop = curve.interpolate_baked(offset_s * clength)
			start_basis = _normal_for_offset(curve, offset_s * clength)
			
		if loop == loops - 1:
			end_loop = to_local(end_point.global_transform.origin)
			end_basis = end_point.global_transform.basis.x
		else:
			end_loop = curve.interpolate_baked(offset_e * clength)
			end_basis = _normal_for_offset(curve, offset_e * clength)
		
		#print("\tRunning loop %s: %s to %s; Start: %s,%s, end: %s,%s" % [
		#	loop, offset_s, offset_e, start_loop, start_basis, end_loop, end_basis
		#])
		
		var near_width = lerp(start_point.lane_width, end_point.lane_width, offset_s)
		var far_width = lerp(start_point.lane_width, end_point.lane_width, offset_e)
		
		for i in range(lane_count):
			# Create the contents of a single lane / quad within this quad loop.
			var lane_offset_s = near_width * (i - lane_count / 2.0) * start_basis
			var lane_offset_e = far_width * (i - lane_count / 2.0) * end_basis
			
			# Assume the start and end lanes are the same for now.
			var uv_l:float # the left edge of the uv for this lane.
			var uv_r:float
			if i >= len(start_point.lanes):
				uv_l = uv_width * 7 # Fallback for lane mismatch
				uv_r = uv_l + uv_width
			else:
				match start_point.lanes[i]:
					RoadPoint.LaneType.NO_MARKING:
						uv_l = uv_width * 7
						uv_r = uv_l + uv_width
					RoadPoint.LaneType.SHOULDER:
						uv_l = uv_width * 0
						uv_r = uv_l + uv_width
					RoadPoint.LaneType.SLOW:
						uv_l = uv_width * 1
						uv_r = uv_l + uv_width
					RoadPoint.LaneType.MIDDLE:
						uv_l = uv_width * 2
						uv_r = uv_l + uv_width
					RoadPoint.LaneType.FAST:
						uv_l = uv_width * 3
						uv_r = uv_l + uv_width
					RoadPoint.LaneType.TWO_WAY:
						# Flipped
						uv_r = uv_width * 4
						uv_l = uv_r + uv_width
					RoadPoint.LaneType.ONE_WAY:
						# Flipped
						uv_r = uv_width * 5
						uv_l = uv_r + uv_width
					RoadPoint.LaneType.SINGLE_LINE:
						uv_l = uv_width * 6
						uv_r = uv_l + uv_width
				if start_point.traffic_dir[i] == RoadPoint.LaneDir.REVERSE:
					var tmp = uv_r
					uv_r = uv_l
					uv_l = tmp
			
			# uv offset continuation for this lane.
			var uv_y_start = lane_uvs_length[i]
			var uv_y_end = lane_uvs_length[i] + per_loop_uv_size
			lane_uvs_length[i] = uv_y_end # For next loop to use.
			#print("Seg: %s, lane:%s, uv %s-%s" % [
			#	self.name, loop, uv_y_start, uv_y_end])
			
			# Prepare attributes for add_vertex.
			# Long edge towards origin, p1
			#st.add_normal(Vector3(0, 1, 0))
			quad(
				st,
				[
					Vector2(uv_l, uv_y_end),
					Vector2(uv_r, uv_y_end),
					Vector2(uv_r, uv_y_start),
					Vector2(uv_l, uv_y_start),
				],
				[
					end_loop + end_basis * far_width + lane_offset_e,
					end_loop + lane_offset_e,
					start_loop + lane_offset_s,
					start_loop + start_basis * near_width + lane_offset_s,

				])
			
		#else:
		#push_warning("Non-same number of lanes not implemented yet")
		
		# Now create the shoulder geometry, including the "bevel" geo.
		
		# Gutter depth is the same for the left and right sides.
		var gutr_near = Vector2(
			lerp(start_point.gutter_profile.x, end_point.gutter_profile.x, offset_s),
			lerp(start_point.gutter_profile.y, end_point.gutter_profile.y, offset_s))
		var gutr_far = Vector2(
			lerp(start_point.gutter_profile.x, end_point.gutter_profile.x, offset_e),
			lerp(start_point.gutter_profile.y, end_point.gutter_profile.y, offset_e))
	
		for i in range(2):
			var dir = -1 if i==0 else 1
			var uv_y_start = lane_uvs_length[dir]
			var uv_y_end = lane_uvs_length[dir] + per_loop_uv_size
			
			# Account for custom left/right shoulder width.
			var near_w_shoulder
			var far_w_shoulder
			var pos_far_l
			var pos_far_r
			var pos_near_l
			var pos_near_r
			var pos_far_gutter
			var pos_near_gutter
			if dir == 1:
				near_w_shoulder = lerp(start_point.shoulder_width_l, end_point.shoulder_width_l, offset_s)
				far_w_shoulder = lerp(start_point.shoulder_width_l, end_point.shoulder_width_l, offset_e)
				pos_far_l = lane_count / 2.0 * far_width + far_w_shoulder
				pos_far_r = lane_count / 2.0 * far_width
				pos_near_l = lane_count / 2.0 * near_width + near_w_shoulder
				pos_near_r = lane_count / 2.0 * near_width 
				pos_far_gutter = pos_far_l
				pos_near_gutter = pos_near_l
			else:
				near_w_shoulder = lerp(start_point.shoulder_width_r, end_point.shoulder_width_r, offset_s)
				far_w_shoulder = lerp(start_point.shoulder_width_r, end_point.shoulder_width_r, offset_e)
				pos_far_l = lane_count / 2.0 * far_width
				pos_far_r = lane_count / 2.0 * far_width + far_w_shoulder
				pos_near_l = lane_count / 2.0 * near_width
				pos_near_r = lane_count / 2.0 * near_width + near_w_shoulder
				pos_far_gutter = pos_far_r
				pos_near_gutter = pos_near_r
			
			# Assume the start and end lanes are the same for now.
			var uv_l:float # the left edge of the uv for this lane.
			var uv_m:float # The 'middle' vert, same level as shoulder but to edge.
			var uv_r:float
			var uv_mid = 0.8 # should be more like 0.9
			if dir == 1:
				uv_l = 0.0 * uv_width
				uv_m = uv_mid * uv_width
				uv_r = 1.0 * uv_width
			else:
				uv_l = 1.0 * uv_width
				uv_m = uv_mid * uv_width
				uv_r = 0.0 * uv_width
			# LEFT (between pos:_s and _m, and between uv:_l and _m)
			# The flat part of the shoulder on both sides
			quad(
				st,
				[
					Vector2(uv_m if dir == 1 else 1-uv_m, uv_y_end),
					Vector2(uv_r if dir == 1 else 1-uv_r, uv_y_end),
					Vector2(uv_r if dir == 1 else 1-uv_r, uv_y_start),
					Vector2(uv_m if dir == 1 else 1-uv_m, uv_y_start),
				],
				[
					end_loop + end_basis * pos_far_l * dir,
					end_loop + end_basis * pos_far_r * dir,
					start_loop + start_basis * pos_near_r * dir,
					start_loop + start_basis * pos_near_l * dir,
				])
			
			# The gutter, lower part of the shoulder on both sides.
			if dir == 1:
				quad(
					st,
					[
						Vector2(uv_l, uv_y_end),
						Vector2(uv_m, uv_y_end),
						Vector2(uv_m, uv_y_start),
						Vector2(uv_l, uv_y_start),
					],
					[
						end_loop + end_basis * (pos_far_l + gutr_far.x) * dir + Vector3(0, gutr_far.y, 0),
						end_loop + end_basis * pos_far_l * dir,
						start_loop + start_basis * pos_near_l * dir,
						start_loop + start_basis * (pos_near_l + gutr_near.x) * dir + Vector3(0, gutr_near.y, 0),
					])
			else:
				quad(
					st,
					[
						Vector2(uv_m, uv_y_end),
						Vector2(uv_r, uv_y_end),
						Vector2(uv_r, uv_y_start),
						Vector2(uv_m, uv_y_start),
					],
					[
						end_loop + end_basis * pos_far_r * dir,
						end_loop + end_basis * (pos_far_r + gutr_far.x) * dir + Vector3(0, gutr_far.y, 0),
						start_loop + start_basis * (pos_near_r + gutr_near.x) * dir + Vector3(0, gutr_near.y, 0),
						start_loop + start_basis * pos_near_r * dir,
					])
	
	st.index()
	if material:
		st.set_material(material)
	st.generate_normals()
	road_mesh.mesh = st.commit()
	road_mesh.create_trimesh_collision() # Call deferred?
	road_mesh.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF


# Generate a quad with two triangles for a list of 4 points/uvs in a row.
# For convention, do cloclwise from top-left vert, where the diagonal
# will go from bottom left to top right.
static func quad(st, uvs:Array, pts:Array) -> void:
	# Triangle 1.
	st.add_uv(uvs[0])
	# Add normal explicitly?
	st.add_vertex(pts[0])
	st.add_uv(uvs[1])
	st.add_vertex(pts[1])
	st.add_uv(uvs[3])
	st.add_vertex(pts[3])
	# Triangle 2.
	st.add_uv(uvs[1])
	st.add_vertex(pts[1])
	st.add_uv(uvs[2])
	st.add_vertex(pts[2])
	st.add_uv(uvs[3])
	st.add_vertex(pts[3])

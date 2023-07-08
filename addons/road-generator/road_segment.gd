## Create and hold the geometry of a segment of road, including its curve.
##
## Assume lazy evaluation, only adding nodes when explicitly requested, so that
## the structure stays light only until needed.
extends Spatial

# Disabled, since we don't want users to manually via the UI to add this class.
#class_name RoadSegment, "road_segment.png"
#
# To be able to reference as if a class, place this in any script:
# const RoadSegment = preload("res://addons/road-generator/road_segment.gd")

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

# Reference:
# https://raw.githubusercontent.com/godotengine/godot-docs/3.5/img/ease_cheatsheet.png
var smooth_amount := -2  # Ease in/out smooth, used with ease built function


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
func get_id() -> String:
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
	if not is_instance_valid(network):
		return
	#emit_signal("check_rebuild", self)
func _init_start_get():
	return start_init


func _init_end_set(value):
	end_init = value
	is_dirty = true
	if not is_instance_valid(network):
		return
	#emit_signal("check_rebuild", self)
func _init_end_get():
	return end_init


## Check if needing to be rebuilt.
## Returns true if rebuild was done, else (including if invalid) false.
func check_rebuild() -> bool:
	if is_queued_for_deletion():
		return false
	if not is_instance_valid(network):
		return false
	if not is_instance_valid(start_point) or not is_instance_valid(end_point):
		return false
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
		return true
	return false


## Utility to auto generate all road lanes for this road for use by AI.
##
## debug: No longer used, kept for backwards compatibility.
##
## Returns true if any lanes generated, false if not.
func generate_lane_segments(_debug: bool = false) -> bool:
	if not is_instance_valid(network):
		return false
	if not is_instance_valid(start_point) or not is_instance_valid(end_point):
		return false

	# First identify all road lanes that will exist.
	var matched_lanes = self._match_lanes()
	if len(matched_lanes) == 0:
		return false

	var any_generated = false

	# TODO: conditionally check for same-named lanes for re-use.
	clear_lane_segments()

	var start_offset = len(start_point.lanes) / 2.0 * start_point.lane_width - start_point.lane_width/2.0
	var end_offset = len(end_point.lanes) / 2.0 * end_point.lane_width - end_point.lane_width/2.0

	# Tracker used during the loop, to sum offset to apply.
	var lanes_added := 0

	# Assist var to assign lane_right and lane_left, used by AI for lane changes
	var last_ln = null

	# We need to keep track of the number of reverse lane subtractions and
	# forward subtractions. The left side (reverse) needs to be precalcuated,
	# while the right (forward) can be a running sum during the loop itself.
	var lane_shift = {"reverse": 0, "forward": 0}
	var end_is_wider = len(start_point.lanes) < len(end_point.lanes)
	for this_match in matched_lanes:
		var ln_type: int = this_match[0] # Enum RoadPoint.LaneType (texture)
		var ln_dir: int = this_match[1] # Enum RoadPoint.LaneDir (what we need)

		if ln_dir != RoadPoint.LaneDir.REVERSE:
			break # Already done

		if ln_type == RoadPoint.LaneType.TRANSITION_REM:
			lane_shift.reverse += 1
		if ln_type == RoadPoint.LaneType.TRANSITION_ADD:
			lane_shift.reverse += 1

	var max_rev_shift = lane_shift.reverse

	for this_match in matched_lanes:
		# Reusable name to check for and re-use, based on "tagged names".
		var ln_name = "p:%s_n:%s" % [this_match[2], this_match[3]]

		var ln_type: int = this_match[0] # Enum RoadPoint.LaneType
		var ln_dir: int = this_match[1] # Enum RoadPoint.LaneDir

		# TODO: Check for existing lanes and reuse (but also clean up if needed)
		# var ln_child = self.get_node_or_null(ln_name)
		var ln_child = null
		if not is_instance_valid(ln_child) or not ln_child is RoadLane:
			ln_child = RoadLane.new()
			add_child(ln_child)
			ln_child.add_to_group(network.ai_lane_group)
		var new_ln:RoadLane = ln_child

		# Assign the in and out lane tags, to help with connecting to other
		# road lanes later (handled by RoadNetwork).
		new_ln.lane_prior_tag = this_match[2]
		new_ln.lane_next_tag = this_match[3]
		new_ln.name = ln_name

		# Now decide where the two poitns should go, and their magnitudes.
		var in_pos: Vector3 = start_point.global_transform.origin
		var out_pos: Vector3 = end_point.global_transform.origin

		var tmp = get_transition_offset(
			ln_type, ln_dir, lane_shift, end_is_wider, max_rev_shift)
		var start_shift:float = tmp[0]
		var end_shift:float = tmp[1]

		var in_offset = lanes_added * start_point.lane_width - start_offset + start_shift
		var out_offset = lanes_added * end_point.lane_width - end_offset + end_shift

		in_pos += start_point.global_transform.basis.x * in_offset
		out_pos += end_point.global_transform.basis.x * out_offset

		# Set direction
		# TODO: When directionality is made consistent, we should no longer
		# need to invert the direction assignment here.
		if ln_dir != RoadPoint.LaneDir.REVERSE:
			new_ln.reverse_direction = true

		# TODO(#46): Swtich to re-sampling and adding more points following the
		# curve along from the parent path generator, including its use of ease
		# in and out at the edges.
		new_ln.curve.add_point(
			new_ln.to_local(in_pos),
			curve.get_point_in(0),
			curve.get_point_out(0))
		new_ln.curve.add_point(
			new_ln.to_local(out_pos),
			curve.get_point_in(1),
			curve.get_point_out(1))

		# Visually display.
		new_ln.draw_in_editor = network.draw_lanes_editor
		new_ln.draw_in_game = network.draw_lanes_game
		new_ln.refresh_geom = true
		new_ln.rebuild_geom()

		# Update lane connectedness for left/right lane connections.
		if not last_ln == null and last_ln.reverse_direction == new_ln.reverse_direction:
			# If the last lane and this one are facing the same way, then they
			# should be adjacent for lane changing. Which lane (left/right) is
			# just determiend by which way we are facing.
			if ln_dir == RoadPoint.LaneDir.FORWARD:
				last_ln.lane_right = last_ln.get_path_to(new_ln)
				new_ln.lane_left = new_ln.get_path_to(last_ln)
			else:
				last_ln.lane_left = last_ln.get_path_to(new_ln)
				new_ln.lane_right = new_ln.get_path_to(last_ln)

		# Assign that it was a success.
		any_generated = true
		lanes_added += 1
		last_ln = new_ln # For the next loop iteration.

	return any_generated


## Offset the curve in/out points based on lane index.
##
## Track the init (for reverse) or the stacking (fwd) number of
## transition lanes to offset.
##
## Note: lane_shift is passed by reference and mutated.
func get_transition_offset(
		ln_type: int,
		ln_dir: int,
		lane_shift: Dictionary,
		end_is_wider: bool,
		max_rev_shift: float) -> Array:

	var start_shift: float = 0
	var end_shift: float = 0

	# Forward cases
	if ln_type == RoadPoint.LaneType.TRANSITION_ADD and ln_dir == RoadPoint.LaneDir.FORWARD:
		lane_shift.forward += 1
		if end_is_wider:
			start_shift = lane_shift.forward * start_point.lane_width * -1
		else:
			end_shift = lane_shift.forward * end_point.lane_width * -1
	elif ln_type == RoadPoint.LaneType.TRANSITION_REM and ln_dir == RoadPoint.LaneDir.FORWARD:
		lane_shift.forward += 1
		if end_is_wider:
			start_shift = lane_shift.forward * start_point.lane_width * -1
		else:
			end_shift = lane_shift.forward * end_point.lane_width * -1
	# Reverse cases
	elif ln_type == RoadPoint.LaneType.TRANSITION_ADD and ln_dir == RoadPoint.LaneDir.REVERSE:
		if end_is_wider:
			start_shift = lane_shift.reverse * start_point.lane_width
		else:
			end_shift = lane_shift.reverse * end_point.lane_width
		lane_shift.reverse -= 1
	elif ln_type == RoadPoint.LaneType.TRANSITION_REM and ln_dir == RoadPoint.LaneDir.REVERSE:
		if end_is_wider:
			start_shift = lane_shift.reverse * start_point.lane_width
		else:
			end_shift = lane_shift.reverse * end_point.lane_width
		lane_shift.reverse -= 1
	#else:
	# General non transition case, but should be reverse=0 by now.

	if end_is_wider:
		start_shift -= max_rev_shift * start_point.lane_width
	else:
		end_shift -= max_rev_shift * end_point.lane_width

	return [start_shift, end_shift]


## Returns list of only valid RoadLanes
func get_lanes() -> Array:
	var lanes = []
	for ch in self.get_children():
		if not is_instance_valid(ch):
			continue
		elif not ch is RoadLane:
			# push_warning("Child of RoadSegment is not a RoadLane: %s" % ln.name)
			continue
		lanes.append(ch)
	return lanes


## Remove all RoadLanes attached to this RoadSegment
func clear_lane_segments():
	for ch in get_children():
		if ch is RoadLane:
			ch.queue_free()


# ------------------------------------------------------------------------------
# Geometry construction
# ------------------------------------------------------------------------------

## Construct the geometry of this road segment.
func _rebuild():
	if is_queued_for_deletion():
		return

	get_id()
	if network and network.density > 0:
		density = network.density

	# Reposition this node to be physically located between both RoadPoints.
	global_transform.origin = (
		start_point.global_transform.origin + start_point.global_transform.origin) / 2.0

	_update_curve()

	# Create a low and high poly road, start with low poly.
	_build_geo()


func _update_curve():
	curve.clear_points()
	curve.bake_interval = density # Specing in meters between loops.
	# path.transform.origin = Vector3.ZERO
	# path.transform.scaled(Vector3.ONE)
	# path.transform. clear rotation.

	# Setup in handle of curve
	var pos = to_local(start_point.global_transform.origin)
	var handle = start_point.global_transform.basis.z * start_point.next_mag
	curve.add_point(pos, -handle, handle)
	# curve.set_point_tilt(0, start_point.rotation.z)  # Doing custom interpolation

	# Out handle.
	pos = to_local(end_point.global_transform.origin)
	handle = end_point.global_transform.basis.z * end_point.prior_mag
	curve.add_point(pos, -handle, handle)
	# curve.set_point_tilt(1, end_point.rotation.z)  # Doing custom interpolation


## Calculates the horizontal vector of a Segment geometry loop. Interpolates
## between the start and end points. Applies "easing" to prevent potentially
## unwanted rotation on the loops at the ends of the curve.
## Inputs:
## curve - The curve this Segment will follow.
## sample_position - Curve sample position to use for interpolation. Normalized.
## Returns: Normalized Vector3
func _normal_for_offset(curve: Curve3D, sample_position: float) -> Vector3:
	# Calculate interpolation amount for curve sample point
	return _normal_for_offset_eased(curve, sample_position)
	# return _normal_for_offset_legacy(curve, sample_position)


## Alternate method which doesn't guarentee consistent lane width.
func _normal_for_offset_legacy(curve: Curve3D, sample_position: float) -> Vector3:
	var loop_point: Transform
	var _smooth_amount := -1.5
	var interp_amount: float = ease(sample_position, _smooth_amount)

	# Calculate loop transform
	loop_point.basis = start_point.global_transform.basis
	loop_point.basis = loop_point.interpolate_with(end_point.global_transform.basis, interp_amount).basis
	return loop_point.basis.x


## Enforce consistent lane width, at the cost of overlapping geometry.
func _normal_for_offset_eased(curve: Curve3D, sample_position: float) -> Vector3:
	var offset_amount = 0.002 # TODO: Consider basing this on lane width.
	var start_offset: float
	var end_offset: float
	if sample_position <= 0.0 + offset_amount:
		return start_point.global_transform.basis.x
	elif sample_position >= 1.0 - offset_amount * 0.5:
		return end_point.global_transform.basis.x
	else:
		start_offset = sample_position - offset_amount * 0.5
		end_offset = sample_position + offset_amount * 0.5

	var pt1 := curve.interpolate_baked(start_offset * curve.get_baked_length())
	var pt2 := curve.interpolate_baked(end_offset * curve.get_baked_length())
	var tangent := pt2 - pt1
	var sample_eased = ease(sample_position, smooth_amount)
	var up_vec:Vector3 = lerp(
		start_point.global_transform.basis.y,
		end_point.global_transform.basis.y,
		sample_position)
	var normal = up_vec.cross(tangent)
	return normal.normalized()


func _build_geo():
	if not is_instance_valid(road_mesh):
		return
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	#st.add_smooth_group(true)
	var lanes = _match_lanes()
	var lane_count = len(lanes)
	if lane_count == 0:
		# Invalid configuration or nothing to draw
		road_mesh.mesh = st.commit()
		return

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
		_insert_geo_loop(
			st, loop, loops, lanes,
			lane_count, clength,
			lane_uvs_length, per_loop_uv_size, uv_width)

	st.index()
	if material:
		st.set_material(material)
	st.generate_normals()
	road_mesh.mesh = st.commit()
	road_mesh.create_trimesh_collision() # Call deferred?
	road_mesh.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF


func _insert_geo_loop(
		st: SurfaceTool,
		loop: int,
		loops: int,
		lanes: Array,
		lane_count: int,
		clength: float,
		lane_uvs_length: Array,
		per_loop_uv_size: float,
		uv_width: float):
	# One loop = row of quads left to right across the road, spanning lanes.
	var offset_s = float(loop) / float(loops)
	var offset_e = float(loop + 1) / float(loops)

	# Apply ease in and out across all attributes.
	var offset_s_ease = ease(offset_s, smooth_amount)
	var offset_e_ease = ease(offset_e, smooth_amount)

	#if len(start_point.lanes) == len(end_point.lanes):
	var start_loop:Vector3
	var start_basis:Vector3
	var end_loop:Vector3
	var end_basis:Vector3
	start_loop = curve.interpolate_baked(offset_s * clength)
	start_basis = _normal_for_offset(curve, offset_s)
	end_loop = curve.interpolate_baked(offset_e * clength)
	end_basis = _normal_for_offset(curve, offset_e)

	#print("\tRunning loop %s: %s to %s; Start: %s,%s, end: %s,%s" % [
	#	loop, offset_s, offset_e, start_loop, start_basis, end_loop, end_basis
	#])

	# Calculate lane widths
	var near_width = lerp(start_point.lane_width, end_point.lane_width, offset_s_ease)
	var near_add_width = lerp(0, end_point.lane_width, offset_s_ease)
	var near_rem_width = lerp(start_point.lane_width, 0, offset_s_ease)
	var far_width = lerp(start_point.lane_width, end_point.lane_width, offset_e_ease)
	var far_add_width = lerp(0, end_point.lane_width, offset_e_ease)
	var far_rem_width = lerp(start_point.lane_width, 0, offset_e_ease)

	# Sum the lane widths and get position of left edge
	var near_width_offset
	var far_width_offset

	near_width_offset = -lerp(
			len(start_point.lanes) * start_point.lane_width,
			len(end_point.lanes) * end_point.lane_width,
			offset_s_ease
	) / 2.0
	far_width_offset = -lerp(
			len(start_point.lanes) * start_point.lane_width,
			len(end_point.lanes) * end_point.lane_width,
			offset_e_ease
	) / 2.0

	for i in range(lane_count):
		# Create the contents of a single lane / quad within this quad loop.
		var lane_offset_s = near_width_offset * start_basis
		var lane_offset_e = far_width_offset * end_basis
		var lane_near_width
		var lane_far_width

		# Set lane width for current lane type
		if lanes[i][0] == RoadPoint.LaneType.TRANSITION_ADD:
			lane_near_width = near_add_width
			lane_far_width = far_add_width
		elif lanes[i][0] == RoadPoint.LaneType.TRANSITION_REM:
			lane_near_width = near_rem_width
			lane_far_width = far_rem_width
		else:
			lane_near_width = near_width
			lane_far_width = far_width

		near_width_offset += lane_near_width
		far_width_offset += lane_far_width

		# Assume the start and end lanes are the same for now.
		var uv_l:float # the left edge of the uv for this lane.
		var uv_r:float
		match lanes[i][0]:
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
			RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.TRANSITION_REM:
				uv_l = uv_width * 7
				uv_r = uv_l + uv_width - 0.002
			_:
				uv_l = uv_width * 7
				uv_r = uv_l + uv_width
		if lanes[i][1] == RoadPoint.LaneDir.REVERSE:
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
				end_loop + end_basis * lane_far_width + lane_offset_e,
				end_loop + lane_offset_e,
				start_loop + lane_offset_s,
				start_loop + start_basis * lane_near_width + lane_offset_s,

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
		var uv_y_start
		var uv_y_end
		if len(lane_uvs_length) == 1:
			uv_y_start = lane_uvs_length[0]
			uv_y_end = lane_uvs_length[0] + per_loop_uv_size
		else:
			uv_y_start = lane_uvs_length[dir]
			uv_y_end = lane_uvs_length[dir] + per_loop_uv_size

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
			pos_far_l = far_width_offset + far_w_shoulder
			pos_far_r = far_width_offset
			pos_near_l = near_width_offset + near_w_shoulder
			pos_near_r = near_width_offset
			pos_far_gutter = pos_far_l
			pos_near_gutter = pos_near_l
		else:
			near_w_shoulder = lerp(start_point.shoulder_width_r, end_point.shoulder_width_r, offset_s)
			far_w_shoulder = lerp(start_point.shoulder_width_r, end_point.shoulder_width_r, offset_e)
			pos_far_l = far_width_offset
			pos_far_r = far_width_offset + far_w_shoulder
			pos_near_l = near_width_offset
			pos_near_r = near_width_offset + near_w_shoulder
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
				Vector2(uv_m if dir == 1 else uv_l, uv_y_end),
				Vector2(uv_r if dir == 1 else uv_m, uv_y_end),
				Vector2(uv_r if dir == 1 else uv_m, uv_y_start),
				Vector2(uv_m if dir == 1 else uv_l, uv_y_start),
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

## Evaluate start and end point Traffic Direction and Lane Type arrays. Match up
## the lanes whose directions match and create Add/Remove Transition lanes where
## the start or end points are missing lanes. Return an array that includes both
## full lanes and transition lanes.
## Returns: Array[
##   RoadPoint.LaneType, # To indicate texture, and whether an add/remove.
##   RoadPoint.LaneDir, # To indicate which direction the traffic goes.
##   lane_prior_tag, # Appropriate str for later connecting RoadLanes
##   lane_next_tag # Appropriate str for later connecting RoadLanes
## ]
func _match_lanes() -> Array:
	# Check for invalid lane configuration
	if len(start_point.traffic_dir) == 0 or len(end_point.traffic_dir) == 0:
		return []
	if (
		(start_point.traffic_dir[0] == RoadPoint.LaneDir.REVERSE
			and end_point.traffic_dir[0] == RoadPoint.LaneDir.FORWARD)
			or (start_point.traffic_dir[0] == RoadPoint.LaneDir.FORWARD
			and end_point.traffic_dir[0] == RoadPoint.LaneDir.REVERSE)
	):
		push_warning("Warning: Unable to match lanes on start_point %s" % start_point)
		return []

	var start_flip_data = _get_lane_flip_data(start_point)
	var start_flip_offset = start_flip_data[0]
	var start_traffic_dir = start_flip_data[1]
	var end_flip_data = _get_lane_flip_data(end_point)
	var end_flip_offset = end_flip_data[0]
	var end_traffic_dir = end_flip_data[1]

	# Bail on invalid flip offsets
	if start_flip_offset == -1 or end_flip_offset == -1:
		return []

	# Check for additional invalid lane configurations
	if (
		(start_traffic_dir == RoadPoint.LaneDir.REVERSE
			and end_traffic_dir == RoadPoint.LaneDir.BOTH)
		or (start_traffic_dir == RoadPoint.LaneDir.FORWARD
			and end_traffic_dir == RoadPoint.LaneDir.BOTH)
		or (start_traffic_dir == RoadPoint.LaneDir.BOTH
			and end_traffic_dir == RoadPoint.LaneDir.REVERSE)
		or (start_traffic_dir == RoadPoint.LaneDir.BOTH
			and end_traffic_dir == RoadPoint.LaneDir.FORWARD)
	):
		push_warning("Warning: Unable to match lanes on start_point %s" % start_point)
		return []

	# Build lanes list.
	var lanes: Array
	var range_to_check = max(len(start_point.traffic_dir), len(end_point.traffic_dir))

	# Handle FORWARD-only lane setups
	if (
		start_traffic_dir == RoadPoint.LaneDir.FORWARD
		and end_traffic_dir == RoadPoint.LaneDir.FORWARD
	):
		var last_same_i = 0 # last lane where F# was the same at start/end
		for i in range(range_to_check):
			if i < len(start_point.traffic_dir) and i < len(end_point.traffic_dir):
				lanes.append([
					start_point.lanes[i],
					RoadPoint.LaneDir.FORWARD,
					"F%s" % i,
					"F%s" % i])
				last_same_i = i
			elif i > len(start_point.traffic_dir) - 1:
				lanes.append([
					RoadPoint.LaneType.TRANSITION_ADD,
					RoadPoint.LaneDir.FORWARD,
					"F%sa" % last_same_i,
					"F%s" % i])
			elif i > len(end_point.traffic_dir) - 1:
				lanes.append([
					RoadPoint.LaneType.TRANSITION_REM,
					RoadPoint.LaneDir.FORWARD,
					"F%s" % i,
					"F%sr" % last_same_i])
	# Handle REVERSE-only lane setups
	elif (
		start_traffic_dir == RoadPoint.LaneDir.REVERSE
		and end_traffic_dir == RoadPoint.LaneDir.REVERSE
	):
		var last_same_i = 0 # last lane where F# was the same at start/end
		for i in range(range_to_check):
			if i < len(start_point.traffic_dir) and i < len(end_point.traffic_dir):
				lanes.push_front([
					start_point.lanes[-i - 1],
					RoadPoint.LaneDir.REVERSE,
					"R%s" % i,
					"R%s" % i])
				last_same_i = i
			elif i > len(end_point.traffic_dir) - 1:
				lanes.push_front([
					RoadPoint.LaneType.TRANSITION_REM,
					RoadPoint.LaneDir.REVERSE,
					"R%s" % i,
					"R%sr" % last_same_i])
			elif i > len(start_point.traffic_dir) - 1:
				lanes.push_front([
					RoadPoint.LaneType.TRANSITION_ADD,
					RoadPoint.LaneDir.REVERSE,
					"R%sa" % last_same_i,
					"R%s" % i])
	# Handle bi-directional lane setups
	else:
		# Match REVERSE lanes.
		# Iterate the start point REVERSE lanes. But, iterate the maximum number of
		# REVERSE lanes of the two road points. If the iterator goes below zero,
		# then assign TRANSITION_ADD lane(s). If the iterator is above -1 and
		# there is a lane on the end point, then assign the start point's LaneType.
		# If the iterator is above -1 and there are no more lanes on the end point,
		# then assign a TRANSITION_REM lane.
		var start_end_offset_diff = start_flip_offset - end_flip_offset
		range_to_check = start_flip_offset - max(start_flip_offset, end_flip_offset) - 1
		var last_same_i = -1 # last lane where R# was the same at start/end
		var curr_i = -1
		for i in range(start_flip_offset-1, range_to_check, -1):
			curr_i += 1
			if i < 0:
				# No pre-existing lane on start point. Add a lane.
				lanes.push_front([
					RoadPoint.LaneType.TRANSITION_ADD,
					RoadPoint.LaneDir.REVERSE,
					"R%sa" % last_same_i,
					"R%s" % curr_i])
			elif i > -1 and i - start_end_offset_diff < 0:
				# No pre-existing lane on end point. Remove a lane.
				lanes.push_front([
					RoadPoint.LaneType.TRANSITION_REM,
					RoadPoint.LaneDir.REVERSE,
					"R%s" % curr_i,
					"R%sr" % last_same_i])
			else:
				# Lane directions match. Add LaneType from start point.
				last_same_i += 1
				lanes.push_front([
					start_point.lanes[i],
					RoadPoint.LaneDir.REVERSE,
					"R%s" % curr_i,
					"R%s" % curr_i])

		# Match FORWARD lanes
		# Iterate the start point FORWARD lanes. But, iterate the maximum number of
		# FORWARD lanes of the two road points. If the iterator goes above the
		# length of start point lanes, then assign TRANSITION_ADD lane(s). If the
		# iterator is below the length of start point lanes and there is a lane on
		# the end point, then assign the start point's LaneType. If the iterator is
		# below the length of start point lanes and there are no more lanes on the
		# end point, then assign TRANSITION_REM lane(s).
		range_to_check = max(len(start_point.traffic_dir), len(end_point.traffic_dir) + start_end_offset_diff)
		last_same_i = 0 # last lane where F# was the same at start/end
		for i in range(start_flip_offset, range_to_check):
			if i > len(start_point.traffic_dir) - 1:
				# No pre-existing lane on start point. Add a lane.
				lanes.append([
					RoadPoint.LaneType.TRANSITION_ADD,
					RoadPoint.LaneDir.FORWARD,
					"F%sa" % last_same_i,
					"F%s" % (i - start_flip_offset)])
			elif i < len(start_point.traffic_dir) and i - start_end_offset_diff > len(end_point.traffic_dir) - 1:
				# No pre-existing lane on end point. Remove a lane.
				lanes.append([
					RoadPoint.LaneType.TRANSITION_REM,
					RoadPoint.LaneDir.FORWARD,
					"F%s" % (i - start_flip_offset),
					"F%sr" % last_same_i])
			elif i < len(start_point.lanes):
				# Lane directions match. Add LaneType from start point.
				lanes.append([
					start_point.lanes[i],
					RoadPoint.LaneDir.FORWARD,
					"F%s" % (i - start_flip_offset),
					"F%s" % (i - start_flip_offset)])
				last_same_i = (i - start_flip_offset)

	return lanes

## Evaluate the lanes of a RoadPoint and return the index of the direction flip
## from REVERSE to FORWARD. Return -1 if no flip was found. Also, return the
## overall traffic direction of the RoadPoint.
## Returns: Array[int, RoadPoint.LaneDir]
func _get_lane_flip_data(road_point: RoadPoint) -> Array:
	# Get lane FORWARD flip offset. If a flip occurs more than once, give
	# warning.
	var flip_offset = 0
	var flip_count = 0

	for i in range(len(road_point.traffic_dir)):
		if (
				# Save ID of first FORWARD lane
				road_point.traffic_dir[i] == RoadPoint.LaneDir.FORWARD
				and flip_count == 0
		):
			flip_offset = i
			flip_count += 1
		if (
				# Flag unwanted flips. REVERSE always comes before FORWARD.
				road_point.traffic_dir[i] == RoadPoint.LaneDir.REVERSE
				and flip_count > 0
		):
			push_warning("Warning: Unable to detect lane flip on road_point %s" % road_point)
			return [-1, RoadPoint.LaneDir.NONE]
		elif flip_count == 0 and i == len(road_point.traffic_dir) - 1:
			# This must be a REVERSE-only road point
			flip_offset = len(road_point.traffic_dir) - 1
			return [flip_offset, RoadPoint.LaneDir.REVERSE]
		elif flip_count == 1 and flip_offset == 0 and i == len(road_point.traffic_dir) - 1:
			# This must be a FORWARD-only road point
			flip_offset = len(road_point.traffic_dir) - 1
			return [flip_offset, RoadPoint.LaneDir.FORWARD]
	return [flip_offset, RoadPoint.LaneDir.BOTH]

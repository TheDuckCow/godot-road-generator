extends Node3D
## Create and hold the geometry of a segment of road, including its curve.
##
## Assume lazy evaluation, only adding nodes when explicitly requested, so that
## the structure stays light only until needed.
##
## Not defined with a ClassName, since this should be treated as internal
## functionality of how the road generation works, and may change.
##
## If necessary to reference like a class, place this in any script:
## const RoadSegment = preload("res://addons/road-generator/road_segment.gd")
#class_name RoadSegment, "road_segment.png"

const LOWPOLY_FACTOR = 3.0
const RAD_NINETY_DEG = PI/2 ## aka 1.5707963267949, used for offset_curve algorithm
const EDGE_R_NAME = "edge_R" ## Name of reverse lane edge curve
const EDGE_F_NAME = "edge_F" ## Name of forward lane edge curve
const EDGE_C_NAME = "edge_C" ## Name of road center (direction divider) edge curve

## Lookup for lane texture multiplier - corresponds to RoadPoint.LaneType enum
const uv_mul = [7, 0, 1, 2, 3, 4, 5, 6, 7, 7]

signal seg_ready(road_segment)

@export var start_init: NodePath: get = _init_start_get, set = _init_start_set
@export var end_init: NodePath: get = _init_end_get, set = _init_end_set

var start_point:RoadPoint
var end_point:RoadPoint

var curve:Curve3D
var road_mesh:MeshInstance3D
var material:Material
var density := 4.00 ## Distance between loops, bake_interval in m applied to curve for geo creation.
var container:RoadContainer ## The managing container node for this road segment (grandparent).

var is_dirty := true
var low_poly := false  # If true, then was (or will be) generated as low poly.

# Reference:
# https://raw.githubusercontent.com/godotengine/godot-docs/3.5/img/ease_cheatsheet.png
var smooth_amount := -2  # Ease in/out smooth, used with ease built function

# Cache for matched lanes, result of _match_lanes() func
var _matched_lanes: Array = []

# Indicator that this sequence is the connection of two "Next's" or two "Prior's"
# and therefore we need to do some flipping around.
var _start_flip: bool = false
var _end_flip: bool = false
# For easier calculation, to account for flipped directions.
var _start_flip_mult: int = 1
var _end_flip_mult: int = 1

## For iteration on values related to Near(start) or Far(end) points of a segment
enum NearFar {
	NEAR,
	FAR
}

## For iteration on values related to Left or Right sides of a segment
enum LeftRight {
	LEFT,
	RIGHT
}


# ------------------------------------------------------------------------------
# Setup and export setter/getters
# ------------------------------------------------------------------------------


func _init(_container):
	if not _container:
		push_error("Invalid container assigned")
		return
	container = _container
	curve = Curve3D.new()



func _ready():
	do_roadmesh_creation()
	if container.debug_scene_visible and is_instance_valid(road_mesh):
		road_mesh.owner = container.get_owner()


# Workaround for cyclic typing
func is_road_segment() -> bool:
	return true


func should_add_mesh() -> bool:
	var should_add_mesh = true
	var par = get_parent()
	if not is_instance_valid(par) or not par is RoadPoint:
		return should_add_mesh

	if par.create_geo == false:
		should_add_mesh = false

	if container.create_geo == false:
		should_add_mesh = false

	return should_add_mesh


func do_roadmesh_creation():
	var do_create := should_add_mesh()
	if do_create:
		add_road_mesh()
	else:
		remove_road_mesh()


func add_road_mesh() -> void:
	if is_instance_valid(road_mesh):
		return
	road_mesh = MeshInstance3D.new()
	add_child(road_mesh)
	road_mesh.name = "road_mesh"
	if container.debug_scene_visible and is_instance_valid(road_mesh):
		road_mesh.owner = container.get_owner()


func remove_road_mesh():
	if road_mesh == null:
		return
	road_mesh.queue_free()


## Unique identifier for a segment based on what its connected to.
func get_id() -> String:
	name = get_id_for_points(start_point, end_point)
	return name


## Generic function for getting a consistent ID given a start and end point
static func get_id_for_points(_start:RoadPoint, _end:RoadPoint) -> String:
	var id: String
	if _start and _end:
		var start_id = _start.get_instance_id()
		var end_id = _end.get_instance_id()
		if start_id < end_id:
			id = "%s-%s" % [start_id, end_id]
		else:
			id = "%s-%s" % [end_id, start_id]
	elif _start:
		id = "%s-x" % _start.get_instance_id()
	elif _end:
		id = "x-%s" % _end.get_instance_id()
	else:
		id = "x-x"
	return id


# ------------------------------------------------------------------------------
# Export callbacks
# ------------------------------------------------------------------------------

func _init_start_set(value):
	start_init = value
	is_dirty = true
	if not is_instance_valid(container):
		return
func _init_start_get():
	return start_init


func _init_end_set(value):
	end_init = value
	is_dirty = true
	if not is_instance_valid(container):
		return
func _init_end_get():
	return end_init


## Check if needing to be rebuilt.
## Returns true if rebuild was done, else (including if invalid) false.
func check_rebuild() -> bool:
	if is_queued_for_deletion():
		return false
	if not is_instance_valid(container):
		return false
	if not is_instance_valid(start_point) or not is_instance_valid(end_point):
		return false

	if _start_flip:
		start_point.prior_seg = self
		_start_flip_mult = -1
	else:
		start_point.next_seg = self
		_start_flip_mult = 1
	if _end_flip:
		end_point.next_seg = self
		_end_flip_mult = -1
	else:
		end_point.prior_seg = self
		_end_flip_mult = 1

	# Build lane cache, to be used once only
	_matched_lanes = _match_lanes()

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


func generate_edge_curves():
	if not is_instance_valid(container):
		return
	if not is_instance_valid(start_point) or not is_instance_valid(end_point):
		return
	if not container.create_edge_curves:
		clear_edge_curves()
		return

	# Find the road edge positions
	if _matched_lanes == []:
		_matched_lanes = self._match_lanes()

	if len(_matched_lanes) == 0:
		return

	var _par = get_parent()

	var start_offset_R
	var start_offset_F
	var end_offset_R
	var end_offset_F
	if start_point.alignment == RoadPoint.Alignment.GEOMETRIC:
		var start_half_width: float = len(start_point.lanes) * start_point.lane_width * 0.5
		start_offset_R = start_half_width
		start_offset_F = start_half_width
	else:
		assert( start_point.alignment == RoadPoint.Alignment.DIVIDER )
		start_offset_R = start_point.get_rev_lane_count() * start_point.lane_width
		start_offset_F = start_point.get_fwd_lane_count() * start_point.lane_width
	if end_point.alignment == RoadPoint.Alignment.GEOMETRIC:
		var end_half_width: float = len(end_point.lanes) * end_point.lane_width * 0.5
		end_offset_R = end_half_width
		end_offset_F = end_half_width
	else:
		assert( end_point.alignment == RoadPoint.Alignment.DIVIDER )
		end_offset_R = end_point.get_rev_lane_count() * end_point.lane_width
		end_offset_F = end_point.get_fwd_lane_count() * end_point.lane_width

	# Add edge curves
	var edge_R: Path3D = _par.get_node_or_null(EDGE_R_NAME)
	var edge_F: Path3D = _par.get_node_or_null(EDGE_F_NAME)
	var extra_offset: float = 0.0
	start_offset_R += start_point.shoulder_width_r + start_point.gutter_profile[0] + extra_offset
	start_offset_F += start_point.shoulder_width_l + start_point.gutter_profile[0] + extra_offset
	end_offset_R += end_point.shoulder_width_r + end_point.gutter_profile[0] + extra_offset
	end_offset_F += end_point.shoulder_width_l + end_point.gutter_profile[0] + extra_offset

	if edge_R == null or not is_instance_valid(edge_R):
		edge_R = Path3D.new()
		edge_R.name = EDGE_R_NAME
		_par.add_child(edge_R)
		edge_R.owner = _par.owner
		edge_R.set_meta("_edit_lock_", true)
	edge_R.curve = Curve3D.new()
	offset_curve(self, edge_R, -start_offset_R, -end_offset_R, start_point, end_point, false)

	if edge_F == null or not is_instance_valid(edge_F):
		edge_F = Path3D.new()
		edge_F.name = EDGE_F_NAME
		_par.add_child(edge_F)
		edge_F.owner = _par.owner
		edge_F.set_meta("_edit_lock_", true)
	edge_F.curve = Curve3D.new()
	offset_curve(self, edge_F, start_offset_F, end_offset_F, start_point, end_point, false)

	# Add center curve
	var edge_C: Path3D = _par.get_node_or_null(EDGE_C_NAME)
	var start_offset_C: float = 0
	var end_offset_C: float = 0

	if edge_C == null or not is_instance_valid(edge_C):
		edge_C = Path3D.new()
		edge_C.name = EDGE_C_NAME
		_par.add_child(edge_C)
		edge_C.owner = _par.owner
		edge_C.set_meta("_edit_lock_", true)
	edge_C.curve = Curve3D.new()
	offset_curve(self, edge_C, start_offset_C, end_offset_C, start_point, end_point, false)


## Utility to auto generate all road lanes for this road for use by AI.
##
## debug: No longer used, kept for backwards compatibility.
##
## Returns true if any lanes generated, false if not.
func generate_lane_segments(_debug: bool = false) -> bool:
	if not is_instance_valid(container):
		return false
	if not is_instance_valid(start_point) or not is_instance_valid(end_point):
		return false

	# First identify all road lanes that will exist.
	if _matched_lanes == []:
		_matched_lanes = self._match_lanes()
	if len(_matched_lanes) == 0:
		return false
	
	var start_lane_offset
	var end_lane_offset
	if start_point.alignment == RoadPoint.Alignment.DIVIDER:
		start_lane_offset = start_point.get_rev_lane_count()
	else:
		assert( start_point.alignment == RoadPoint.Alignment.GEOMETRIC )
		start_lane_offset = len(start_point.lanes) / 2.0

	var manager:RoadManager = container.get_manager()
	if end_point.alignment == RoadPoint.Alignment.DIVIDER:
		end_lane_offset = end_point.get_rev_lane_count()
	else:
		assert( end_point.alignment == RoadPoint.Alignment.GEOMETRIC )
		end_lane_offset = len(end_point.lanes) / 2.0

	var start_offset = (start_lane_offset - 0.5) * start_point.lane_width
	var end_offset = (end_lane_offset - 0.5) * end_point.lane_width

	# Tracker used during the loop, to sum offset to apply.
	var lanes_added := 0

	# Assist var to assign lane_right and lane_left, used by AI for lane changes
	var last_ln = null
	var last_ln_reverse: bool

	# Cache for sparse node removal
	var active_lanes = []

	var _par = get_parent() # Add RoadLanes to the parent RoadPoint, with option to add as children directly.

	# We need to keep track of the number of reverse and forward lane
	# additions and substractions to calculate which lanes are going to get merged.
	# Only expecting additions or substractions, not both at the same time (for each direction separately)
	var lane_shift := {"reverse": 0, "forward": 0}

	var _tmppar = _par.get_children()
	for this_match in _matched_lanes:
		# Reusable name to check for and re-use, based on "tagged names".
		var ln_name = "p%s_n%s" % [this_match[2], this_match[3]]

		var ln_type: int = this_match[0] # Enum RoadPoint.LaneType
		var ln_dir: int = this_match[1] # Enum RoadPoint.LaneDir

		# TODO: Check for existing lanes and reuse (but also clean up if needed)
		# var ln_child = self.get_node_or_null(ln_name)
		var ln_child = null
		ln_child = _par.get_node_or_null(ln_name)
		if not is_instance_valid(ln_child) or not ln_child is RoadLane:
			ln_child = RoadLane.new()
			_par.add_child(ln_child)
			if container.debug_scene_visible:
				ln_child.owner = container.get_owner()
			
			if container.ai_lane_group != "":
				ln_child.add_to_group(container.ai_lane_group)
			elif is_instance_valid(manager) and manager.ai_lane_group != "":
				ln_child.add_to_group(manager.ai_lane_group)
			ln_child.set_meta("_edit_lock_", true)
			ln_child.auto_free_vehicles = container.auto_free_vehicles
		else:
			ln_child.curve.clear_points()
		var new_ln:RoadLane = ln_child
		active_lanes.append(new_ln)

		# Assign the in and out lane tags, to help with connecting to other
		# road lanes later (handled by RoadContainer).
		new_ln.lane_prior_tag = this_match[2]
		new_ln.lane_next_tag = this_match[3]
		new_ln.name = ln_name

		var tmp = get_transition_offset(
			ln_type, ln_dir, lane_shift)
		var start_shift:float = tmp[0]
		var end_shift:float = tmp[1]
		var in_offset = lanes_added * start_point.lane_width - start_offset + start_shift
		var out_offset = lanes_added * end_point.lane_width - end_offset + end_shift

		# Set direction
		# TODO: When directionality is made consistent, we should no longer
		# need to invert the direction assignment here.
		var new_ln_reverse = true if ln_dir != RoadPoint.LaneDir.REVERSE else false

		if ln_type == RoadPoint.LaneType.TRANSITION_ADD || ln_type == RoadPoint.LaneType.TRANSITION_REM:
			new_ln.transition = true

		# TODO(#46): Swtich to re-sampling and adding more points following the
		# curve along from the parent path generator, including its use of ease
		# in and out at the edges.
		offset_curve(self, new_ln, in_offset, out_offset, start_point, end_point, new_ln_reverse)

		# Visually display if indicated, and not mid transform (low_poly)
		if low_poly:
			new_ln.draw_in_editor = false
		else:
			new_ln.draw_in_editor = container.draw_lanes_editor
		new_ln.draw_in_game = container.draw_lanes_game
		new_ln.refresh_geom = true
		new_ln.rebuild_geom()

		# Update lane connectedness for left/right lane connections.
		if not last_ln == null and last_ln_reverse == new_ln_reverse:
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
		lanes_added += 1
		last_ln = new_ln # For the next loop iteration.
		last_ln_reverse = new_ln_reverse
	clear_lane_segments(active_lanes)

	return lanes_added > 0


## Offsets a destination curve from a source curve by a specified distance.
##
##  Evaluates 4 points on source curve: Point 0 and 1 positions as well as
##  point-0-out and point-1-in handles. Requires transforms for point 0
##  and point 1, which determine the direction of the handles. Calculates best
##  fit position for destination curve given the supplied curves, transforms,
##  and distance.
##
##  For more details and context: https://github.com/TheDuckCow/godot-road-generator/issues/46
func offset_curve(road_seg: Node3D, road_lane: Path3D, in_offset: float, out_offset: float, start_point: Node3D, end_point: Node3D, reverse: bool) -> void:
	var src: Curve3D = road_seg.curve
	var dst: Curve3D = road_lane.curve
	
	# Transformations in local space relative to the road_lane
	var a_transform := road_lane.global_transform.affine_inverse() * start_point.global_transform
	var d_transform := road_lane.global_transform.affine_inverse() * end_point.global_transform
	
	var a_gbasis := a_transform.basis
	var d_gbasis := d_transform.basis
	
	var in_pos := a_transform.origin + (a_gbasis.x * in_offset * _start_flip_mult)
	var out_pos := d_transform.origin + (d_gbasis.x * out_offset * _end_flip_mult)

	# Get initial point locations in local space
	var pt_a := src.get_point_position(0)
	var pt_b := src.get_point_position(0) + src.get_point_out(0)
	var pt_c := src.get_point_position(1) + src.get_point_in(1)
	var pt_d := src.get_point_position(1)
	
	# Project the primary curve points onto the road_lane
	var pt_e := a_transform.origin + (a_gbasis.x * in_offset)
	var pt_i := pt_b + (a_gbasis.x * in_offset)
	var pt_h := d_transform.origin + (d_gbasis.x * out_offset)
	var pt_j := pt_c + (d_gbasis.x * out_offset)

	# Calculate vectors and angles
	var vec_ab := pt_b - pt_a
	var vec_bc := pt_c - pt_b
	var vec_cd := pt_d - pt_c
	
	var angle_q := -vec_ab.signed_angle_to(vec_bc, a_gbasis.y) * 0.5
	var angle_s := vec_cd.signed_angle_to(vec_bc, d_gbasis.y) * 0.5
	
	var offset_q := tan(angle_q) * in_offset
	var offset_s := tan(angle_s) * out_offset
	
	# Calculate adjusted handles using local coordinates
	var pt_f := a_gbasis.z * (vec_ab.length() + offset_q)
	var pt_g := -d_gbasis.z * (vec_cd.length() + offset_s)
	
	var margin := 0.1745329  # roughly 10 degrees
	
	# Calculate final in/out points and positions in local space
	var in_pt_in := pt_a
	var in_pt_out: Vector3
	var out_pt_in: Vector3
	var out_pt_out := pt_d
	
	in_pos = pt_e
	out_pos = pt_h
	
	# Adjust for harsh angles at the "in" point
	if abs(angle_q) > RAD_NINETY_DEG - margin and abs(angle_q) < RAD_NINETY_DEG + margin:
		in_pt_out = pt_b
	else:
		in_pt_out = pt_f

	# Adjust for harsh angles at the "out" point
	if abs(angle_s) > RAD_NINETY_DEG - margin and abs(angle_s) < RAD_NINETY_DEG + margin:
		out_pt_in = pt_c
	else:
		out_pt_in = pt_g
	
	# Set points in the destination curve
	dst.clear_points()
	if reverse:
		dst.add_point(out_pos, out_pt_out, out_pt_in)
		dst.add_point(in_pos, in_pt_out, in_pt_in)
	else:
		dst.add_point(in_pos, in_pt_in, in_pt_out)
		dst.add_point(out_pos, out_pt_in, out_pt_out)


## Offset the curve in/out points based on lane index.
##
## Track the init (for reverse) or the stacking (fwd) number of
## transition lanes to offset.
##
## Note: lane_shift is passed by reference and mutated.
func get_transition_offset(
		ln_type: int,
		ln_dir: int,
		lane_shift: Dictionary) -> Array:

	var start_shift: float = 0
	var end_shift: float = 0

	start_shift = min(lane_shift.reverse, 0)
	end_shift = -max(lane_shift.reverse, 0)
	# Forward cases
	if ln_dir == RoadPoint.LaneDir.FORWARD:
		if ln_type == RoadPoint.LaneType.TRANSITION_ADD:
			assert(lane_shift.forward <= 0)
			lane_shift.forward -= 1
			start_shift += lane_shift.forward
		if ln_type == RoadPoint.LaneType.TRANSITION_REM:
			assert(lane_shift.forward >= 0)
			lane_shift.forward += 1
			end_shift -= lane_shift.forward
	## Reverse cases
	elif ln_dir == RoadPoint.LaneDir.REVERSE:
		if ln_type == RoadPoint.LaneType.TRANSITION_ADD:
			assert(lane_shift.reverse <= 0)
			start_shift = lane_shift.reverse
			lane_shift.reverse -= 1
		elif ln_type == RoadPoint.LaneType.TRANSITION_REM:
			assert(lane_shift.reverse >= 0)
			end_shift = -lane_shift.reverse
			lane_shift.reverse += 1
	#else:
	# General non transition case, but should be reverse=0 by now.

	start_shift *= start_point.lane_width
	end_shift *= end_point.lane_width

	return [start_shift, end_shift]


## Returns list of only valid RoadLanes
func get_lanes() -> Array:
	var lanes = []
	var _par = get_parent()
	for ch in _par.get_children():
		if not is_instance_valid(ch):
			continue
		elif not ch is RoadLane:
			# push_warning("Child of RoadSegment is not a RoadLane: %s" % ln.name)
			continue
		lanes.append(ch)
	return lanes


## Remove all RoadLanes attached to this RoadSegment
func clear_lane_segments(ignore_list: Array = []) -> void:
	var _par = get_parent()
	for ch in _par.get_children():
		if ch in ignore_list:
			continue
		if ch is RoadLane:
			ch.queue_free()
	# Legacy, RoadLanes used to be children of the segment class, but are now
	# direct children of the RoadPoint with the option to be visualized in editor later.
	for ch in get_children():
		if ch in ignore_list:
			continue
		if ch is RoadLane:
			ch.queue_free()


## Remove all edge curves attached to this RoadSegment
func clear_edge_curves():
	var _par = get_parent()
	for ch in _par.get_children():
		if ch is Path3D and ch.name in [EDGE_R_NAME, EDGE_F_NAME, EDGE_C_NAME]:
			for gch in ch.get_children():
				ch.remove_child(gch)
				gch.queue_free()
			_par.remove_child(ch)
			ch.queue_free()


## Shows/hides edge curves.
func hide_edge_curves(hide_edge: bool = false):
	var _par = get_parent()
	for ch in _par.get_children():
		if ch is Path3D and (ch.name == "edge_R" or ch.name == "edge_F"):
			ch.visible = not hide_edge


func update_lane_visibility():
	for lane in get_lanes():
		lane.draw_in_editor = container.draw_lanes_editor
		lane.draw_in_game = container.draw_lanes_game


# ------------------------------------------------------------------------------
# Geometry construction
# ------------------------------------------------------------------------------

## Construct the geometry of this road segment.
func _rebuild():
	if is_queued_for_deletion():
		return

	get_id()
	if not container or not is_instance_valid(container):
		pass
	elif container.density > 0:
		density = container.density
	elif is_instance_valid(container.get_manager()):
		density = container.get_manager().density
	else:
		pass

	# Reset its transform to undo the rotation of the parent
	var tr = get_parent().transform
	transform = tr.inverse()

	# Reposition this node to be physically located between both RoadPoints.
	global_transform.origin = (
		start_point.global_transform.origin + start_point.global_transform.origin) / 2.0

	_update_curve()

	# Create a low and high poly road, start with low poly.
	_build_geo()

	if container.create_edge_curves:
		generate_edge_curves()
	else:
		clear_edge_curves()

	if container.generate_ai_lanes:
		generate_lane_segments()
	else:
		clear_lane_segments()


func _update_curve():
	curve.clear_points()
	curve.bake_interval = density # Spacing in meters between loops.
	# path.transform.origin = Vector3.ZERO
	# path.transform.scaled(Vector3.ONE)
	# path.transform. clear rotation.

	# Setup in and out handle of curve points
	var start_mag = start_point.next_mag if _start_flip == false else start_point.prior_mag
	_set_curve_point(curve, start_point, start_mag, _start_flip_mult)
	var end_mag = end_point.prior_mag if _end_flip == false else end_point.next_mag
	_set_curve_point(curve, end_point, end_mag, _end_flip_mult)

	# Show this primary curve in the scene hierarchy if the debug state set.
	if container.debug_scene_visible:
		var found_path = false
		var path_node: Path3D
		for ch in self.get_children():
			if not ch is Path3D:
				continue
			found_path = true
			path_node = ch
			break

		if not found_path:
			path_node = Path3D.new()
			self.add_child(path_node)
			path_node.owner = container.get_owner()
			path_node.name = "RoadSeg primary curve"
		path_node.curve = curve

## Helper to set a curve point taking into account transform of rp (if parent)
func _set_curve_point(_curve: Curve3D, rp: RoadPoint, mag_val: float, flip_fac: int) ->  void:
	var pos_g = rp.global_transform.origin
	var pos = to_local(pos_g)
	var handle_in = rp.global_transform.basis.z * -mag_val * flip_fac
	var handle_out = rp.global_transform.basis.z * mag_val * flip_fac
	var handle_in_l = to_local(handle_in + pos_g)
	var handle_out_l = to_local(handle_out + pos_g)
	_curve.add_point(pos, handle_in_l-pos, handle_out_l-pos)
	# curve.set_point_tilt(1, end_point.rotation.z)  # Doing custom interpolation, skip this.


## Calculates the horizontal vector of a Segment geometry loop. Interpolates
## between the start and end points. Applies "easing" to prevent potentially
## unwanted rotation on the loops at the ends of the curve.
## Inputs:
## curve - The curve this Segment will follow.
## sample_position - Curve sample position 0.0 - 1.0 to use for interpolation. Normalized.
## Returns: Normalized Vector3 in local space.
func _normal_for_offset(curve: Curve3D, sample_position: float) -> Vector3:
	# Calculate interpolation amount for curve sample point
	return _normal_for_offset_eased(curve, sample_position)
	#return _normal_for_offset_legacy(curve, sample_position)


## Alternate method which doesn't guarentee consistent lane width.
func _normal_for_offset_legacy(curve: Curve3D, sample_position: float) -> Vector3:
	var loop_point: Transform3D
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
		# Use exact basis of RoadPoint to ensure geometry lines up.
		return start_point.transform.basis.x * _start_flip_mult
	elif sample_position >= 1.0 - offset_amount * 0.5:
		# Use exact basis of RoadPoint to ensure geometry lines up.
		return end_point.transform.basis.x * _end_flip_mult
	else:
		start_offset = sample_position - offset_amount * 0.5
		end_offset = sample_position + offset_amount * 0.5

	var pt1:Vector3 = curve.sample_baked(start_offset * curve.get_baked_length())
	var pt2:Vector3 = curve.sample_baked(end_offset * curve.get_baked_length())
	var tangent_l:Vector3 = pt2 - pt1

	# Using local transforms. Both are transforms relative to the parent RoadContainer,
	# and the current mesh we are writing to already has the inverse of the start_point
	# (or whichever it is parented to) rotation applied. Not affected by _flip_mult.
	var start_up = start_point.transform.basis.y
	var end_up = end_point.transform.basis.y

	var up_vec_l:Vector3 = lerp(
		start_up.normalized(),
		end_up.normalized(),
		sample_position)
	var normal_l = up_vec_l.cross(tangent_l)

	#var sample_eased = ease(sample_position, smooth_amount)

	return normal_l.normalized()

## @babybedbug's first code contribution! It's not functional code, but hey.
#func build_grandparent(car):
#	var beep = "ctylicious"
#	var st = not in_my backyard
#	if stroad_count AudioEffectEQ10
#	&hearts; @ the gig
#	<i> divas are working </i>
#	knock knock
#	divas are putting their lashes on
#	return xoxoxo


func _build_geo():
	if not is_instance_valid(road_mesh):
		return
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	#st.add_smooth_group(true)
	var lane_count := len(_matched_lanes)
	if lane_count == 0:
		# Invalid configuration or nothing to draw
		road_mesh.mesh = st.commit()
		return

	var clength = curve.get_baked_length()
	# In this context, loop refers to "quad" faces, not the edges, as it will
	# be a loop of generated faces.
	var loops: int
	if low_poly: # one third the geo
		# Remove all loops between road points, so it's a straight mesh with no
		# loops. In the future, this could be reduce to just a lower density.
		# This makes interactivity in the UI much faster, but could also work for
		# in-game LODs.
		loops = int(max(floor(clength / density / LOWPOLY_FACTOR), 1.0)) # Need at least 1 loop.
	else:
		loops = int(max(floor(clength / density), 1.0)) # Need at least 1 loop.

	# Keep track of UV position over lane, to be seamless within the segment.
	var lane_uvs_length := []
	for ln in range(lane_count):
		lane_uvs_length.append(0)

	# Number of times the UV will wrap, to ensure seamless at next RoadPoint.
	#
	# Use the minimum sized road width for counting.
	var min_road_width:float = min(start_point.lane_width, end_point.lane_width)
	# Aim for real-world texture proportions width:height of 2:1 matching texture,
	# but then the hight of 1 full UV is half the with across all lanes, so another 2x
	var single_uv_height:float = min_road_width * 4.0
	var target_uv_tiles:int = int(clength / single_uv_height)
	var per_loop_uv_size:float = float(target_uv_tiles) / float(loops)
	var uv_width := 0.125 # 1/8 for breakdown of texture.

	#print_debug("(re)building %s: Seg gen: %s loops, length: %s, lp: %s" % [
	#	self.name, loops, clength, low_poly])

	for loop in range(loops):
		_insert_geo_loop(
			st, loop, loops, _matched_lanes,
			lane_count, clength,
			lane_uvs_length, per_loop_uv_size, uv_width)

	st.index()
	if material:
		st.set_material(material)
	st.generate_normals()
	road_mesh.mesh = st.commit()
	road_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_create_collisions()


func _create_collisions() -> void:
	for ch in road_mesh.get_children():
		ch.queue_free()  # Prior collision meshes
	
	var manager:RoadManager = container.get_manager()

	# Could also manually create with Mesh.create_trimesh_shape(),
	# but this is still advertised as a non-cheap solution.
	road_mesh.create_trimesh_collision()
	for ch in road_mesh.get_children():
		var sbody := ch as StaticBody3D # Set to null if casting fails
		if not sbody:
			continue
		
		if container.collider_group_name != "":
			sbody.add_to_group(container.collider_group_name)
		elif is_instance_valid(manager) and manager.collider_group_name != "":
			sbody.add_to_group(manager.collider_group_name)
		
		if container.collider_meta_name != "":
			sbody.set_meta(container.collider_meta_name, true)
		elif is_instance_valid(manager) and manager.collider_meta_name != "":
			sbody.set_meta(manager.collider_meta_name, true)
		
		if container.physics_material != null:
			sbody.physics_material_override = container.physics_material
		elif is_instance_valid(manager) and manager.physics_material != null:
			sbody.physics_material_override = manager.physics_material
		
		if container.override_collision_layers:
			sbody.collision_layer = container.collision_layer
			sbody.collision_mask = container.collision_mask
		elif is_instance_valid(manager):
			sbody.collision_layer = manager.collision_layer
			sbody.collision_mask = manager.collision_mask
		# else: will just be the godot default.
		
		sbody.set_meta("_edit_lock_", true)


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
	assert (loop < loops)
	
	# One loop = row of quads left to right across the road, spanning lanes.
	var offset = [float(loop) / float(loops), float(loop + 1) / float(loops)]
	var point = [start_point, end_point]

	var lane_offset = []
	for nf in NearFar.values():
		lane_offset.append(len(point[nf].lanes) / 2.0)
	if start_point.alignment == RoadPoint.Alignment.DIVIDER || \
		end_point.alignment == RoadPoint.Alignment.DIVIDER:
		var nf_reverse = [0, 0]
		for l in lanes:
			if l[1] == RoadPoint.LaneDir.REVERSE:
				if l[0] == RoadPoint.LaneType.TRANSITION_ADD:
					nf_reverse[NearFar.FAR] += 1
				elif l[0] == RoadPoint.LaneType.TRANSITION_REM:
					nf_reverse[NearFar.NEAR] += 1
				elif l[0] != RoadPoint.LaneType.SHOULDER:
					nf_reverse[NearFar.NEAR] += 1
					nf_reverse[NearFar.FAR] += 1
			else:
				assert (l[1] == RoadPoint.LaneDir.FORWARD)
		for nf in NearFar.values():
			if point[nf].alignment == RoadPoint.Alignment.DIVIDER:
				lane_offset[nf] = nf_reverse[nf]

	var nf_loop = [null, null]
	var nf_basis = [null, null]
	var nf_width = [null, null]
	var add_width = [null, null]
	var rem_width = [null, null]

	var width_offset = [[null, null], [null, null]] #width_offset[LeftRight][NearFar]

	for nf in NearFar.values():
		# Apply ease in and out across all attributes.
		var offset_ease = ease(offset[nf], smooth_amount)
		nf_loop[nf] = curve.sample_baked(offset[nf] * clength)
		nf_basis[nf] = _normal_for_offset(curve, offset[nf])

		# Calculate lane widths
		nf_width[nf] = lerp(start_point.lane_width, end_point.lane_width, offset_ease)
		add_width[nf] = lerp(0.0, end_point.lane_width, offset_ease)
		rem_width[nf] = lerp(start_point.lane_width, 0.0, offset_ease)
		# Sum the lane widths and get position of left edge
		width_offset[LeftRight.LEFT][nf] = lerp(
				lane_offset[NearFar.NEAR] * start_point.lane_width,
				lane_offset[NearFar.FAR] * end_point.lane_width,
				offset_ease
		)
		width_offset[LeftRight.RIGHT][nf] = -width_offset[LeftRight.LEFT][nf]

	#print("\tRunning loop %s: %s to %s; Start: %s,%s, end: %s,%s" % [
	#	loop, offset[NearFar.NEAR], offset[NearFar.FAR], nf_loop[NearFar.NEAR], nf_basis[NearFar.NEAR], nf_loop[NearFar.FAR], nf_basis[NearFar.FAR]
	#])

	for i in range(lane_count):
		# Create the contents of a single lane / quad within this quad loop.
		var lane_offset_nf = [0, 0]
		var lane_width = [0, 0]
		for nf in NearFar.values():
			lane_offset_nf[nf] = width_offset[LeftRight.RIGHT][nf] * nf_basis[nf]

			# Set lane width for current lane type
			if lanes[i][0] == RoadPoint.LaneType.TRANSITION_ADD:
				lane_width[nf] = add_width[nf]
			elif lanes[i][0] == RoadPoint.LaneType.TRANSITION_REM:
				lane_width[nf] = rem_width[nf]
			else:
				lane_width[nf] = nf_width[nf]

		# Assume the start and end lanes are the same for now.
		var uv_l:float # the left edge of the uv for this lane.
		var uv_r:float
		assert (len(uv_mul) == len(RoadPoint.LaneType.values()))
		uv_l = uv_width * uv_mul[lanes[i][0]]
		uv_r = uv_l + uv_width
		if lanes[i][0] == RoadPoint.LaneType.TRANSITION_ADD || lanes[i][0] == RoadPoint.LaneType.TRANSITION_REM:
			uv_r -= 0.002
		var flipped = (lanes[i][0] == RoadPoint.LaneType.TWO_WAY || lanes[i][0] == RoadPoint.LaneType.ONE_WAY)
		if (lanes[i][1] == RoadPoint.LaneDir.REVERSE) != flipped:
			var tmp = uv_r
			uv_r = uv_l
			uv_l = tmp

		# uv offset continuation for this lane.
		var uv_y = [lane_uvs_length[i], lane_uvs_length[i] + per_loop_uv_size]
		lane_uvs_length[i] = uv_y[NearFar.FAR] # For next loop to use.
		#print("Seg: %s, lane:%s, uv %s-%s" % [
		#	self.name, loop, uv_y[NearFar.NEAR], uv_y[NearFar.FAR]])

		# Prepare attributes for add_vertex.
		# Long edge towards origin, p1
		quad( st, uv_square(uv_l, uv_r, uv_y),
			pts_square(nf_loop, nf_basis,
				[(width_offset[LeftRight.RIGHT][NearFar.FAR] + lane_width[NearFar.FAR]),
				width_offset[LeftRight.RIGHT][NearFar.FAR],
				width_offset[LeftRight.RIGHT][NearFar.NEAR],
				(width_offset[LeftRight.RIGHT][NearFar.NEAR] + lane_width[NearFar.NEAR])
				]) )
		for nf in NearFar.values():
			width_offset[LeftRight.RIGHT][nf] += lane_width[nf]

	var gutr_x = [null, null]
	var gutr_y = [null, null]
	var w_shoulder = [[null, null], [null, null]] #w_shoulder[LeftRight][NearFar]
	for nf in NearFar.values():
		w_shoulder[LeftRight.LEFT][nf]  = lerp(start_point.shoulder_width_l, end_point.shoulder_width_l, offset[nf])
		w_shoulder[LeftRight.RIGHT][nf] = lerp(start_point.shoulder_width_r, end_point.shoulder_width_r, offset[nf])

		# Gutter depth is the same for the left and right sides.
		gutr_x[nf] = lerp(start_point.gutter_profile.x, end_point.gutter_profile.x, offset[nf])
		gutr_y[nf] = lerp(start_point.gutter_profile.y, end_point.gutter_profile.y, offset[nf])
	# Now create the shoulder geometry, including the "bevel" geo.
	for lr in LeftRight.values():
		var dir = -1 if lr==0 else 1
		var uv_y = [null, null]
		var lane_uvx_ix = dir
		if len(lane_uvs_length) == 1:
			lane_uvx_ix = 0
		uv_y = [ lane_uvs_length[lane_uvx_ix], lane_uvs_length[lane_uvx_ix] + per_loop_uv_size ]

		# Account for custom left/right shoulder width.
		var pos_l = [dir, dir]
		var pos_r = [dir, dir]
		for nf in NearFar.values():
			var pos_gutter = width_offset[lr][nf] + w_shoulder[lr][nf]
			if lr == LeftRight.RIGHT:
				pos_l[nf] *= pos_gutter
				pos_r[nf] *= width_offset[lr][nf]
			else:
				pos_l[nf] *= width_offset[lr][nf]
				pos_r[nf] *= pos_gutter

		# Assume the start and end lanes are the same for now.
		var uv_mid = 0.8 # should be more like 0.9
		var uv_m = uv_mid * uv_width # The 'middle' vert, same level as shoulder but to edge.
		# LEFT (between pos:_s and _m, and between uv:_l and _m)
		# The flat part of the shoulder on both sides

		quad( st, uv_square(uv_m, uv_width, uv_y) if lr == LeftRight.RIGHT else uv_square(uv_width, uv_m, uv_y),
			pts_square(nf_loop, nf_basis, [pos_l[NearFar.FAR], pos_r[NearFar.FAR], pos_r[NearFar.NEAR], pos_l[NearFar.NEAR]]) )

		# The gutter, lower part of the shoulder on both sides.
		if lr == LeftRight.RIGHT:
			quad( st, uv_square(0, uv_m, uv_y),
				pts_square(nf_loop, nf_basis,
					[
						pos_l[NearFar.FAR] + gutr_x[NearFar.FAR] * dir,
						pos_l[NearFar.FAR],
						pos_l[NearFar.NEAR],
						pos_l[NearFar.NEAR] + gutr_x[NearFar.NEAR] * dir
					],
					[
						gutr_y[NearFar.FAR],
						0,
						0,
						gutr_y[NearFar.NEAR]
					])
				)
		else:
			quad( st, uv_square(uv_m, 0, uv_y),
				pts_square(nf_loop, nf_basis,
					[
						pos_r[NearFar.FAR],
						pos_r[NearFar.FAR] + gutr_x[NearFar.FAR] * dir,
						pos_r[NearFar.NEAR] + gutr_x[NearFar.NEAR] * dir,
						pos_r[NearFar.NEAR]
					],
					[
						0,
						gutr_y[NearFar.FAR],
						gutr_y[NearFar.NEAR],
						0
					])
				)

static func uv_square(uv_lmr1:float, uv_lmr2:float, uv_y: Array) -> Array:
	assert( len(uv_y) == 2 )
	return	[
			Vector2(uv_lmr1, uv_y[NearFar.FAR]),
			Vector2(uv_lmr2, uv_y[NearFar.FAR]),
			Vector2(uv_lmr2, uv_y[NearFar.NEAR]),
			Vector2(uv_lmr1, uv_y[NearFar.NEAR]),
			]

static func pts_square(nf_loop:Array, nf_basis:Array, width_offset: Array, y_offset = null) -> Array:
	assert( len(nf_loop) == 2 && len(nf_basis) == 2 )
	var ret = [
			nf_loop[NearFar.FAR] + nf_basis[NearFar.FAR] * width_offset[0],
			nf_loop[NearFar.FAR] + nf_basis[NearFar.FAR] * width_offset[1],
			nf_loop[NearFar.NEAR] + nf_basis[NearFar.NEAR] * width_offset[2],
			nf_loop[NearFar.NEAR] + nf_basis[NearFar.NEAR] * width_offset[3],
			]
	if y_offset != null:
		for i in len(y_offset):
			ret[i] += Vector3.UP * y_offset[i]
	return ret

# Generate a quad with two triangles for a list of 4 points/uvs in a row.
# For convention, do cloclwise from top-left vert, where the diagonal
# will go from bottom left to top right.
static func quad(st:SurfaceTool, uvs:Array, pts:Array) -> void:
	# Triangle 1.
	st.set_uv(uvs[0])
	# Add normal explicitly?
	st.add_vertex(pts[0])
	st.set_uv(uvs[1])
	st.add_vertex(pts[1])
	st.set_uv(uvs[3])
	st.add_vertex(pts[3])
	# Triangle 2.
	st.set_uv(uvs[1])
	st.add_vertex(pts[1])
	st.set_uv(uvs[2])
	st.add_vertex(pts[2])
	st.set_uv(uvs[3])
	st.add_vertex(pts[3])


func _flip_traffic_dir(lanes: Array) -> Array:
	var _spdir:Array = []
	for itm in lanes:
		var val = itm
		if itm == RoadPoint.LaneDir.FORWARD:
			val = RoadPoint.LaneDir.REVERSE
		elif itm == RoadPoint.LaneDir.REVERSE:
			val = RoadPoint.LaneDir.FORWARD
		_spdir.append(val)
	_spdir.reverse()
	return _spdir


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

	# Correct for flipped direction (two next's pointing to each other,
	# or two reverse's pointing to each other
	var sp_traffic_dir:Array = start_point.traffic_dir
	var ep_traffic_dir:Array = end_point.traffic_dir
	var anyflip := false
	if _start_flip:
		sp_traffic_dir = _flip_traffic_dir(sp_traffic_dir)
		anyflip = true
	if _end_flip:
		ep_traffic_dir = _flip_traffic_dir(ep_traffic_dir)
		anyflip = true

	if (
		(sp_traffic_dir[0] == RoadPoint.LaneDir.REVERSE
			and ep_traffic_dir[0] == RoadPoint.LaneDir.FORWARD)
			or (sp_traffic_dir[0] == RoadPoint.LaneDir.FORWARD
			and ep_traffic_dir[0] == RoadPoint.LaneDir.REVERSE)
	):
		push_warning("Warning: Unable to match lanes on start_point %s" % start_point)
		return []

	var start_flip_data = _get_lane_flip_data(sp_traffic_dir)
	var start_flip_offset = start_flip_data[0]
	var start_traffic_dir = start_flip_data[1]

	var end_flip_data = _get_lane_flip_data(ep_traffic_dir)
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
	var range_to_check = max(len(sp_traffic_dir), len(ep_traffic_dir))

	# Handle FORWARD-only lane setups
	if (
		start_traffic_dir == RoadPoint.LaneDir.FORWARD
		and end_traffic_dir == RoadPoint.LaneDir.FORWARD
	):
		var last_same_i = 0 # last lane where F# was the same at start/end
		for i in range(range_to_check):
			if i < len(sp_traffic_dir) and i < len(ep_traffic_dir):
				var lni = -1 - i if _start_flip else i
				lanes.append([
					start_point.lanes[lni], # accounting for _start_flip
					RoadPoint.LaneDir.FORWARD,
					"F%s" % i,
					"F%s" % i])
				last_same_i = i
			elif i > len(sp_traffic_dir) - 1:
				lanes.append([
					RoadPoint.LaneType.TRANSITION_ADD,
					RoadPoint.LaneDir.FORWARD,
					"F%sa" % last_same_i,
					"F%s" % i])
			elif i > len(ep_traffic_dir) - 1:
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
			if i < len(sp_traffic_dir) and i < len(ep_traffic_dir):
				var lni = i if _start_flip else -1 - i
				lanes.push_front([
					start_point.lanes[lni], # accounting for _start_flip
					RoadPoint.LaneDir.REVERSE,
					"R%s" % i,
					"R%s" % i])
				last_same_i = i
			elif i > len(ep_traffic_dir) - 1:
				lanes.push_front([
					RoadPoint.LaneType.TRANSITION_REM,
					RoadPoint.LaneDir.REVERSE,
					"R%s" % i,
					"R%sr" % last_same_i])
			elif i > len(sp_traffic_dir) - 1:
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
				var lni = -1 - i if _start_flip else i
				lanes.push_front([
					start_point.lanes[lni],  # Account for lane flip
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
		range_to_check = max(len(sp_traffic_dir), len(ep_traffic_dir) + start_end_offset_diff)
		last_same_i = 0 # last lane where F# was the same at start/end
		for i in range(start_flip_offset, range_to_check):
			if i > len(sp_traffic_dir) - 1:
				# No pre-existing lane on start point. Add a lane.
				lanes.append([
					RoadPoint.LaneType.TRANSITION_ADD,
					RoadPoint.LaneDir.FORWARD,
					"F%sa" % last_same_i,
					"F%s" % (i - start_flip_offset)])
			elif i < len(sp_traffic_dir) and i - start_end_offset_diff > len(ep_traffic_dir) - 1:
				# No pre-existing lane on end point. Remove a lane.
				lanes.append([
					RoadPoint.LaneType.TRANSITION_REM,
					RoadPoint.LaneDir.FORWARD,
					"F%s" % (i - start_flip_offset),
					"F%sr" % last_same_i])
			elif i < len(start_point.lanes):
				# Lane directions match. Add LaneType from start point.
				var lni = -1 - i if _start_flip else i
				lanes.append([
					start_point.lanes[lni], # Account for lane flips
					RoadPoint.LaneDir.FORWARD,
					"F%s" % (i - start_flip_offset),
					"F%s" % (i - start_flip_offset)])
				last_same_i = (i - start_flip_offset)

	return lanes

## Evaluate the lanes of a RoadPoint and return the index of the direction flip
## from REVERSE to FORWARD. Return -1 if no flip was found. Also, return the
## overall traffic direction of the RoadPoint.
## Returns: Array[int, RoadPoint.LaneDir]
func _get_lane_flip_data(traffic_dir: Array) -> Array:
	# Get lane FORWARD flip offset. If a flip occurs more than once, give
	# warning.
	var flip_offset = 0
	var flip_count = 0

	for i in range(len(traffic_dir)):
		if (
				# Save ID of first FORWARD lane
				traffic_dir[i] == RoadPoint.LaneDir.FORWARD
				and flip_count == 0
		):
			flip_offset = i
			flip_count += 1
		if (
				# Flag unwanted flips. REVERSE always comes before FORWARD.
				traffic_dir[i] == RoadPoint.LaneDir.REVERSE
				and flip_count > 0
		):
			push_warning("Warning: Unable to detect lane flip on road_point with traffic dirs %s" % traffic_dir)
			return [-1, RoadPoint.LaneDir.NONE]
		elif flip_count == 0 and i == len(traffic_dir) - 1:
			# This must be a REVERSE-only road point
			flip_offset = len(traffic_dir) - 1
			return [flip_offset, RoadPoint.LaneDir.REVERSE]
		elif flip_count == 1 and flip_offset == 0 and i == len(traffic_dir) - 1:
			# This must be a FORWARD-only road point
			flip_offset = len(traffic_dir) - 1
			return [flip_offset, RoadPoint.LaneDir.FORWARD]
	return [flip_offset, RoadPoint.LaneDir.BOTH]

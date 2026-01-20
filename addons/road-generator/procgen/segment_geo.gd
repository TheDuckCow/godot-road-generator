extends Object


# ------------------------------------------------------------------------------
#region Enums/Const
# TODO: Resolve duplication of these also being defined in road_segment.gd
# ------------------------------------------------------------------------------


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

const UV_MID_SHOULDER = 0.8  # should be more like 0.9


# ------------------------------------------------------------------------------
#endregion
#region Geo utilities
# ------------------------------------------------------------------------------

#
static func uv_square(uv_lmr1:float, uv_lmr2:float, uv_y: Array) -> Array:
	assert( len(uv_y) == 2 )
	return	[
			Vector2(uv_lmr1, uv_y[NearFar.FAR]),
			Vector2(uv_lmr2, uv_y[NearFar.FAR]),
			Vector2(uv_lmr2, uv_y[NearFar.NEAR]),
			Vector2(uv_lmr1, uv_y[NearFar.NEAR]),
			]


static func pts_square(nf_loop:Array, nf_basis:Array, width_offset: Array, y_offset: Array = [], nf_y_dir = [Vector3.UP, Vector3.UP]) -> Array:
	assert( len(nf_loop) == 2 && len(nf_basis) == 2 )
	var ret = [
			nf_loop[NearFar.FAR] + nf_basis[NearFar.FAR] * width_offset[0],
			nf_loop[NearFar.FAR] + nf_basis[NearFar.FAR] * width_offset[1],
			nf_loop[NearFar.NEAR] + nf_basis[NearFar.NEAR] * width_offset[2],
			nf_loop[NearFar.NEAR] + nf_basis[NearFar.NEAR] * width_offset[3],
			]
	if y_offset != null and y_offset.size() == 4:
		ret[0] += nf_y_dir[NearFar.FAR] * y_offset[0]
		ret[1] += nf_y_dir[NearFar.FAR] * y_offset[1]
		ret[2] += nf_y_dir[NearFar.NEAR] * y_offset[2]
		ret[3] += nf_y_dir[NearFar.NEAR] * y_offset[3]

	return ret


# Generate a quad with two triangles for a list of 4 points/uvs in a row.
# For convention, do cloclwise from top-left vert, where the diagonal
# will go from bottom left to top right.
static func quad(st:SurfaceTool, uvs:Array, pts:Array, smoothing_group: int = 0) -> void:
	# Triangle 1.
	st.set_smooth_group(smoothing_group)
	st.set_uv(uvs[0])
	# Add normal explicitly?
	st.add_vertex(pts[0])
	st.set_smooth_group(smoothing_group)
	st.set_uv(uvs[1])
	st.add_vertex(pts[1])
	st.set_smooth_group(smoothing_group)
	st.set_uv(uvs[3])
	st.add_vertex(pts[3])
	# Triangle 2.
	st.set_smooth_group(smoothing_group)
	st.set_uv(uvs[1])
	st.add_vertex(pts[1])
	st.set_smooth_group(smoothing_group)
	st.set_uv(uvs[2])
	st.add_vertex(pts[2])
	st.set_smooth_group(smoothing_group)
	st.set_uv(uvs[3])
	st.add_vertex(pts[3])


static func inverse_quad(st:SurfaceTool, uvs:Array, pts:Array, smoothing_group: int = 0) -> void:
	# Triangle 1.
	st.set_smooth_group(smoothing_group)
	st.set_uv(uvs[3])
	# Add normal explicitly?
	st.add_vertex(pts[3])
	st.set_smooth_group(smoothing_group)
	st.set_uv(uvs[1])
	st.add_vertex(pts[1])
	st.set_smooth_group(smoothing_group)
	st.set_uv(uvs[0])
	st.add_vertex(pts[0])
	# Triangle 2.
	st.set_uv(uvs[3])
	st.add_vertex(pts[3])
	st.set_smooth_group(smoothing_group)
	st.set_uv(uvs[2])
	st.add_vertex(pts[2])
	st.set_smooth_group(smoothing_group)
	st.set_uv(uvs[1])
	st.add_vertex(pts[1])


static func _flip_traffic_dir(lanes: Array[int]) -> Array:
	var _spdir:Array[int] = []
	for itm in lanes:
		var val = itm
		if itm == RoadPoint.LaneDir.FORWARD:
			val = RoadPoint.LaneDir.REVERSE
		elif itm == RoadPoint.LaneDir.REVERSE:
			val = RoadPoint.LaneDir.FORWARD
		_spdir.append(val)
	_spdir.reverse()
	return _spdir


## Evaluate the lanes of a RoadPoint and return the index of the direction flip
## from REVERSE to FORWARD. Return -1 if no flip was found. Also, return the
## overall traffic direction of the RoadPoint.
## Returns: Array[int, RoadPoint.LaneDir]
static func _get_lane_flip_data(traffic_dir: Array) -> Array:
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


#endregion
# ------------------------------------------------------------------------------

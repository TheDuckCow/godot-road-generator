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


# Generate a single triangle for a list of 3 points/uvs, in the given order.
# Caller picks the winding; Godot front faces are clockwise.
static func tri(st:SurfaceTool, uvs:Array, pts:Array, smoothing_group: int = 0) -> void:
	st.set_smooth_group(smoothing_group)
	st.set_uv(uvs[0])
	st.add_vertex(pts[0])
	st.set_smooth_group(smoothing_group)
	st.set_uv(uvs[1])
	st.add_vertex(pts[1])
	st.set_smooth_group(smoothing_group)
	st.set_uv(uvs[2])
	st.add_vertex(pts[2])


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


## Snaps the normals of vertices lying on RoadPoint planes to analytic
## per-role values so adjoining segments shade seamlessly. Each plane is a
## Dictionary: p, x, up are the plane origin, lateral axis and up; outer is
## [left, right] half width with shoulders; gutter is the (x, y) gutter
## profile; thickness is the underside depth. A vertex belongs to the first
## plane it lies on. Roles come from position (lane, crease, lip, bottom,
## wall); the duplicated bottom/wall corner is resolved by topology: the
## in-plane edge-mate of the vertex's triangle. Vertices of triangles that lie
## entirely in one plane, such as end fills, are left untouched. Reads
## ARRAY_INDEX; unindexed arrays are read as consecutive triangles. Mutates
## arrays.
static func fix_boundary_normals(arrays: Array, planes: Array, underside: bool) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if verts.is_empty() or normals.is_empty() or verts.size() != normals.size():
		return
	if planes.is_empty():
		return
	const TOL := 1e-3
	var n_planes: int = planes.size()
	var ps := PackedVector3Array()
	var zs := PackedVector3Array()
	ps.resize(n_planes)
	zs.resize(n_planes)
	for k in range(n_planes):
		ps[k] = planes[k].p
		zs[k] = (planes[k].x as Vector3).cross(planes[k].up).normalized()

	# Verts on a plane, tagged with the first plane they lie on.
	var vcount: int = verts.size()
	var plane_of := PackedInt32Array()
	plane_of.resize(vcount)
	plane_of.fill(-1)
	var on_list := PackedInt32Array()
	for i in range(vcount):
		var v: Vector3 = verts[i]
		for k in range(n_planes):
			if absf((v - ps[k]).dot(zs[k])) < TOL:
				plane_of[i] = k
				on_list.append(i)
				break
	if on_list.is_empty():
		return

	# Triangles: fully in-plane ones are caps; edges in a plane give mates.
	var idx := PackedInt32Array()
	if arrays.size() > Mesh.ARRAY_INDEX:
		var idx_v = arrays[Mesh.ARRAY_INDEX]
		if idx_v is PackedInt32Array:
			idx = idx_v
	var indexed := not idx.is_empty()
	var tri_count: int = idx.size() / 3 if indexed else vcount / 3
	var is_cap := PackedByteArray()
	is_cap.resize(vcount)
	var mates := {}
	for t in range(tri_count):
		var a: int = idx[3 * t] if indexed else 3 * t
		var b: int = idx[3 * t + 1] if indexed else 3 * t + 1
		var c: int = idx[3 * t + 2] if indexed else 3 * t + 2
		var pa: int = plane_of[a]
		var pb: int = plane_of[b]
		var pc: int = plane_of[c]
		if pa < 0 and pb < 0 and pc < 0:
			continue
		if pa >= 0 and pa == pb and pa == pc:
			is_cap[a] = 1
			is_cap[b] = 1
			is_cap[c] = 1
			continue
		if pa >= 0 and pa == pb:
			_add_mates(mates, a, b)
		elif pa >= 0 and pa == pc:
			_add_mates(mates, a, c)
		elif pb >= 0 and pb == pc:
			_add_mates(mates, b, c)

	for i in on_list:
		if is_cap[i] != 0:
			continue
		var pl: Dictionary = planes[plane_of[i]]
		var p: Vector3 = pl.p
		var x: Vector3 = pl.x
		var up: Vector3 = pl.up
		var outer: Array = pl.outer
		var gx: float = pl.gutter.x
		var gy: float = pl.gutter.y
		var thickness: float = pl.thickness
		var d: Vector3 = verts[i] - p
		var s: float = d.dot(x)
		var h: float = d.dot(up)
		var side := 1.0 if s >= 0.0 else -1.0
		var o: float = outer[1] if side > 0.0 else outer[0]
		if absf(s) > o + gx + TOL:
			continue
		if not underside:
			var g_side: Vector3 = -side * gy * x + gx * up
			if g_side.length() < 1e-6:
				g_side = up
			else:
				g_side = g_side.normalized()
			if absf(h) < TOL and absf(absf(s) - o) < TOL:
				normals[i] = (up + g_side).normalized() # Crease.
			elif absf(h) < TOL:
				normals[i] = up
			elif absf(h - gy) < TOL and absf(absf(s) - (o + gx)) < TOL:
				normals[i] = g_side # Lip.
		else:
			var wall: Vector3 = side * (gy + thickness) * x - gx * up
			if wall.length() < 1e-6:
				wall = -up
			else:
				wall = wall.normalized()
			if absf(h + thickness) < TOL and absf(s) < o - TOL:
				normals[i] = -up # Bottom.
			elif absf(h + thickness) < TOL and absf(absf(s) - o) < TOL:
				# Corner: the face is the one its in-plane edge-mate lies on.
				if not mates.has(i):
					continue
				var is_wall := false
				for j in mates[i]:
					var dj: Vector3 = verts[j] - p
					var sj: float = dj.dot(x)
					var hj: float = dj.dot(up)
					var oj: float = outer[1] if sj >= 0.0 else outer[0]
					var bottom_pos := absf(hj + thickness) < TOL and absf(sj) <= oj + TOL
					if not bottom_pos:
						is_wall = true
						break
				normals[i] = wall if is_wall else -up
			elif absf(h - gy) < TOL and absf(absf(s) - (o + gx)) < TOL:
				normals[i] = wall # Lip.
	arrays[Mesh.ARRAY_NORMAL] = normals


static func _add_mates(mates: Dictionary, a: int, b: int) -> void:
	if not mates.has(a):
		mates[a] = []
	if not mates.has(b):
		mates[b] = []
	mates[a].append(b)
	mates[b].append(a)


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
## quiet suppresses the malformed-config warning for callers that only validate
## (e.g. RoadPoint configuration warnings), which run on every editor edit.
static func _get_lane_flip_data(traffic_dir: Array, quiet: bool = false) -> Array:
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
			if not quiet:
				push_warning("Warning: Unable to detect lane flip on road_point with traffic dirs %s" % [traffic_dir])
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


## Whether two connected road points can form a road. A one-way (FORWARD or
## REVERSE) to two-way (BOTH) transition matches no lanes and so produces no
## mesh. start_dir/end_dir are overall directions from _get_lane_flip_data.
static func is_valid_lane_transition(start_dir: int, end_dir: int) -> bool:
	if start_dir == RoadPoint.LaneDir.BOTH and end_dir != RoadPoint.LaneDir.BOTH:
		return false
	if end_dir == RoadPoint.LaneDir.BOTH and start_dir != RoadPoint.LaneDir.BOTH:
		return false
	return true


#endregion
# ------------------------------------------------------------------------------

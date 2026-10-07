extends "res://addons/gut/test.gd"

const RoadUtils = preload("res://test/unit/road_utils.gd")
const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")

var road_util: RoadUtils


func before_each():
	road_util = RoadUtils.new()
	road_util.gut = gut


func ensure_roadlanes_exist(container:RoadContainer, segs: int = 3):
	var lanes = []
	for _ch in container.get_roadpoints():
		var rp: RoadPoint = _ch as RoadPoint
		for ln in rp.get_children():
			if not ln is RoadLane:
				continue
			lanes.append(ln)
	var expected: int = 4*segs
	assert_eq(lanes.size(), expected, "Should create exactly %s lanes" % expected)

	# A total-only count hides a clobber: one segment can lose all its lanes
	# while a shared-parent sibling holds a duplicate set, keeping the sum right.
	# Assert per segment so a starved segment is caught.
	for seg in container.get_segments():
		assert_eq(seg.get_lanes().size(), 4,
			"Segment %s should own 4 lanes" % seg.name)


## Function for flipping a RoadPoint 180 and reversing connections
##
## Unforutnately, we can't directly use the high level addon flip operator due
## to current structure, when that is abstracted in the future, use that instead:
## plugin.subaction_flip_roadpoint
func simple_flip_roadpoint(rp: RoadPoint) -> void:
	var flipped_transform = rp.transform
	flipped_transform = flipped_transform.rotated_local(Vector3.UP, PI)
	rp.set_internal_updating(true)
	var tmpinit = rp.prior_pt_init
	rp.prior_pt_init = rp.next_pt_init
	rp.next_pt_init = tmpinit
	#rp.traffic_dir = _new_traffic_dirs # they are mirrored anyways
	var tmpmag = rp.prior_mag
	rp.prior_mag = rp.next_mag
	rp.next_mag = tmpmag
	rp.transform = flipped_transform
	rp.set_internal_updating(false)


# ------------------------------------------------------------------------------


## Checkes that two RoadPoints pointing in the same direction produces good lanes
func test_lanes_next_to_prior():
	var container:RoadContainer = add_child_autofree(RoadContainer.new())
	var points: Array[RoadPoint] = road_util.create_rp_line(container, 4, true, true)
	# No flipping, already in a next-to-prior config
	container.generate_ai_lanes = true
	container.draw_lanes_editor = true
	container.rebuild_segments(true)
	ensure_roadlanes_exist(container)
	#road_util.save_testscene_to_file(container)


## Checkes that two RoadPoints pointing away from each other produces good lanes
func test_lanes_prior_to_prior():
	var container:RoadContainer = add_child_autofree(RoadContainer.new())
	var points: Array[RoadPoint] = road_util.create_rp_line(container, 4, true, true)
	# Flip first two roadpoints
	for idx in [0, 1]:
		var rp:RoadPoint = points[idx]
		simple_flip_roadpoint(rp)

	container.generate_ai_lanes = true
	container.draw_lanes_editor = true
	container.rebuild_segments(true)
	ensure_roadlanes_exist(container)
	#road_util.save_testscene_to_file(container)
	

## Checkes that two RoadPoints pointing towards each other produces good lanes
func test_lanes_next_to_next():
	var container:RoadContainer = add_child_autofree(RoadContainer.new())
	var points: Array[RoadPoint] = road_util.create_rp_line(container, 4, true, true)
	for idx in [2, 3]:
		var rp:RoadPoint = points[idx]
		simple_flip_roadpoint(rp)

	container.generate_ai_lanes = true
	container.draw_lanes_editor = true
	container.rebuild_segments(true)
	ensure_roadlanes_exist(container)
	#road_util.save_testscene_to_file(container)


## Minimal shared-parent case: a center point parents two segments whose lanes
## would otherwise share a name and clobber. Three points is the smallest setup
## that produces two segments under one RoadPoint.
func test_lanes_shared_parent_no_clobber():
	var container:RoadContainer = add_child_autofree(RoadContainer.new())
	var points: Array[RoadPoint] = road_util.create_rp_line(container, 3, true, true)
	# Flip the last point so the middle point is the start of both segments.
	simple_flip_roadpoint(points[2])

	container.generate_ai_lanes = true
	container.draw_lanes_editor = true
	container.rebuild_segments(true)
	ensure_roadlanes_exist(container, 2)
	#road_util.save_testscene_to_file(container)


# ------------------------------------------------------------------------------
# Bare end fill


const PLANE_EPS := 1e-3


## Live segment between two points (old ones may still be queued for free).
func _seg_for(container: RoadContainer, rpa: RoadPoint, rpb: RoadPoint) -> RoadSegment:
	var sid := RoadSegment.get_id_for_points(rpa, rpb)
	assert_true(sid in container.segid_map, "Segment %s should exist" % sid)
	if not sid in container.segid_map:
		return null
	return container.segid_map[sid]


## Tris whose three normals face dir; asserts each lies on local z=plane_z.
## Each entry is [idx0, idx1, idx2].
func _cap_tris(mesh: Mesh, surface: int, dir: Vector3, plane_z: float) -> Array:
	var res := []
	var arrs: Array = mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrs[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrs[Mesh.ARRAY_INDEX]
	for i in range(0, idx.size(), 3):
		var tri := [idx[i], idx[i + 1], idx[i + 2]]
		var facing := true
		for v in tri:
			if norms[v].dot(dir) <= 0.99:
				facing = false
				break
		if not facing:
			continue
		for v in tri:
			assert_almost_eq(verts[v].z, plane_z, PLANE_EPS,
				"Cap vertex %s should lie on z=%s" % [verts[v], plane_z])
		res.append(tri)
	return res


func _tris_area(mesh: Mesh, surface: int, tris: Array) -> float:
	var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	var area := 0.0
	for tri in tris:
		var a: Vector3 = verts[tri[0]]
		area += 0.5 * (verts[tri[1]] - a).cross(verts[tri[2]] - a).length()
	return area


## Fill normals must not bleed into wall/bottom vertices: on this straight
## road, non-cap vertices on the end plane keep |n.z| < 0.5 (smoothing-group
## isolation).
func _assert_no_stray_axial(mesh: Mesh, surface: int, caps: Array, plane_z: float) -> void:
	var arrs: Array = mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrs[Mesh.ARRAY_NORMAL]
	var cap_idx := {}
	for tri in caps:
		for v in tri:
			cap_idx[v] = true
	var stray := 0
	for v in range(verts.size()):
		if v in cap_idx or absf(verts[v].z - plane_z) >= PLANE_EPS:
			continue
		if absf(norms[v].z) >= 0.5:
			stray += 1
	assert_eq(stray, 0, "No non-cap vertex on z=%s should face along z" % plane_z)


## Shared checks for a +z segment from z=0 to z=10 with both ends bare.
func _assert_bare_line_caps(seg: RoadSegment, th: float) -> void:
	var mesh: Mesh = seg.road_mesh.mesh
	assert_eq(mesh.get_surface_count(), 2, "Top and underside surfaces")
	if mesh.get_surface_count() < 2:
		return
	var w: float = seg.start_point.get_width_with_shoulders()
	var gx: float = seg.start_point.gutter_profile.x
	assert_gt(gx, 0.0, "Gutter x must be nonzero for side tris")
	var expect_area: float = th * (w + gx)
	var near := _cap_tris(mesh, 1, Vector3(0, 0, -1), 0.0)
	var far := _cap_tris(mesh, 1, Vector3(0, 0, 1), 10.0)
	assert_eq(near.size(), 4, "Start cap tris facing -z")
	assert_eq(far.size(), 4, "End cap tris facing +z")
	assert_almost_eq(_tris_area(mesh, 1, near), expect_area, 1e-3, "Start cap area")
	assert_almost_eq(_tris_area(mesh, 1, far), expect_area, 1e-3, "End cap area")
	_assert_no_stray_axial(mesh, 1, near, 0.0)
	_assert_no_stray_axial(mesh, 1, far, 10.0)


func test_end_fill_bare_line():
	var container: RoadContainer = add_child_autofree(RoadContainer.new())
	var points: Array[RoadPoint] = road_util.create_rp_line(container, 2, true, true)
	container.underside_thickness = 0.5
	container.rebuild_segments(true)
	assert_eq(points[0].get_thickness(), 0.5, "Thickness from container")
	_assert_bare_line_caps(_seg_for(container, points[0], points[1]), 0.5)

	var flat: RoadContainer = add_child_autofree(RoadContainer.new())
	var flat_pts: Array[RoadPoint] = road_util.create_rp_line(flat, 2, true, true)
	flat.rebuild_segments(true)
	var flat_seg := _seg_for(flat, flat_pts[0], flat_pts[1])
	assert_eq(flat_seg.road_mesh.mesh.get_surface_count(), 1, "No underside, no fill")


func test_end_fill_cross_container():
	var cont_a: RoadContainer = add_child_autofree(RoadContainer.new())
	var cont_b: RoadContainer = add_child_autofree(RoadContainer.new())
	var pa: Array[RoadPoint] = road_util.create_rp_line(cont_a, 2, true, true)
	var pb: Array[RoadPoint] = road_util.create_rp_line(cont_b, 2, true, true)
	# b starts where a ends.
	cont_b.position.z = 10
	cont_a.underside_thickness = 0.5
	cont_b.underside_thickness = 0.5
	cont_a.update_edges()
	cont_b.update_edges()
	var res := pa[1].connect_container(RoadPoint.PointInit.NEXT, pb[0], RoadPoint.PointInit.PRIOR)
	assert_true(res, "Containers connect")
	cont_a.rebuild_segments(true)
	cont_b.rebuild_segments(true)

	var mesh_a: Mesh = _seg_for(cont_a, pa[0], pa[1]).road_mesh.mesh
	var mesh_b: Mesh = _seg_for(cont_b, pb[0], pb[1]).road_mesh.mesh
	assert_eq(_cap_tris(mesh_a, 1, Vector3(0, 0, -1), 0.0).size(), 4, "A free start capped")
	assert_eq(_cap_tris(mesh_a, 1, Vector3(0, 0, 1), 10.0).size(), 0, "A joined end open")
	assert_eq(_cap_tris(mesh_b, 1, Vector3(0, 0, -1), 0.0).size(), 0, "B joined start open")
	assert_eq(_cap_tris(mesh_b, 1, Vector3(0, 0, 1), 10.0).size(), 4, "B free end capped")

	res = pa[1].disconnect_container(RoadPoint.PointInit.NEXT, RoadPoint.PointInit.PRIOR)
	assert_true(res, "Containers disconnect")
	cont_a.rebuild_segments(true)
	cont_b.rebuild_segments(true)

	mesh_a = _seg_for(cont_a, pa[0], pa[1]).road_mesh.mesh
	mesh_b = _seg_for(cont_b, pb[0], pb[1]).road_mesh.mesh
	assert_eq(_cap_tris(mesh_a, 1, Vector3(0, 0, -1), 0.0).size(), 4, "A start capped")
	assert_eq(_cap_tris(mesh_a, 1, Vector3(0, 0, 1), 10.0).size(), 4, "A end capped")
	assert_eq(_cap_tris(mesh_b, 1, Vector3(0, 0, -1), 0.0).size(), 4, "B start capped")
	assert_eq(_cap_tris(mesh_b, 1, Vector3(0, 0, 1), 10.0).size(), 4, "B end capped")


func test_is_bare_edge():
	var NEXT := RoadPoint.PointInit.NEXT
	var PRIOR := RoadPoint.PointInit.PRIOR

	var container: RoadContainer = add_child_autofree(RoadContainer.new())
	var points: Array[RoadPoint] = road_util.create_rp_line(container, 3, true, true)
	container.update_edges()
	assert_true(points[0].is_bare_edge(PRIOR), "RP0 prior is open")
	assert_false(points[0].is_bare_edge(NEXT), "RP0 next is RP1")
	assert_false(points[1].is_bare_edge(PRIOR), "RP1 prior is RP0")
	assert_false(points[1].is_bare_edge(NEXT), "RP1 next is RP2")
	assert_true(points[2].is_bare_edge(NEXT), "RP2 next is open")

	points[2].terminated = true
	container.update_edges()
	assert_false(points[2].is_bare_edge(NEXT), "Terminated end opts out")

	var inter_cont: RoadContainer = add_child_autofree(RoadContainer.new())
	road_util.create_intersection_two_branch(inter_cont)
	var p1: RoadPoint = inter_cont.get_node("p1")
	var p2: RoadPoint = inter_cont.get_node("p2")
	assert_false(p1.is_bare_edge(NEXT), "Intersection branch not bare")
	assert_false(p2.is_bare_edge(PRIOR), "Intersection branch not bare")

	var cont_a: RoadContainer = add_child_autofree(RoadContainer.new())
	var cont_b: RoadContainer = add_child_autofree(RoadContainer.new())
	var pa: Array[RoadPoint] = road_util.create_rp_line(cont_a, 2, true, true)
	var pb: Array[RoadPoint] = road_util.create_rp_line(cont_b, 2, true, true)
	cont_b.position.z = 10
	cont_a.update_edges()
	cont_b.update_edges()
	assert_true(pa[1].is_bare_edge(NEXT), "Edge bare before connect")
	assert_true(pa[1].connect_container(NEXT, pb[0], PRIOR), "Containers connect")
	assert_false(pa[1].is_bare_edge(NEXT), "Connected container edge not bare")
	assert_false(pb[0].is_bare_edge(PRIOR), "Connected container edge not bare")
	assert_true(pa[0].is_bare_edge(PRIOR), "Far edge still bare")


# ------------------------------------------------------------------------------
# Live end fill updates


## Asserts cap tri counts on a 10m +z segment; local z=0 is the start RP.
func _assert_caps(seg: RoadSegment, near: int, far: int, msg: String) -> void:
	if seg == null:
		return
	var mesh: Mesh = seg.road_mesh.mesh
	assert_eq(mesh.get_surface_count(), 2, "%s: top and underside" % msg)
	if mesh.get_surface_count() < 2:
		return
	assert_eq(_cap_tris(mesh, 1, Vector3(0, 0, -1), 0.0).size(), near, "%s: near cap" % msg)
	assert_eq(_cap_tris(mesh, 1, Vector3(0, 0, 1), 10.0).size(), far, "%s: far cap" % msg)


func _rebuild_dirty(seg: RoadSegment, msg: String) -> void:
	if seg == null:
		return
	assert_true(seg.is_dirty, "%s: dirty" % msg)
	seg.check_rebuild()


func test_end_fill_live_connect_disconnect():
	var NEXT := RoadPoint.PointInit.NEXT
	var PRIOR := RoadPoint.PointInit.PRIOR
	var container: RoadContainer = add_child_autofree(RoadContainer.new())
	var points: Array[RoadPoint] = road_util.create_rp_line(container, 3, true, true)
	container.underside_thickness = 0.5
	container.rebuild_segments(true)
	var seg_ab := _seg_for(container, points[0], points[1])
	_assert_caps(seg_ab, 4, 0, "Initial A-B")

	assert_true(points[1].disconnect_roadpoint(NEXT, PRIOR), "Disconnect B-C")
	_rebuild_dirty(seg_ab, "A-B after disconnect")
	_assert_caps(seg_ab, 4, 4, "A-B after disconnect")

	assert_true(points[1].connect_roadpoint(NEXT, points[2], PRIOR), "Connect B-C")
	_rebuild_dirty(seg_ab, "A-B after connect")
	_assert_caps(seg_ab, 4, 0, "A-B after connect")
	var seg_bc := _seg_for(container, points[1], points[2])
	if seg_bc and seg_bc.is_dirty:
		seg_bc.check_rebuild()
	_assert_caps(seg_bc, 0, 4, "B-C after connect")


## Mirrors plugin _add_next_rp_on_click_do.
func test_end_fill_live_add_road_point():
	var NEXT := RoadPoint.PointInit.NEXT
	var container: RoadContainer = add_child_autofree(RoadContainer.new())
	var points: Array[RoadPoint] = road_util.create_rp_line(container, 2, true, true)
	container.underside_thickness = 0.5
	container.rebuild_segments(true)
	var seg_ab := _seg_for(container, points[0], points[1])
	_assert_caps(seg_ab, 4, 4, "Initial A-B")

	# add_road_point adds c to the container itself.
	var c: RoadPoint = autoqfree(RoadPoint.new())
	c._is_internal_updating = true
	points[1].add_road_point(c, NEXT)
	assert_eq(c.get_parent(), container, "c added to container")
	c.global_position = Vector3(0, 0, 20)
	c._is_internal_updating = false
	c._skip_next_on_transform = true
	container.on_point_update(c, false)

	_rebuild_dirty(seg_ab, "A-B after add")
	_assert_caps(seg_ab, 4, 0, "A-B after add")
	var seg_bc := _seg_for(container, points[1], c)
	if seg_bc and seg_bc.is_dirty:
		seg_bc.check_rebuild()
	_assert_caps(seg_bc, 0, 4, "B-c after add")


func test_end_fill_no_redundant_dirty():
	var container: RoadContainer = add_child_autofree(RoadContainer.new())
	var points: Array[RoadPoint] = road_util.create_rp_line(container, 2, true, true)
	container.underside_thickness = 0.5
	container.rebuild_segments(true)
	var seg := _seg_for(container, points[0], points[1])
	seg.check_rebuild()
	assert_false(seg.is_dirty, "Clean after build")
	watch_signals(container)
	container.update_edges()
	assert_false(seg.is_dirty, "update_edges leaves clean segment clean")
	assert_signal_not_emitted(container, "on_road_updated", "No road update")

extends "res://addons/gut/test.gd"

const RoadUtils = preload("res://test/unit/road_utils.gd")

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

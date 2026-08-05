extends "res://addons/gut/test.gd"

# Removing and re-adding a container subtree mirrors an editor scene-tab
# switch: nodes persist but exit and re-enter the tree. Runtime state
# (segments, lanes, fin meshes, the segment id map) must survive the cycle.

const RoadUtils = preload("res://test/unit/road_utils.gd")

var road_util: RoadUtils

func before_each():
	road_util = RoadUtils.new()
	road_util.gut = gut


func _cycle_tree(container: RoadContainer) -> void:
	remove_child(container)
	await wait_frames(2)
	add_child(container)
	await wait_frames(4)


func test_segment_state_survives_reentry():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.setup_road_container()
	container.generate_ai_lanes = true
	container.draw_lanes_game = true

	var p1 = autoqfree(RoadPoint.new())
	var p2 = autoqfree(RoadPoint.new())
	container.add_child(p1)
	container.add_child(p2)
	p1.name = "p1"
	p2.name = "p2"
	p2.position = Vector3(0, 0, 30)
	p1.next_pt_init = p1.get_path_to(p2)
	p2.prior_pt_init = p2.get_path_to(p1)
	container.update_edges()
	container.rebuild_segments(true)
	await wait_frames(3)

	var seg = p1.next_seg
	assert_true(is_instance_valid(seg), "Segment exists before cycle")
	var lanes := []
	for child in p1.get_children():
		if child is RoadLane:
			lanes.append(child)
	assert_gt(lanes.size(), 0, "Lanes exist before cycle")

	await _cycle_tree(container)

	assert_true(is_instance_valid(seg), "Segment node survives")
	assert_eq(container.segid_map.size(), 1, "Segment re-registered on re-entry")
	for lane in lanes:
		assert_true(is_instance_valid(lane), "Lane survives")
		assert_eq(lane.geom.get_surface_count(), 1, "Lane fin mesh survives")


func test_intersection_state_survives_reentry():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.setup_road_container()
	road_util.create_intersection_three_branch(container, 30.0)
	container.generate_ai_lanes = true
	container.draw_lanes_game = true
	container.rebuild_segments(true)
	await wait_frames(3)

	var inter: RoadIntersection = container.get_intersections()[0]
	var surfaces: int = inter._mesh.mesh.get_surface_count()
	var lane_count := 0
	for child in inter.get_children():
		if child is RoadLane:
			lane_count += 1
	assert_gt(lane_count, 0, "Intersection lanes exist before cycle")

	await _cycle_tree(container)

	assert_eq(inter.edge_points.size(), 3, "Edge points survive")
	assert_eq(inter._mesh.mesh.get_surface_count(), surfaces, "Intersection mesh survives")
	var after_count := 0
	for child in inter.get_children():
		if child is RoadLane:
			after_count += 1
			assert_eq(child.geom.get_surface_count(), 1, "Intersection lane fin mesh survives")
	assert_eq(after_count, lane_count, "Intersection lanes survive")

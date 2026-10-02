extends "res://addons/gut/test.gd"

const RoadUtils = preload("res://test/unit/road_utils.gd")

var road_util: RoadUtils


func before_each():
	road_util = RoadUtils.new()
	road_util.gut = gut


func _make_intersection(container) -> RoadIntersection:
	container.setup_road_container()
	road_util.create_intersection_two_branch(container)
	return container.get_intersections()[0]


## Generated edge curves: Path3D children carrying the edge_ prefix. RoadLanes are
## also Path3D, so they are filtered out explicitly.
func _edge_curves(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is RoadLane:
			continue
		if child is Path3D and not child.is_queued_for_deletion() \
				and str(child.name).begins_with("edge_"):
			result.append(child)
	return result


func _edge_names(node: Node) -> Array:
	var result: Array = []
	for edge in _edge_curves(node):
		result.append(str(edge.name))
	result.sort()
	return result


# ------------------------------------------------------------------------------


func test_generates_one_edge_curve_per_branch():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.create_edge_curves = true
	var inter := _make_intersection(container)

	container.rebuild_segments(true)

	# Two branches bound two exterior spans, one curve owned by each edge.
	assert_eq(_edge_curves(inter).size(), 2, "One edge curve per branch")
	assert_eq(_edge_names(inter), ["edge_p1", "edge_p2"], "Named after their starting RoadPoint")


func test_edge_curve_count_matches_four_branches():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.create_edge_curves = true
	container.setup_road_container()
	road_util.create_intersection_four_branch(container)
	var inter: RoadIntersection = container.get_intersections()[0]

	container.rebuild_segments(true)

	assert_eq(_edge_curves(inter).size(), 4, "One exterior edge curve per branch")


func test_edge_curve_count_matches_three_branches():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.create_edge_curves = true
	container.setup_road_container()
	road_util.create_intersection_three_branch(container)
	var inter: RoadIntersection = container.get_intersections()[0]

	container.rebuild_segments(true)

	assert_eq(_edge_curves(inter).size(), 3, "One exterior edge curve per branch")


func test_no_edge_curves_when_disabled():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.create_edge_curves = false
	var inter := _make_intersection(container)

	container.rebuild_segments(true)

	assert_eq(_edge_curves(inter).size(), 0, "No edge curves when the toggle is off")


func test_edge_curve_has_four_points():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.create_edge_curves = true
	var inter := _make_intersection(container)

	container.rebuild_segments(true)

	# RoadPoint corner, stop-line corner, neighbour stop-line corner, neighbour
	# RoadPoint corner: the same point count as the outermost RoadLane.
	for edge in _edge_curves(inter):
		assert_eq(edge.curve.point_count, 4, "Edge curve runs RoadPoint to RoadPoint via both stop lines")


func test_edge_curves_independent_of_ai_lanes():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.create_edge_curves = true
	container.generate_ai_lanes = false
	var inter := _make_intersection(container)

	container.rebuild_segments(true)

	# Edge curves derive from RoadPoint geometry, not emitted lanes, so they exist
	# even with AI lane generation switched off.
	var edges := _edge_curves(inter)
	assert_eq(edges.size(), 2, "Edge curves generate without AI lanes")
	for edge in edges:
		assert_eq(edge.curve.point_count, 4, "Edge curve is fully built without AI lanes")


func test_edge_curve_node_reused_on_rebuild():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.create_edge_curves = true
	var inter := _make_intersection(container)

	container.rebuild_segments(true)
	var before: Path3D = inter.get_node("edge_p1")
	container.rebuild_segments(true)
	var after: Path3D = inter.get_node("edge_p1")

	assert_eq(before, after, "The Path3D node itself is reused, only its curve rewritten")
	assert_eq(_edge_curves(inter).size(), 2, "Edge curves reused, not duplicated, on rebuild")


func test_edge_curve_children_survive_rebuild():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.create_edge_curves = true
	var inter := _make_intersection(container)
	container.rebuild_segments(true)

	# The user is expected to parent decoration nodes to the edge curve; a rebuild
	# rewrites the curve resource but must not free the node or its children.
	var edge: Path3D = inter.get_node("edge_p1")
	var decoration := Node3D.new()
	edge.add_child(decoration)
	decoration.name = "decoration"
	decoration.owner = container

	container.rebuild_segments(true)

	assert_false(decoration.is_queued_for_deletion(), "User-added child survives rebuild")
	assert_not_null(edge.get_node_or_null("decoration"), "Child still parented to the edge curve")


func test_edge_curve_bends_have_sharp_handles():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.create_edge_curves = true
	container.setup_road_container()
	road_util.create_intersection_four_branch(container)
	var inter: RoadIntersection = container.get_intersections()[0]

	container.rebuild_segments(true)

	# At a 90-degree corner the in/out handles point at different neighbours, so
	# they are non-aligned (sharp) rather than colinear (smooth).
	var edge: Path3D = inter.get_node("edge_pn")
	var in_handle := edge.curve.get_point_in(1)
	var out_handle := edge.curve.get_point_out(1)
	assert_gt(in_handle.cross(out_handle).length(), 0.01, "Bend handles are sharp, not aligned")


func test_removing_a_branch_deletes_its_edge_and_regenerates():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.create_edge_curves = true
	container.setup_road_container()
	road_util.create_intersection_four_branch(container)
	var inter: RoadIntersection = container.get_intersections()[0]
	container.rebuild_segments(true)
	assert_eq(_edge_curves(inter).size(), 4, "Four edges to begin with")

	var pw: RoadPoint = container.get_node("pw")
	inter.remove_branch(pw)
	container.rebuild_segments(true)

	# The orphaned edge is swept away and the survivors regenerate to their new
	# neighbours, leaving one curve per remaining branch.
	assert_eq(_edge_curves(inter).size(), 3, "Removed branch drops one edge curve")
	assert_null(inter.get_node_or_null("edge_pw"), "The removed branch's edge curve is gone")


func test_adding_a_branch_creates_an_edge():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.create_edge_curves = true
	var inter := _make_intersection(container)
	container.rebuild_segments(true)
	assert_eq(_edge_curves(inter).size(), 2, "Two edges to begin with")

	var p3 = autoqfree(RoadPoint.new())
	p3.name = "p3"
	container.add_child(p3)
	p3.position = Vector3(10, 0, 0)
	inter.add_branch(p3)

	container.rebuild_segments(true)

	assert_eq(_edge_curves(inter).size(), 3, "New branch adds an edge curve")
	assert_not_null(inter.get_node_or_null("edge_p3"), "The new branch's edge curve exists")


func test_container_toggle_generates_and_clears_edges():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	var inter := _make_intersection(container)
	container.rebuild_segments(true)
	assert_eq(_edge_curves(inter).size(), 0, "No edge curves while the toggle is off")

	# Flipping the container toggle drives the intersection edges directly, without
	# waiting for a rebuild, in parallel with how it drives segment edge curves.
	container.create_edge_curves = true
	assert_eq(_edge_curves(inter).size(), 2, "Enabling the toggle generates intersection edges")

	container.create_edge_curves = false
	assert_eq(_edge_curves(inter).size(), 0, "Disabling the toggle clears intersection edges")

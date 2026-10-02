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


func _lanes(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is RoadLane and not child.is_queued_for_deletion():
			result.append(child)
	return result


func _lanes_for_edge(node: Node, edge_name: String) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is RoadLane and not child.is_queued_for_deletion() \
				and str(child.name).begins_with("%s_p" % edge_name):
			result.append(child)
	return result


func _tags(lanes: Array) -> Array:
	var result: Array = []
	for lane in lanes:
		result.append(lane.lane_prior_tag)
	result.sort()
	return result


# ------------------------------------------------------------------------------


func test_generates_one_lane_per_entering_lane():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)

	container.rebuild_segments(true)

	# Two default edges (2 forward + 2 reverse each): one enters forward, the
	# other enters reverse, for two entering lanes apiece.
	assert_eq(_lanes(inter).size(), 4, "One lane per entering lane")


func test_entering_lane_tags():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)

	container.rebuild_segments(true)

	# p1 connects on its next side, so the lanes travelling toward the
	# intersection (and through it) are its reverse lanes; p2 the forward ones.
	assert_eq(_tags(_lanes_for_edge(inter, "p1")), ["R0", "R1"], "Entering edge tags")
	assert_eq(_tags(_lanes_for_edge(inter, "p2")), ["F0", "F1"], "Entering edge tags")


func test_variable_lane_counts():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)
	# Edge p1 enters the intersection on its reverse lanes; give it three.
	var p1: RoadPoint = container.get_node("p1")
	p1.traffic_dir = [
		RoadPoint.LaneDir.REVERSE,
		RoadPoint.LaneDir.REVERSE,
		RoadPoint.LaneDir.REVERSE,
		RoadPoint.LaneDir.FORWARD,
	]

	container.rebuild_segments(true)

	assert_eq(_lanes_for_edge(inter, "p1").size(), 3, "Three entering reverse lanes")
	assert_eq(_lanes_for_edge(inter, "p2").size(), 2, "Two entering forward lanes")


func test_lane_visibility_follows_container():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)
	container.rebuild_segments(true)

	container.draw_lanes_editor = true
	container.draw_lanes_game = false
	for lane in _lanes(inter):
		assert_true(lane.draw_in_editor, "Editor draw follows container")
		assert_false(lane.draw_in_game, "Game draw follows container")

	container.draw_lanes_editor = false
	container.draw_lanes_game = true
	for lane in _lanes(inter):
		assert_false(lane.draw_in_editor, "Editor draw toggles off with container")
		assert_true(lane.draw_in_game, "Game draw toggles on with container")


func test_no_lanes_when_generation_disabled():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = false
	var inter := _make_intersection(container)

	container.rebuild_segments(true)

	assert_eq(_lanes(inter).size(), 0, "No lanes when generation disabled")


func test_rebuild_does_not_duplicate_lanes():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)

	container.rebuild_segments(true)
	container.rebuild_segments(true)

	assert_eq(_lanes(inter).size(), 4, "Lanes reused, not duplicated, on rebuild")


func test_lanes_added_to_ai_group():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	container.ai_lane_group = "test_ai_lanes"
	var inter := _make_intersection(container)

	container.rebuild_segments(true)

	var lanes := _lanes(inter)
	assert_eq(lanes.size(), 4, "All entering lanes generated")
	for lane in lanes:
		assert_true(lane.is_in_group("test_ai_lanes"), "Lane is in the AI lane group")


func test_lanes_have_curve_points():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)

	container.rebuild_segments(true)

	# RoadPoint, stop line, opposite stop line, opposite RoadPoint.
	for lane in _lanes(inter):
		assert_eq(lane.curve.point_count, 4, "Lane runs RoadPoint to RoadPoint via its stop lines")


func test_straight_through_lane_crosses_intersection():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)

	container.rebuild_segments(true)

	var lane: RoadLane = inter.get_node("p1_pR0_nR0")
	var lane_start := lane.get_lane_start()
	var lane_end := lane.get_lane_end()
	assert_almost_eq(lane_start.x, lane_end.x, 0.01, "Through lane keeps a constant offset")
	assert_true(lane_start.z < 0.0 and lane_end.z > 0.0, "Through lane spans both edges")


func test_through_lane_reaches_road_points():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)

	container.rebuild_segments(true)

	var lane: RoadLane = inter.get_node("p1_pR0_nR0")
	var p1: RoadPoint = container.get_node("p1")
	var p2: RoadPoint = container.get_node("p2")
	assert_almost_eq(lane.get_lane_start().z, p1.global_transform.origin.z, 0.01,
			"Lane starts at the entry RoadPoint, not the stop line")
	assert_almost_eq(lane.get_lane_end().z, p2.global_transform.origin.z, 0.01,
			"Lane ends at the exit RoadPoint, not the stop line")


func test_straight_through_keeps_tag():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)

	container.rebuild_segments(true)

	var lane: RoadLane = inter.get_node("p1_pR0_nR0")
	assert_eq(lane.lane_next_tag, "R0", "Straight-through lane exits with the same tag")


func test_mismatched_lane_counts_merge():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)
	# Three entering lanes feeding into two exit lanes opposite.
	var p1: RoadPoint = container.get_node("p1")
	p1.traffic_dir = [
		RoadPoint.LaneDir.REVERSE,
		RoadPoint.LaneDir.REVERSE,
		RoadPoint.LaneDir.REVERSE,
		RoadPoint.LaneDir.FORWARD,
	]

	container.rebuild_segments(true)

	assert_eq(_lanes_for_edge(inter, "p1").size(), 3, "All entering lanes generated")
	for lane in _lanes_for_edge(inter, "p1"):
		assert_eq(lane.curve.point_count, 4, "Each lane is routed")
	var extra: RoadLane = inter.get_node("p1_pR2_nR2r")
	assert_eq(extra.lane_next_tag, "R1", "Surplus lane merges into the outer exit lane")


func test_colinear_lane_stays_straight():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)

	container.rebuild_segments(true)

	var lane: RoadLane = inter.get_node("p1_pR0_nR0")
	var chord := lane.get_lane_start().distance_to(lane.get_lane_end())
	assert_almost_eq(lane.curve.get_baked_length(), chord, 0.1, "Colinear lane has no bulge")


func test_offset_lane_arcs_between_edges():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)
	# Shift the opposite edge sideways so the through lane must curve.
	var p2: RoadPoint = container.get_node("p2")
	p2.position += Vector3(10.0, 0.0, 0.0)

	container.rebuild_segments(true)

	var lane: RoadLane = inter.get_node("p1_pR0_nR0")
	var chord := lane.get_lane_start().distance_to(lane.get_lane_end())
	assert_gt(lane.curve.get_baked_length(), chord + 0.5, "Offset lane curves rather than cutting straight")


func _is_turn_lane(lane_name: String) -> bool:
	# Turn lanes carry an `a` suffix on their next tag: edge_pTAG_nTAGa[counter].
	return "a" in str(lane_name).get_slice("_n", 1)


func _nearest_edge(container: Node, source_name: String, point: Vector3) -> String:
	var best := ""
	var best_d := INF
	for child in container.get_children():
		if not (child is RoadPoint) or str(child.name) == source_name:
			continue
		var d: float = child.global_transform.origin.distance_to(point)
		if d < best_d:
			best_d = d
			best = str(child.name)
	return best


func _turn_lane_to(node: Node, container: Node, edge_name: String, target_name: String) -> RoadLane:
	# Turn names no longer carry the target edge, so match by geometry: the turn
	# lane off edge_name whose end lands nearer target_name than any other edge.
	var target: RoadPoint = container.get_node(target_name)
	var best: RoadLane = null
	var best_d := INF
	for child in node.get_children():
		if not (child is RoadLane) or not str(child.name).begins_with("%s_p" % edge_name):
			continue
		if not _is_turn_lane(child.name):
			continue
		var d: float = child.get_lane_end().distance_to(target.global_transform.origin)
		if d < best_d:
			best_d = d
			best = child
	if best == null or _nearest_edge(container, edge_name, best.get_lane_end()) != target_name:
		return null
	return best


func test_four_way_generates_through_and_turn_lanes():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	container.setup_road_container()
	road_util.create_intersection_four_branch(container)
	var inter: RoadIntersection = container.get_intersections()[0]

	container.rebuild_segments(true)

	# Each of four edges has two through lanes plus a turn to each adjacent edge.
	assert_eq(_lanes(inter).size(), 16, "Through and turn lanes for every edge")
	assert_eq(_lanes_for_edge(inter, "pn").size(), 4, "Two through and two turn lanes")


func test_four_way_turn_lane_reaches_target_edge():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	container.setup_road_container()
	road_util.create_intersection_four_branch(container)
	var inter: RoadIntersection = container.get_intersections()[0]

	container.rebuild_segments(true)

	var turn := _turn_lane_to(inter, container, "pn", "pw")
	assert_not_null(turn, "Turn lane from pn to pw exists")
	if turn == null:
		return
	var turn_start := turn.get_lane_start()
	var turn_end := turn.get_lane_end()
	assert_lt(turn_start.z, -1.0, "Turn starts on the north edge")
	assert_lt(turn_end.x, -1.0, "Turn ends on the west edge")
	var chord := turn_start.distance_to(turn_end)
	assert_gt(turn.curve.get_baked_length(), chord + 0.5, "Turn lane arcs around the corner")


func test_four_way_turn_handedness():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	container.setup_road_container()
	road_util.create_intersection_four_branch(container)
	var inter: RoadIntersection = container.get_intersections()[0]

	container.rebuild_segments(true)

	# From the north edge heading south, west (pw) is the right turn and east
	# (pe) the left turn. Right turns source from the outer (curb-side) lane,
	# left turns from the inner (divider-side) lane.
	var right_turn := _turn_lane_to(inter, container, "pn", "pw")
	var left_turn := _turn_lane_to(inter, container, "pn", "pe")
	assert_not_null(right_turn, "Right turn pn->pw exists")
	assert_not_null(left_turn, "Left turn pn->pe exists")
	if right_turn == null or left_turn == null:
		return
	# pn's entering lanes lie on the west (-X) half; the outer/right lane sits
	# further from the centerline than the inner/left lane.
	assert_lt(right_turn.get_lane_start().x, left_turn.get_lane_start().x,
			"Right turn sources from the outer lane, left turn from the inner lane")


func test_divider_alignment_shifts_lane_offset():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)
	var p1: RoadPoint = container.get_node("p1")
	p1.traffic_dir = [
		RoadPoint.LaneDir.REVERSE,
		RoadPoint.LaneDir.FORWARD,
		RoadPoint.LaneDir.FORWARD,
		RoadPoint.LaneDir.FORWARD,
	]

	p1.alignment = RoadPoint.Alignment.GEOMETRIC
	container.rebuild_segments(true)
	var geometric_x: float = (inter.get_node("p1_pR0_nR0") as RoadLane).get_lane_start().x

	p1.alignment = RoadPoint.Alignment.DIVIDER
	container.rebuild_segments(true)
	var divider_x: float = (inter.get_node("p1_pR0_nR0") as RoadLane).get_lane_start().x

	assert_almost_eq(divider_x - geometric_x, 4.0, 0.01, "Divider shifts entering lanes by one lane width")


func test_editable_lane_preserved_on_rebuild():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)
	container.rebuild_segments(true)

	var lane: RoadLane = inter.get_node("p1_pR0_nR0")
	lane.owner = container
	var custom := Curve3D.new()
	custom.add_point(Vector3(99, 0, 0))
	custom.add_point(Vector3(100, 0, 0))
	lane.curve = custom

	container.rebuild_segments(true)

	assert_eq(lane.curve.get_point_position(0), Vector3(99, 0, 0), "User-edited lane is left intact")


func test_custom_editable_lane_not_deleted_on_rebuild():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)
	container.rebuild_segments(true)

	# A lane the generator never produces (e.g. a hand-drawn U-turn), promoted to
	# editable by giving it an owner, must survive a rebuild rather than being
	# swept up with the stale generated lanes.
	var custom := RoadLane.new()
	inter.add_child(custom)
	custom.name = "custom_uturn"
	custom.owner = container

	container.rebuild_segments(true)

	assert_false(custom.is_queued_for_deletion(), "User-added editable lane survives rebuild")
	assert_not_null(inter.get_node_or_null("custom_uturn"), "Custom lane still present after rebuild")


# ------------------------------------------------------------------------------


func test_pairing_prefers_facing_over_position():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	container.setup_road_container()
	road_util.create_intersection_facing_split(container)
	var inter: RoadIntersection = container.get_intersections()[0]

	container.rebuild_segments(true)

	# ps routes through to pg, the edge that faces it head-on, rather than pb,
	# which sits more directly opposite but points sideways.
	assert_not_null(inter.get_node_or_null("ps_pR0_nR0"), "Source emits a through lane")
	var through: RoadLane = inter.get_node("ps_pR0_nR0")
	var pg: RoadPoint = container.get_node("pg")
	var pb: RoadPoint = container.get_node("pb")
	var ends_at := through.get_lane_end()
	assert_lt(ends_at.distance_to(pg.global_transform.origin),
			ends_at.distance_to(pb.global_transform.origin),
			"Through lane reaches the head-on edge pg, not the dead-opposite pb")


func test_pairing_lateral_cost_scales_with_lane_width():
	# The pairing loss blends a lateral offset with a facing angle. Because a road
	# built with wider lanes spaces its edges proportionally wider, the lateral
	# term is divided by lane width so it stays comparable to the width-independent
	# angle instead of swamping it on supersized roads.
	var ngon := IntersectionNGon.new()
	var rel := Vector3(6, 0, 10)
	var dir := Vector3(0, 0, 1)
	assert_almost_eq(ngon._pairing_lateral_cost(rel, dir, RoadPoint.DEFAULT_LANE_WIDTH), 6.0, 0.001,
			"At the default lane width the cost is the raw perpendicular distance")
	assert_almost_eq(ngon._pairing_lateral_cost(rel, dir, RoadPoint.DEFAULT_LANE_WIDTH * 2.0), 3.0, 0.001,
			"Doubling the lane width halves the lateral cost")


func test_turn_handedness_follows_primary_not_inbound():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	container.setup_road_container()
	road_util.create_intersection_facing_split(container)
	var inter: RoadIntersection = container.get_intersections()[0]

	container.rebuild_segments(true)

	# ps routes through to pg (off to its right), leaving pb as a turn target that
	# sits to the right of that through path. Handedness is measured against the
	# primary, so the pb turn is a right turn sourced from the outer lane (R1),
	# even though pb lies left of ps's raw inbound axis.
	var turn := _turn_lane_to(inter, container, "ps", "pb")
	assert_not_null(turn, "Turn to pb exists")
	if turn == null:
		return
	assert_eq(turn.lane_prior_tag, "R1",
			"Turn to pb sources from the outer lane (right of the ps->pg primary), "
			+ "not the inner lane implied by the raw inbound direction")


func _make_t_junction(container) -> RoadIntersection:
	container.setup_road_container()
	road_util.create_intersection_three_branch(container)
	return container.get_intersections()[0]


func test_t_junction_bar_edges_pair_through():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_t_junction(container)

	container.rebuild_segments(true)

	# pw and pe form the straight bar, so each carries its entering lanes across.
	var lane: RoadLane = inter.get_node("pw_pR0_nR0")
	assert_eq(lane.curve.point_count, 4, "Through lane runs RoadPoint to RoadPoint")
	assert_true(lane.get_lane_start().x < 0.0 and lane.get_lane_end().x > 0.0,
			"Through lane spans both bar edges")


func test_t_junction_stem_routes_through_to_primary():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_t_junction(container)

	container.rebuild_segments(true)

	# Incoming lanes always connect to the primary, even on the stem: both of its
	# entering lanes route through to pw (the bar edge it points most directly at).
	assert_not_null(inter.get_node_or_null("ps_pR0_nR0"), "Stem routes to its primary")
	assert_not_null(inter.get_node_or_null("ps_pR1_nR1"), "Stem routes to its primary")


func test_t_junction_stem_turns_to_non_primary_bar():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_t_junction(container)

	container.rebuild_segments(true)

	# pw is the stem's primary (taken as a through lane); the other bar edge pe is
	# reached as a turn.
	assert_not_null(_turn_lane_to(inter, container, "ps", "pe"), "Stem turns toward the non-primary bar")
	assert_null(_turn_lane_to(inter, container, "ps", "pw"), "Primary bar is a through lane, not a turn")


func test_t_junction_lane_count():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_t_junction(container)

	container.rebuild_segments(true)

	# Bar edges: two through lanes plus a turn to the stem apiece (3 each); stem:
	# two through lanes to its primary plus a turn to the other bar (3).
	assert_eq(_lanes(inter).size(), 9, "Through and turn lanes for the T")

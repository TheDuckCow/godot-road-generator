extends "res://addons/gut/test.gd"

const RoadUtils = preload("res://test/unit/road_utils.gd")

var road_util: RoadUtils


func before_each():
	road_util = RoadUtils.new()
	road_util.gut = gut


# ------------------------------------------------------------------------------


func test_create_road_point():
	var _pt = autoqfree(RoadPoint.new())
	pass_test('nothing tested, passing')


var count_params = [1, 2, 3, 4, 5, 6]

func test_auto_lanes_count(params=use_parameters(count_params)):
	var pt = autoqfree(RoadPoint.new())
	var nullarray: Array[RoadPoint.LaneDir] = []
	pt.traffic_dir = nullarray
	for _i in range(params):
		pt.traffic_dir.append(pt.LaneDir.NONE)
	pt.assign_lanes()
	assert_eq(len(pt.lanes), len(pt.traffic_dir), "Matching lane count generated")
	assert_eq(len(pt.lanes), params, "Matching lane param count")


var auto_lane_pairs = [
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.TWO_WAY, RoadPoint.LaneType.TWO_WAY],
		"Two way"
	],
	[
		[RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.NO_MARKING],
		"One way forward"
	],
	[
		[RoadPoint.LaneDir.REVERSE],
		[RoadPoint.LaneType.NO_MARKING],
		"One way reverse"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.TWO_WAY, RoadPoint.LaneType.FAST, RoadPoint.LaneType.SLOW],
		"3-lane"
	],
	[
		[RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.NO_MARKING, RoadPoint.LaneType.MIDDLE, RoadPoint.LaneType.SLOW],
		"3-lane one way forward"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.MIDDLE, RoadPoint.LaneType.NO_MARKING],
		"3-lane one way reverse"
	],
]

func test_auto_lanes_sequence(params=use_parameters(auto_lane_pairs)):
	var pt = autoqfree(RoadPoint.new())
	#var assign_dir: Array[RoadPoint.LaneDir] = params[0] as Array[RoadPoint.LaneDir]
	# use array.assign() I guess, huh. https://forum.godotengine.org/t/cast-untyped-array-to-typed-array/50135/2
	pt.traffic_dir.assign(params[0]) # = assign_dir
	var target = params[1]
	pt.assign_lanes()
	assert_eq(pt.lanes, target, "Auto lane %s" % params[2])


func test_error_no_traffic_dir():
	var pt = autoqfree(RoadPoint.new())
	pt.traffic_dir.assign([])
	pt.assign_lanes()
	pass_test('nothing tested, passing')


## A one-way <-> two-way transition renders no mesh, so the connected RoadPoints
## should surface a configuration warning instead of silently failing.
func test_config_warning_invalid_lane_transition():
	var container = add_child_autofree(RoadContainer.new())
	container._auto_refresh = false
	var points = road_util.create_unconnected_container(container)
	var p1 = points[0]
	var p2 = points[1]
	p1.next_pt_init = p1.get_path_to(p2)
	p2.prior_pt_init = p2.get_path_to(p1)

	# Invalid: p1 two-way (BOTH), p2 one-way (REVERSE), sharing the first dir.
	p1.traffic_dir.assign([RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD])
	p2.traffic_dir.assign([RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE])
	assert_gt(p1._get_configuration_warnings().size(), 0, "p1 warns on invalid transition")
	assert_gt(p2._get_configuration_warnings().size(), 0, "p2 warns on invalid transition")

	# Valid: both two-way -> transition warning clears.
	p2.traffic_dir.assign([RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD])
	assert_eq(p1._get_configuration_warnings().size(), 0, "p1 clear when transition valid")
	assert_eq(p2._get_configuration_warnings().size(), 0, "p2 clear when transition valid")


## A malformed lane order (a FORWARD lane before a REVERSE one) renders no mesh,
## so the RoadPoint should warn on its own without a neighbour.
func test_config_warning_malformed_lane_order():
	var container = add_child_autofree(RoadContainer.new())
	container._auto_refresh = false
	var pt = road_util.create_unconnected_container(container)[0]

	pt.traffic_dir.assign([RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD])
	assert_gt(pt._get_configuration_warnings().size(), 0, "Warns on malformed lane order")

	# REVERSE-before-FORWARD order is valid and clears the warning.
	pt.traffic_dir.assign([RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD])
	assert_eq(pt._get_configuration_warnings().size(), 0, "Clear on valid lane order")


func test_autofix_noncyclic_added_next():
	var container = add_child_autofree(RoadContainer.new())
	container._auto_refresh = false

	var points = road_util.create_unconnected_container(container)
	var p1 = points[0]
	var p2 = points[1]

	container._auto_refresh = true
	watch_signals(container)

	# The change which should trigger an auto path fix and thus a signal
	p1.next_pt_init = p1.get_path_to(p2)

	# Validate that the road segment was generated (based on signal emission)
	var res = get_signal_parameters(container, 'on_road_updated')
	if res == null:
		fail_test("No signal emitted at all to fetch")
	else:
		var segments_updated = res[0]
		assert_eq(len(segments_updated), 1, "Single segment created")
		assert_signal_emit_count(container, "on_road_updated", 1, "One signal call")

	# Validate the other connection is there too now.
	var expected_p2_prior = p2.get_path_to(p1)
	assert_eq(p2.prior_pt_init, expected_p2_prior, "Check reverse connection made")


func test_junction_validate_init_path_just_removed():
	var container = add_child_autofree(RoadContainer.new())
	container._auto_refresh = false

	var points = road_util.create_unconnected_container(container)
	var p1 = points[0]
	var p2 = points[1]

	# The change which should trigger an auto path fix and thus a signal
	p1.next_pt_init = p1.get_path_to(p2)
	p2.prior_pt_init = p2.get_path_to(p1)

	# Trigger build.
	container._auto_refresh = true
	container.rebuild_segments(true)

	# should have a child segment now, TODO assert this.
	watch_signals(container)

	# The main test line: ie clear it out during auto refresh.
	# Should trigger _autofix_noncyclic_references.
	p1.next_pt_init = ""

	# Validate that the road segment was deleted
	# No args to parse, so only removal
	assert_signal_emit_count(container, "on_road_updated", 1, "One signal call")

	var ref_path:NodePath = ""
	assert_eq(p1.next_pt_init, ref_path, "P1's next should have stayed cleared")
	assert_eq(p2.prior_pt_init, ref_path, "P2's prior point should be cleared")


func test_on_road_updated_pt_transform():
	var container = add_child_autofree(RoadContainer.new())
	container._auto_refresh = false

	var points = road_util.create_unconnected_container(container)
	var p1 = points[0]
	var p2 = points[1]

	# Connect the two together
	p1.next_pt_init = p1.get_path_to(p2)
	p2.prior_pt_init = p2.get_path_to(p1)

	container._auto_refresh = true
	# should have a child segment now, TODO assert this.
	watch_signals(container)

	# Trigger a transform equivalent to moving the point in the viewport.
	# Changing global_transform doesn't work since it checks for editor,
	# so we need to directly call the on_transform function.
	p1.emit_transform()

	# Validate that the road segment was generated (based on signal emission)
	var res = get_signal_parameters(container, 'on_road_updated')
	if res == null:
		fail_test("No signal emitted at all to fetch")
	else:
		var segments_updated = res[0]
		assert_eq(len(segments_updated), 1, "Single segment created")
		assert_signal_emit_count(container, "on_road_updated", 1, "One signal call")


func test_connect_roadpoint():
	var container = add_child_autofree(RoadContainer.new())
	container._auto_refresh = false

	var points = road_util.create_unconnected_container(container)
	var p1 = points[0]
	var p2 = points[1]

	var res = p1.connect_roadpoint(RoadPoint.PointInit.NEXT, p2, RoadPoint.PointInit.PRIOR)
	assert_true(res, "Connect RPs with no prior connections")
	res = p1.connect_roadpoint(RoadPoint.PointInit.NEXT, p2, RoadPoint.PointInit.PRIOR)
	assert_false(res, "Should fail to re-connect the same RP and direction")
	res = p1.connect_roadpoint(RoadPoint.PointInit.PRIOR, p2, RoadPoint.PointInit.PRIOR)
	assert_false(res, "Should fail to connect an already connected directions")


func test_roadpoint_disconnection():
	# Setup: create and connect two RoadPoints
	var container = add_child_autofree(RoadContainer.new())
	container._auto_refresh = false

	var points = road_util.create_unconnected_container(container)
	var p1 = points[0]
	var p2 = points[1]

	# Connect the two together
	p1.next_pt_init = p1.get_path_to(p2)
	p2.prior_pt_init = p2.get_path_to(p1)

	container._auto_refresh = true
	# should have a child segment now, TODO assert this.
	watch_signals(container)

	# Now use the disconnect function explicitly
	var res = p1.disconnect_roadpoint(RoadPoint.PointInit.NEXT, RoadPoint.PointInit.PRIOR)
	assert_true(res, "Should be able to disconnect valid connection")
	res = p1.disconnect_roadpoint(RoadPoint.PointInit.NEXT, RoadPoint.PointInit.PRIOR)
	assert_false(res, "Should fail to disconnect already disconnected rp")
	res = p1.disconnect_roadpoint(RoadPoint.PointInit.PRIOR, RoadPoint.PointInit.PRIOR)
	assert_false(res, "Should fail to disconnect invalid connection prior to prior")


# Builds a connected RP line and flushes the deferred rebuild.
func _build_line(count: int, thickness: float = -1.0) -> Array:
	var container = add_child_autofree(RoadContainer.new())
	container.underside_thickness = thickness
	var points = road_util.create_rp_line(container, count, true, true)
	container.rebuild_segments(true)
	await wait_process_frames(2)
	return [container, points]


# Mimics the Scene-dock "Remove Node(s)": clear paths, remove, undo re-adds.
func _native_delete_action(container, rp: RoadPoint, paths: Array) -> UndoRedo:
	var ur := UndoRedo.new()
	ur.create_action("Remove Node(s)")
	for entry in paths:
		ur.add_do_property(entry[0], entry[1], NodePath())
		ur.add_undo_property(entry[0], entry[1], entry[0].get(entry[1]))
	ur.add_do_method(container.remove_child.bind(rp))
	ur.add_undo_method(container.add_child.bind(rp, true))
	ur.add_undo_method(container.move_child.bind(rp, rp.get_index()))
	ur.add_undo_reference(rp)
	return ur


func test_native_delete_undo_relinks_end_point():
	var res = await _build_line(3, 1.0) # Underside, so end fills matter.
	var container = res[0]
	var points = res[1]
	var p1: RoadPoint = points[1]
	var rp: RoadPoint = points[2]
	var old_prior: NodePath = rp.prior_pt_init
	var old_next: NodePath = p1.next_pt_init
	assert_false(old_prior.is_empty(), "Setup: rp prior linked")

	var ur := _native_delete_action(container, rp, [[p1, "next_pt_init"]])
	ur.commit_action()
	await wait_process_frames(2)
	assert_false(rp.is_inside_tree(), "rp removed")
	assert_false(rp.is_bare_edge(RoadPoint.PointInit.NEXT), "Out of tree is not bare")
	ur.undo()
	await wait_process_frames(3)

	assert_true(rp.is_inside_tree(), "rp back in tree")
	assert_eq(rp.prior_pt_init, old_prior, "rp prior restored")
	assert_eq(p1.next_pt_init, old_next, "p1 next restored")
	assert_true(is_instance_valid(p1.next_seg), "p1 next seg valid")
	if is_instance_valid(p1.next_seg):
		assert_false(p1.next_seg.is_queued_for_deletion(), "seg not queued")
		assert_eq(p1.next_seg.end_point, rp, "seg ends at rp")
		var seg = p1.next_seg
		assert_false(seg.is_end_fill_stale(), "No stale end fill")
		assert_false(seg._built_bare_near, "p1 end connected")
		assert_true(seg._built_bare_far, "rp end bare")
	if is_instance_valid(p1.prior_seg):
		assert_true(p1.prior_seg._built_bare_near, "p0 end bare")
		assert_false(p1.prior_seg._built_bare_far, "p1 end connected")
	else:
		fail_test("p1 prior seg missing")
	assert_eq(container.get_segments().size(), 2, "Both segments present")
	ur.free()


func test_inspector_clear_then_reenter_stays_disconnected():
	var res = await _build_line(3)
	var container = res[0]
	var points = res[1]
	points[1].next_pt_init = ^""
	assert_eq(points[2].prior_pt_init, NodePath(), "Setup: autofix cleared prior")
	assert_false(points[2]._autofix_cleared.is_empty(), "Setup: memo written")

	var par = container.get_parent()
	par.remove_child(container)
	par.add_child(container)
	await wait_process_frames(3)

	assert_eq(points[2].prior_pt_init, NodePath(), "prior stays clear")
	assert_eq(points[1].next_pt_init, NodePath(), "next stays clear")
	assert_eq(container.get_segments().size(), 1, "One segment left")
	assert_true(points[2]._autofix_cleared.is_empty(), "Memo consumed")

extends "res://addons/gut/test.gd"


func before_each():
	gut.p("ran setup", 2)

func after_each():
	gut.p("ran teardown", 2)

func before_all():
	gut.p("ran run setup", 2)

func after_all():
	gut.p("ran run teardown", 2)

# ------------------------------------------------------------------------------


## Utility to create a single segment network (2 points)
func create_unconnected_network(network) -> Array:
	network.setup_road_network()
	assert_eq(network.get_child_count(), 0, "No initial point children")

	var p1 = autoqfree(RoadPoint.new())
	var p2 = autoqfree(RoadPoint.new())

	network.add_child(p1)
	network.add_child(p2)
	assert_eq(network.get_child_count(), 2, "Both RPs added")

	return [p1, p2]


# ------------------------------------------------------------------------------


func test_create_road_point():
	var _pt = autoqfree(RoadPoint.new())
	pass_test('nothing tested, passing')


var count_params = [1, 2, 3, 4, 5, 6]

func test_auto_lanes_count(params=use_parameters(count_params)):
	var pt = autoqfree(RoadPoint.new())
	pt.traffic_dir = []
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

	pt.traffic_dir = params[0]
	var target = params[1]
	pt.assign_lanes()
	assert_eq(pt.lanes, target, "Auto lane %s" % params[2])


func test_error_no_traffic_dir():
	var pt = autoqfree(RoadPoint.new())
	pt.traffic_dir = []
	pt.assign_lanes()
	pass_test('nothing tested, passing')


func test_autofix_noncyclic_added_next():
	var network = add_child_autofree(RoadContainer.new())
	network.auto_refresh = false

	var points = create_unconnected_network(network)
	var p1 = points[0]
	var p2 = points[1]

	network.auto_refresh = true
	watch_signals(network)

	# The change which should trigger an auto path fix and thus a signal
	p1.next_pt_init = p1.get_path_to(p2)

	# Validate that the road segment was generated (based on signal emission)
	var res = get_signal_parameters(network, 'on_road_updated')
	if res == null:
		fail_test("No signal emitted at all to fetch")
	else:
		var segments_updated = res[0]
		assert_eq(len(segments_updated), 1, "Single segment created")
		assert_signal_emit_count(network, "on_road_updated", 1, "One signal call")

	# Validate the other connection is there too now.
	var expected_p2_prior = p2.get_path_to(p1)
	assert_eq(p2.prior_pt_init, expected_p2_prior, "Check reverse connection made")


func test_junction_validate_init_path_just_removed():
	var network = add_child_autofree(RoadContainer.new())
	network.auto_refresh = false

	var points = create_unconnected_network(network)
	var p1 = points[0]
	var p2 = points[1]

	# The change which should trigger an auto path fix and thus a signal
	p1.next_pt_init = p1.get_path_to(p2)
	p2.prior_pt_init = p2.get_path_to(p1)

	# Trigger build.
	network.auto_refresh = true
	network.rebuild_segments(true)

	# should have a child segment now, TODO assert this.
	watch_signals(network)

	# The main test line: ie clear it out during auto refresh.
	# Should trigger _autofix_noncyclic_references.
	p1.next_pt_init = ""

	# Validate that the road segment was deleted
	# No args to parse, so only removal
	assert_signal_emit_count(network, "on_road_updated", 1, "One signal call")

	var ref_path:NodePath = ""
	assert_eq(p1.next_pt_init, ref_path, "P1's next should have stayed cleared")
	assert_eq(p2.prior_pt_init, ref_path, "P2's prior point should be cleared")


func test_on_road_updated_pt_transform():
	var network = add_child_autofree(RoadContainer.new())
	network.auto_refresh = false

	var points = create_unconnected_network(network)
	var p1 = points[0]
	var p2 = points[1]

	# Connect the two together
	p1.next_pt_init = p1.get_path_to(p2)
	p2.prior_pt_init = p2.get_path_to(p1)

	network.auto_refresh = true
	# should have a child segment now, TODO assert this.
	watch_signals(network)

	# Trigger a transform equivalent to moving the point in the viewport.
	# Changing global_transform doesn't work since it checks for editor,
	# so we need to directly call the on_transform function.
	p1.on_transform()

	# Validate that the road segment was generated (based on signal emission)
	var res = get_signal_parameters(network, 'on_road_updated')
	if res == null:
		fail_test("No signal emitted at all to fetch")
	else:
		var segments_updated = res[0]
		assert_eq(len(segments_updated), 1, "Single segment created")
		assert_signal_emit_count(network, "on_road_updated", 1, "One signal call")

extends "res://addons/gut/test.gd"


func before_each():
	gut.p("ran setup", 2)

func after_each():
	gut.p("ran teardown", 2)

func before_all():
	gut.p("ran run setup", 2)

func after_all():
	gut.p("ran run teardown", 2)


## Utility to create a single segment network (2 points)
func create_oneseg_network(network):
	network.setup_road_network()
	var points = network.get_node(network.points)
	var segments = network.get_node(network.segments)

	assert_eq(points.get_child_count(), 0, "No initial point children")
	assert_eq(segments.get_child_count(), 0, "No initial segment children")

	var p1 = autoqfree(RoadPoint.new())
	var p2 = autoqfree(RoadPoint.new())

	points.add_child(p1)
	points.add_child(p2)
	assert_eq(points.get_child_count(), 2, "Both RPs added")

	p1.next_pt_init = p1.get_path_to(p2)
	p2.prior_pt_init = p2.get_path_to(p1)


# ------------------------------------------------------------------------------

func test_road_network_create():
	var network = autoqfree(RoadNetwork.new())
	# Check the children are set up.

	watch_signals(network)
	assert_signal_emit_count(network, "on_road_updated", 0, "Don't signal create")

	# Trigger the auto setup which happens deferred in _ready
	network.setup_road_network()

	# Ensure the automatic nodes got set up.
	var points = network.get_node(network.points)
	var segments = network.get_node(network.segments)
	assert_true(is_instance_valid(points))
	assert_true(is_instance_valid(segments))

	# Since only setup, still should not have triggered on update.
	assert_signal_emit_count(network, "on_road_updated", 0, "Don't signal setup")
	network.rebuild_segments()
	# Now it's updated
	assert_signal_emit_count(network, "on_road_updated", 1, "Signal after rebuild")


func test_on_road_updated_single_segment():
	var network = add_child_autofree(RoadNetwork.new())
	watch_signals(network)

	create_oneseg_network(network)

	# Now trigger the update, to see that a single segment was made
	network.rebuild_segments()
	var res = get_signal_parameters(network, 'on_road_updated')
	print_debug(res)
	var segments_updated = res[0]
	assert_eq(len(segments_updated), 1, "Single segment created")
	assert_signal_emit_count(network, "on_road_updated", 1, "One signal call")

func test_on_road_updated_pt_transform():
	pending('Implement test which asserts on_road_updated called on RoadPoint transform')



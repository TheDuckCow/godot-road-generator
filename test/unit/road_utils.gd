extends "res://addons/gut/test.gd"

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

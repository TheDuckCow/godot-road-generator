extends "res://addons/gut/test.gd"


func create_segment_with_manager():
	var manager = add_child_autofree(RoadManager.new())
	var container = autoqfree(RoadContainer.new())
	var p1 = autoqfree(RoadPoint.new())
	var p2 = autoqfree(RoadPoint.new())
	var road_points = [p1, p2]

	p1.next_pt_init = p1.get_path_to(p2)
	p2.prior_pt_init = p2.get_path_to(p1)

	assert_eq(container.get_child_count(), 2, "Both RPs added")
	assert_eq(p1.get_child_count(), 1, "One RoadSegment created")
	container.rebuild_segments()
	var segment = p1.get_child(0)
	assert_true(segment.has_method("is_road_segment"))

	return [manager, container, road_points, segment]


func test_create_road_manager():
	var _pt = autoqfree(RoadManager.new())
	pass_test('nothing tested, passing')


func test_set_density():
	pass_test('Not ready')
	return
	# Need to setup full tree
	var res = create_segment_with_manager()
	var manager = res[0]
	var container = res[1]
	var segment = res[3]

	assert_gt(manager.density, 0)
	assert_eq(container.density, -1)
	assert_eq(segment.density, manager.density)

	manager.density = PI
	assert_eq(manager.density, PI)
	assert_eq(segment.density, manager.density)

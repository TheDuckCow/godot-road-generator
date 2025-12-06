extends "res://addons/gut/test.gd"

const RoadUtils = preload("res://test/unit/road_utils.gd")
const RoadMaterial = preload("res://addons/road-generator/resources/road_texture.material")

var road_util: RoadUtils

func before_each():
	gut.p("ran setup", 2)
	road_util = RoadUtils.new()
	road_util.gut = gut


func _validate_edges(container: RoadContainer) -> void:
	var edges = container.get_open_edges()
	assert_eq(len(edges), 2, "Should have 2 RP edges")
	for _edge in edges:
		assert_is(_edge, RoadPoint, "Should only have roadpoint edges")


# ------------------------------------------------------------------------------


func test_intersection_creation():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.setup_road_container()
	
	road_util.create_intersection_two_branch(container)
	
	var pts = container.get_roadpoints()
	assert_eq(len(pts), 2, "Should have 2 roadpoints")
	var ints = container.get_intersections()
	assert_eq(len(ints), 1, "Should have 1 intersection")
	assert_eq(ints[0].container, container, "Container should be assigned")


func test_on_road_updated_signal_after_container_refresh():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.setup_road_container()
	road_util.create_intersection_two_branch(container)
	watch_signals(container)

	container.rebuild_segments(true)

	var res = get_signal_parameters(container, 'on_road_updated')
	assert_not_null(res, "Should have on_road_updated emitted")
	if res == null:
		return
	var segments_updated = res[0]
	assert_eq(len(segments_updated), 1, "Should have single segment created")
	assert_signal_emit_count(container, "on_road_updated", 1, "One signal call")
	assert_is(segments_updated[0], RoadIntersection, "Should be a road intersection only")
	
	_validate_edges(container)


func test_on_road_updated_signal_after_inter_moved():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.setup_road_container()
	road_util.create_intersection_two_branch(container)
	watch_signals(container)
	
	var inter:RoadIntersection = container.get_child(0)
	# Trigger a transform equivalent to moving the point in the viewport.
	# Changing global_transform doesn't work since it checks for editor,
	# so we need to directly call the on_transform function.
	inter.emit_transform()

	var res = get_signal_parameters(container, 'on_road_updated')
	print("What is? ", res, " and ", res == null, " vs null ", null)
	assert_not_null(res, "Should have on_road_updated emitted")
	if res == null:
		return
	var segments_updated = res[0]
	assert_eq(len(segments_updated), 1, "Should have single segment created")
	assert_signal_emit_count(container, "on_road_updated", 1, "One signal call")
	assert_is(segments_updated[0], RoadIntersection, "Should be a road intersection only")
	
	_validate_edges(container)


func test_on_road_updated_signal_after_rp_moved():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.setup_road_container()
	road_util.create_intersection_two_branch(container)
	watch_signals(container)
	_validate_edges(container)
	
	var rp:RoadPoint = container.get_child(1)
	# Trigger a transform equivalent to moving the point in the viewport.
	# Changing global_transform doesn't work since it checks for editor,
	# so we need to directly call the on_transform function.
	rp.emit_transform()
	var res = get_signal_parameters(container, 'on_road_updated')
	assert_not_null(res, "Should have on_road_updated emitted")
	if res == null:
		return
	var segments_updated = res[0]
	assert_eq(len(segments_updated), 1, "Should have single segment created")
	assert_signal_emit_count(container, "on_road_updated", 1, "One signal call")
	assert_is(segments_updated[0], RoadIntersection, "Should be a road intersection only")
	
	_validate_edges(container)


func test_intersection_add_branch():
	pass


func test_intersection_remove_branch():
	pass

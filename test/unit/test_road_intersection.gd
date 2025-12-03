extends "res://addons/gut/test.gd"

const RoadUtils = preload("res://test/unit/road_utils.gd")
const RoadMaterial = preload("res://addons/road-generator/resources/road_texture.material")

var road_util: RoadUtils

func before_each():
	gut.p("ran setup", 2)
	road_util = RoadUtils.new()
	road_util.gut = gut


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


func test_on_intersection_updated_single_signal():
	pass


func test_intersection_add_branch():
	pass


func test_intersection_remove_branch():
	pass

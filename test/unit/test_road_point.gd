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

func test_create_road_point():
	var pt = RoadPoint.new()
	pt.queue_free()


var count_params = [1, 2, 3, 4, 5, 6]

func test_auto_lanes_count(params=use_parameters(count_params)):
	var pt = RoadPoint.new()
	pt.traffic_dir = []
	for _i in range(params):
		pt.traffic_dir.append(pt.LaneDir.NONE)
	pt.assign_lanes()
	assert_eq(len(pt.lanes), len(pt.traffic_dir), "Matching lane count generated")
	assert_eq(len(pt.lanes), params, "Matching lane param count")


var auto_lan_paris = [
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.TWO_WAY, RoadPoint.LaneType.TWO_WAY],
		"Two way"
	],
	[
		[RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.ONE_WAY],
		"One way"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.TWO_WAY, RoadPoint.LaneType.FAST, RoadPoint.LaneType.SLOW],
		"3-lane"
	],
	[
		[RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.MIDDLE, RoadPoint.LaneType.SLOW],
		"3-lane one way"
	],
]

func test_auto_lanes_sequence(params=use_parameters(auto_lan_paris)):
	var pt = RoadPoint.new()
	
	pt.traffic_dir = params[0]
	var target = params[1]
	pt.assign_lanes()
	assert_eq(pt.lanes, target, "Auto lane %s" % params[2])


func test_error_no_traffic_dir():
	var pt = RoadPoint.new()
	pt.traffic_dir = []
	pt.assign_lanes()

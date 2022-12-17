extends "res://addons/gut/test.gd"
# ------------------------------------------------------------------------------
# This script contains test cases for the road_segment._match_lanes function.
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# auto_lane_setup array format:
# 0 start point traffic dir
# 1 end point traffic dir
# 2 start point lane types
# 3 expected result
# 4 Test case label
# ------------------------------------------------------------------------------
var auto_lane_setup = [
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RF > RF >> --"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM],
		"RFF > RRF >> A--R"
	],
]

func test_match_lanes_sequence(params=use_parameters(auto_lane_setup)):
	var seg = RoadSegment.new(null)
	
	seg.start_point = RoadPoint.new()
	seg.end_point = RoadPoint.new()
	seg.start_point.traffic_dir = params[0]
	seg.end_point.traffic_dir = params[1]
	seg.start_point.lanes = params[2]
	
	var target = params[3]
	var result = seg._match_lanes()
	assert_eq(result, target, "Match lanes %s" % params[4])

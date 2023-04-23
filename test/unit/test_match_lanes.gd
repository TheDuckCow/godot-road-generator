## This script contains test cases for the road_segment._match_lanes function.
##
## Array format:
## 0 start point traffic dir
## 1 end point traffic dir
## 2 start point lane types
## 3 expected result lane types
## 4 Test case label, with a structure of:
##    Direction start > Direction end > expected outcome, where
##    Direction start/end: F=forward lane, R=reverse lane
##    expected outcome: Lanes start to end: F=fast, S=slow, A=add, R=remove
##    and where `|` = direction switch/double yellow (not an actual lane, just a visual aide)

extends "res://addons/gut/test.gd"

var auto_lane_setup = [
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.FAST, RoadPoint.LaneType.FAST],
		[[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.FORWARD]],
		"RF > RF >> F|F",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.FAST, RoadPoint.LaneType.FAST],
		[[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.FORWARD],[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneDir.FORWARD]],
		"RF > RFF >> F|FA",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.FAST, RoadPoint.LaneType.FAST, RoadPoint.LaneType.SLOW],
		[[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.FORWARD],[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneDir.FORWARD]],
		"RFF > RF >> F|FR",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.FAST, RoadPoint.LaneType.FAST, RoadPoint.LaneType.SLOW],
		[[RoadPoint.LaneType.SLOW, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.FORWARD],[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneDir.FORWARD]],
		"RRFF > RRF >> SF|FR",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.FAST, RoadPoint.LaneType.FAST],
		[[RoadPoint.LaneType.SLOW, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.FORWARD],[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneDir.FORWARD]],
		"RRF > RRFF >> SF|FA",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.FAST, RoadPoint.LaneType.FAST],
		[[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.SLOW, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.FORWARD]],
		"RRRF > RRF >> RSF|F",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.FAST, RoadPoint.LaneType.FAST],
		[[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.SLOW, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.FORWARD]],
		"RRF > RRRF >> ASF|F",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.FAST, RoadPoint.LaneType.FAST, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.FORWARD],[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneDir.FORWARD],[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneDir.FORWARD]],
		"RRRFFF > RF >> RRF|FRR",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.FAST, RoadPoint.LaneType.FAST],
		[[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.FORWARD],[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneDir.FORWARD],[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneDir.FORWARD]],
		"RF > RRRFFF >> AAF|FAA",
	],
]

var one_way_lane_setup = [
	[
		[RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.NO_MARKING],
		[[RoadPoint.LaneType.NO_MARKING, RoadPoint.LaneDir.FORWARD]],
		"F > F >> |M",
	],
	[
		[RoadPoint.LaneDir.REVERSE],
		[RoadPoint.LaneDir.REVERSE],
		[RoadPoint.LaneType.NO_MARKING],
		[[RoadPoint.LaneType.NO_MARKING, RoadPoint.LaneDir.REVERSE]],
		"R > R >> M|",
	],
	[
		[RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.NO_MARKING, RoadPoint.LaneType.SLOW],
		[[RoadPoint.LaneType.NO_MARKING, RoadPoint.LaneDir.FORWARD],[RoadPoint.LaneType.SLOW, RoadPoint.LaneDir.FORWARD]],
		"FF > FF >> |MS",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.MIDDLE],
		[[RoadPoint.LaneType.SLOW, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.MIDDLE, RoadPoint.LaneDir.REVERSE]],
		"RR > RR >> SM|",
	],
	[
		[RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.NO_MARKING, RoadPoint.LaneType.SLOW],
		[[RoadPoint.LaneType.NO_MARKING, RoadPoint.LaneDir.FORWARD],[RoadPoint.LaneType.SLOW, RoadPoint.LaneDir.FORWARD],[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneDir.FORWARD]],
		"FF > FFF >> |MSA",
	],
	[
		[RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.NO_MARKING, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[[RoadPoint.LaneType.NO_MARKING, RoadPoint.LaneDir.FORWARD],[RoadPoint.LaneType.SLOW, RoadPoint.LaneDir.FORWARD],[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneDir.FORWARD]],
		"FFF > FF >> |MSR",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.MIDDLE],
		[[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.SLOW, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.MIDDLE, RoadPoint.LaneDir.REVERSE]],
		"RR > RRR >> ASM|",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.MIDDLE],
		[[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.SLOW, RoadPoint.LaneDir.REVERSE],[RoadPoint.LaneType.MIDDLE, RoadPoint.LaneDir.REVERSE]],
		"RRR > RR >> RSM|",
	],
	[
		[RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[],
		"FF > RR >> ",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE],
		[RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[],
		"RR > FF >> ",
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

func test_one_way_lanes_sequence(params=use_parameters(one_way_lane_setup)):
	var seg = RoadSegment.new(null)

	seg.start_point = RoadPoint.new()
	seg.end_point = RoadPoint.new()
	seg.start_point.traffic_dir = params[0]
	seg.end_point.traffic_dir = params[1]
	seg.start_point.lanes = params[2]

	var target = params[3]
	var result = seg._match_lanes()
	assert_eq(result, target, "Match one-way %s" % params[4])

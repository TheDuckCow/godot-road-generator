## This script contains test cases for the road_segment._match_lanes function.
##
## Array format:
## 0 start RoadPoint traffic dir
## 1 end RoadPoint traffic dir
## 2 Start RoadPoint lane types
## 3 Expected results, which itself is an array where each (lane) item is:
##    [LaneType, LaneDir, lane_prior_tag, lane_next_tag]
## 4 Test case label, with a structure of:
##    Direction start > Direction end > expected outcome, where
##    Direction start/end: F=forward lane, R=reverse lane
##    expected outcome: Lanes start to end: F=fast, S=slow, A=add, R=remove
##    and where `|` = direction switch/double yellow (not an actual lane, just a visual aide)

extends "res://addons/gut/test.gd"

const RoadSegment = preload("res://addons/road-generator/road_segment.gd")

var auto_lane_setup = [
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.FAST, RoadPoint.LaneType.FAST],
		[
			# reverse lane stays reverse lane.
			[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.REVERSE, "R0", "R0"],
			# forward lane stays forward lane.
			[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.FORWARD, "F0", "F0"]],
		"RF > RF >> F|F",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.FAST, RoadPoint.LaneType.FAST, RoadPoint.LaneType.SLOW],
		[
			# reverse lane stays reverse lane.
			[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.REVERSE, "R0", "R0"],
			# forward lane stays forward lane.
			[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.FORWARD, "F0", "F0"],
			# outer fowrad lane stays the same.
			[RoadPoint.LaneType.SLOW, RoadPoint.LaneDir.FORWARD, "F1", "F1"]],
		"RFF > RFF >> F|FS",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.FAST, RoadPoint.LaneType.FAST],
		[
			# reverse lane stays the same
			[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.REVERSE, "R0", "R0"],
			# fwd lane in (initially single, then middle) stays the same
			[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.FORWARD, "F0", "F0"],
			# added fwd lane goes from connecting to F0 to F1 next.
			[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneDir.FORWARD, "F0a", "F1"]],
		"RF > RFF >> F|FA",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.FAST, RoadPoint.LaneType.FAST, RoadPoint.LaneType.SLOW],
		[
			# Reverse stays the same lane
			[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.REVERSE, "R0", "R0"],
			# Forward stays the same lane
			[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.FORWARD, "F0", "F0"],
			# The outside fwd lane is removed, so goes from F1-F0
			[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneDir.FORWARD, "F1", "F0r"]],
		"RFF > RF >> F|FR",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.FAST, RoadPoint.LaneType.FAST, RoadPoint.LaneType.SLOW],
		[
			# Reverse outer lane stays
			[RoadPoint.LaneType.SLOW, RoadPoint.LaneDir.REVERSE, "R1", "R1"],
			# Reverse inner lane stays
			[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.REVERSE, "R0", "R0"],
			# Inner fwd lane stays
			[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.FORWARD, "F0", "F0"],
			# Outer fwd lane removed.
			[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneDir.FORWARD, "F1", "F0r"]],
		"RRFF > RRF >> SF|FR",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.FAST, RoadPoint.LaneType.FAST],
		[
			# Reverse lane outer (id=1) stays.
			[RoadPoint.LaneType.SLOW, RoadPoint.LaneDir.REVERSE, "R1", "R1"],
			# Reverse lane inner (id=0) stays.
			[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.REVERSE, "R0", "R0"],
			# Inner forward lane (id=0) stays.
			[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.FORWARD, "F0", "F0"],
			# Forward lane added (id 0 becomes 1 for next segment)
			[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneDir.FORWARD, "F0a", "F1"]],
		"RRF > RRFF >> SF|FA",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.FAST, RoadPoint.LaneType.FAST],
		[
			# The initial reverse lane is removed.
			# TODO: might have this backwards, which side has the 'R1r'
			[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneDir.REVERSE, "R2", "R1r"],
			# Middle reverse (id = 1) remains
			[RoadPoint.LaneType.SLOW, RoadPoint.LaneDir.REVERSE, "R1", "R1"],
			# Inner reverse (id = 0) remains
			[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.REVERSE, "R0", "R0"],
			# Forward lane remains
			[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.FORWARD, "F0", "F0"]],
		"RRRF > RRF >> RSF|F",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.FAST, RoadPoint.LaneType.FAST],
		[
			# Reverse lane added (id 1 -> 2)
			[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneDir.REVERSE, "R1a", "R2"],
			# Middle reverse lane the same
			[RoadPoint.LaneType.SLOW, RoadPoint.LaneDir.REVERSE, "R1", "R1"],
			# Inner reverse lane the same
			[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.REVERSE, "R0", "R0"],
			# Forward lane remains
			[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.FORWARD, "F0", "F0"]],
		"RRF > RRRF >> ASF|F",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.FAST, RoadPoint.LaneType.FAST, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[
			# Reverse lane was removed
			[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneDir.REVERSE, "R2", "R0r"],
			# Reverse lane was removed
			[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneDir.REVERSE, "R1", "R0r"],
			# Revese lane stayed teh same
			[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.REVERSE, "R0", "R0"],
			# Forward lane stayed the same
			[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.FORWARD, "F0", "F0"],
			# Forward inner lane was removed
			[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneDir.FORWARD, "F1", "F0r"],
			# Forward outer lane was removed
			[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneDir.FORWARD, "F2", "F0r"]],
		"RRRFFF > RF >> RRF|FRR",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.FAST, RoadPoint.LaneType.FAST],
		[
			# Outer reverse lane added
			[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneDir.REVERSE, "R0a", "R2"],
			# Middle reverse lane added
			[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneDir.REVERSE, "R0a", "R1"],
			# Inner reverse lane the same
			[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.REVERSE, "R0", "R0"],
			# Inner fast lane the same
			[RoadPoint.LaneType.FAST, RoadPoint.LaneDir.FORWARD, "F0", "F0"],
			# Middle fast lane added
			[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneDir.FORWARD, "F0a", "F1"],
			# Outer fast lane added
			[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneDir.FORWARD, "F0a", "F2"]],
		"RF > RRRFFF >> AAF|FAA",
	],
]

var one_way_lane_setup = [
	[
		[RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.NO_MARKING],
		[[RoadPoint.LaneType.NO_MARKING, RoadPoint.LaneDir.FORWARD, "F0", "F0"]],
		"F > F >> |M",
	],
	[
		[RoadPoint.LaneDir.REVERSE],
		[RoadPoint.LaneDir.REVERSE],
		[RoadPoint.LaneType.NO_MARKING],
		[[RoadPoint.LaneType.NO_MARKING, RoadPoint.LaneDir.REVERSE, "R0", "R0"]],
		"R > R >> M|",
	],
	[
		[RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.NO_MARKING, RoadPoint.LaneType.SLOW],
		[
			# Inner fast lane, since middle si to left of fast
			[RoadPoint.LaneType.NO_MARKING, RoadPoint.LaneDir.FORWARD, "F0", "F0"],
			# Outer fast lane
			[RoadPoint.LaneType.SLOW, RoadPoint.LaneDir.FORWARD, "F1", "F1"]],
		"FF > FF >> |MS",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.MIDDLE],
		[
			# Outer reverse lane the same.
			[RoadPoint.LaneType.SLOW, RoadPoint.LaneDir.REVERSE, "R1", "R1"],
			# Inner reverse lane, since the "divider" is to the rigth
			[RoadPoint.LaneType.MIDDLE, RoadPoint.LaneDir.REVERSE, "R0", "R0"]],
		"RR > RR >> SM|",
	],
	[
		[RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.NO_MARKING, RoadPoint.LaneType.SLOW],
		[
			# Inner fast lane the same
			[RoadPoint.LaneType.NO_MARKING, RoadPoint.LaneDir.FORWARD, "F0", "F0"],
			# Middle forward lane the same
			[RoadPoint.LaneType.SLOW, RoadPoint.LaneDir.FORWARD, "F1", "F1"],
			# Outer forward lane added
			[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneDir.FORWARD, "F1a", "F2"]],
		"FF > FFF >> |MSA",
	],
	[
		[RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.NO_MARKING, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[
			# Inner fast lane the same
			[RoadPoint.LaneType.NO_MARKING, RoadPoint.LaneDir.FORWARD, "F0", "F0"],
			# Middle fast lane the same
			[RoadPoint.LaneType.SLOW, RoadPoint.LaneDir.FORWARD, "F1", "F1"],
			# Outer lane removed
			[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneDir.FORWARD, "F2", "F1r"]],
		"FFF > FF >> |MSR",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.MIDDLE],
		[
			# Reverse lane added
			[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneDir.REVERSE, "R1a", "R2"],
			# Middle lane the same
			[RoadPoint.LaneType.SLOW, RoadPoint.LaneDir.REVERSE, "R1", "R1"],
			# Inner lane the same
			[RoadPoint.LaneType.MIDDLE, RoadPoint.LaneDir.REVERSE, "R0", "R0"]],
		"RR > RRR >> ASM|",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.MIDDLE],
		[
			# Reverse lane removed
			[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneDir.REVERSE, "R2", "R1r"],
			# Middle lane the same
			[RoadPoint.LaneType.SLOW, RoadPoint.LaneDir.REVERSE, "R1", "R1"],
			# Inner lane the same
			[RoadPoint.LaneType.MIDDLE, RoadPoint.LaneDir.REVERSE, "R0", "R0"]],
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

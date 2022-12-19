## This script contains test cases for the road_segment._match_lanes function.
##
## auto_lane_setup array format:
## 0 start point traffic dir
## 1 end point traffic dir
## 2 start point lane types
## 3 expected result
## 4 Test case label, with a structure of:
##    Direction start > Direction end > expected outcome, where
##    Direction start/end: F=forward lane, R=reverse lane
##    expected outcome: Lanes start to end: A=add, R=remove, -=full lane
##    and where `|` = direction switch/double yellow (not an actual lane, just a visual aide)

extends "res://addons/gut/test.gd"
var auto_lane_setup = [
	[
		[RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.REVERSE],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[],
		[],
		"FR > RF >> Empty set due to invalid lane config",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.REVERSE],
		[],
		[],
		"RF > FR >> Empty set due to invalid lane config",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RF > RF >> --",
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM],
		"RFF > RRF >> A--R",
	],

	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RRF > RF >> R--"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RRRF > RF >> RR--"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM],
		"RFF > RF >> --R"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM],
		"RRFF > RF >> R--R"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM],
		"RRRFF > RF >> RR--R"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.TRANSITION_REM],
		"RFFF > RF >> --RR"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.TRANSITION_REM],
		"RRFFF > RF >> R--RR"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.TRANSITION_REM],
		"RRRFFF > RF >> RR--RR"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RF > RRF >> A--"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RRF > RRF >> ---"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RRRF > RRF >> R---"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM],
		"RFF > RRF >> A--R"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM],
		"RRFF > RRF >> ---R"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM],
		"RRRFF > RRF >> R---R"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.TRANSITION_REM],
		"RFFF > RRF >> A--RR"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.TRANSITION_REM],
		"RRFFF > RRF >> ---RR"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.TRANSITION_REM],
		"RRRFFF > RRF >> R---RR"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RF > RRRF >> AA--"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RRF > RRRF >> A---"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RRRF > RRRF >> ----"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM],
		"RFF > RRRF >> AA--R"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM],
		"RRFF > RRRF >> A---R"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM],
		"RRRFF > RRRF >> ----R"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.TRANSITION_REM],
		"RFFF > RRRF >> AA--RR"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.TRANSITION_REM],
		"RRFFF > RRRF >> A---RR"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.TRANSITION_REM],
		"RRRFFF > RRRF >> ----RR"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD],
		"RF > RFF >> --A"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD],
		"RRF > RFF >> R--A"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD],
		"RRRF > RFF >> RR--A"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RFF > RFF >> ---"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RRFF > RFF >> R---"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RRRFF > RFF >> RR---"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM],
		"RFFF > RFF >> ---R"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM],
		"RRFFF > RFF >> R---R"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM],
		"RRRFFF > RFF >> RR---R"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD],
		"RF > RRFF >> A--A"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD],
		"RRF > RRFF >> ---A"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD],
		"RRRF > RRFF >> R---A"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RFF > RRFF >> A---"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RRFF > RRFF >> ----"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RRRFF > RRFF >> R----"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM],
		"RFFF > RRFF >> A---R"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM],
		"RRFFF > RRFF >> ----R"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM],
		"RRRFFF > RRFF >> R----R"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD],
		"RF > RRRFF >> AA--A"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD],
		"RRF > RRRFF >> A---A"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD],
		"RRRF > RRRFF >> ----A"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RFF > RRRFF >> AA---"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RRFF > RRRFF >> A----"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RRRFF > RRRFF >> -----"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM],
		"RFFF > RRRFF >> AA---R"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM],
		"RRFFF > RRRFF >> A----R"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_REM],
		"RRRFFF > RRRFF >> -----R"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.TRANSITION_ADD],
		"RF > RFFF >> --AA"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.TRANSITION_ADD],
		"RRF > RFFF >> R--AA"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.TRANSITION_ADD],
		"RRRF > RFFF >> RR--AA"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD],
		"RFF > RFFF >> ---A"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD],
		"RRFF > RFFF >> R---A"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD],
		"RRRFF > RFFF >> RR---A"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RFFF > RFFF >> ----"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RRFFF > RFFF >> R----"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RRRFFF > RFFF >> RR----"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.TRANSITION_ADD],
		"RF > RRFFF >> A--AA"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.TRANSITION_ADD],
		"RRF > RRFFF >> ---AA"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.TRANSITION_ADD],
		"RRRF > RRFFF >> R---AA"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD],
		"RFF > RRFFF >> A---A"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD],
		"RRFF > RRFFF >> ----A"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD],
		"RRRFF > RRFFF >> R----A"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RFFF > RRFFF >> A----"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RRFFF > RRFFF >> -----"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RRRFFF > RRFFF >> R-----"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.TRANSITION_ADD],
		"RF > RRRFFF >> AA--AA"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.TRANSITION_ADD],
		"RRF > RRRFFF >> A---AA"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.TRANSITION_ADD],
		"RRRF > RRRFFF >> ----AA"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD],
		"RFF > RRRFFF >> AA---A"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD],
		"RRFF > RRRFFF >> A----A"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD],
		"RRRFF > RRRFFF >> -----A"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RFFF > RRRFFF >> AA----"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RRFFF > RRRFFF >> A-----"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		"RRRFFF > RRRFFF >> ------"
	],
	[
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD],
		[RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW],
		[RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.TRANSITION_REM, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW, RoadPoint.LaneType.TRANSITION_ADD, RoadPoint.LaneType.TRANSITION_ADD],
		"RRRRFF > RRFFFF >> RR----AA"
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

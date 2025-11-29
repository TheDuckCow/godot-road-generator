@tool
extends Resource
class_name RoadDecoration

enum Side {
	FORWARD,
	REVERSE,
	BOTH
}

const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")

@export var side: RoadCurb.Side = RoadCurb.Side.REVERSE
@export var offset_start: float = 0.0
@export var offset_end: float = 0.0
@export var offset_lateral: float = -0.5

func setup(segment: RoadSegment) -> void:
	pass

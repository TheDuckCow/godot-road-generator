@tool
extends Resource
class_name RoadDecoration

const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")

@export var on_forward: bool = true
@export var on_reverse: bool = true


func setup(segment: RoadSegment) -> void:
	pass

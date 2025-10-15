@tool
extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass
	var intersection: RoadIntersection = $RoadManager/RoadTempHardcoding/RoadIntersection
	intersection.container = $RoadManager/RoadTempHardcoding

	# print("Temp hardcoding done.")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

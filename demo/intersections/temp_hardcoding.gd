@tool
extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:

	var edges: Array[RoadPoint] = []
	edges.append($RoadManager/RoadTempHardcoding/RP_001)
	edges.append($RoadManager/RoadTempHardcoding/RP_004)
	edges.append($RoadManager/RoadTempHardcoding/RP_006)
	var intersection: RoadIntersection = $RoadManager/RoadTempHardcoding/RoadIntersection
	intersection.container = $RoadManager/RoadTempHardcoding
	intersection.edge_points = edges
	intersection.refresh_intersection_mesh()

	print("Temp hardcoding done.")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

@tool
extends Node3D

@export var add_interactive_rp_toggle: bool = false:
	set(v):
		add_interactive_rp_toggle = v
		$RoadManager/RoadTempHardcoding/RoadIntersection.add_branch($RoadManager/RoadTempHardcoding/InteractiveRoadPoint)

@export var remove_interactive_rp_toggle: bool = false:
	set(v):
		remove_interactive_rp_toggle = v
		$RoadManager/RoadTempHardcoding/RoadIntersection.remove_branch($RoadManager/RoadTempHardcoding/InteractiveRoadPoint)

@export var sort_temp_toggle: bool = false:
	set(v):
		sort_temp_toggle = v
		$RoadManager/RoadTempHardcoding/RoadIntersection.sort_branches()



# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass
	var intersection: RoadIntersection = $RoadManager/RoadTempHardcoding/RoadIntersection
	intersection.container = $RoadManager/RoadTempHardcoding

	# print("Temp hardcoding done.")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

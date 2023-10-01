## Center point of an intersection
##
## Should be contained within a RoadContainer and a sibling to 1+ RoadPoints
tool
class_name RoadIntersection, "../resources/road_intersection.png"
extends Spatial


# ------------------------------------------------------------------------------
# Setup and export setter/getters
# ------------------------------------------------------------------------------


func _get_configuration_warning() -> String:
	var par = get_parent()
	if par.has_method("is_road_container"):
		return ""
	else:
		return "Intersection should be a direct child of a RoadContainer"


# Workaround for cyclic typing
func is_road_intersection() -> bool:
	return true
